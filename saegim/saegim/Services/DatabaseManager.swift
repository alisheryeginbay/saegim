//
//  DatabaseManager.swift
//  saegim
//
//  PowerSync database setup and synchronization management
//

import Foundation
import Combine
@preconcurrency import PowerSync
import Supabase

// MARK: - PowerSync Schema Definition

/// Schema for the local PowerSync SQLite database
let powerSyncSchema = Schema(
    Table(
        name: "decks",
        columns: [
            .text("user_id"),
            .text("parent_id"),
            .text("name"),
            .text("description"),
            .text("created_at"),
            .text("modified_at")
        ]
    ),
    Table(
        name: "cards",
        columns: [
            .text("user_id"),
            .text("deck_id"),
            .text("front"),
            .text("back"),
            .real("stability"),
            .real("difficulty"),
            .integer("state"),
            .integer("lapses"),
            .text("next_review_date"),
            .text("last_review_date"),
            .integer("total_reviews"),
            .integer("correct_reviews"),
            .text("created_at"),
            .text("modified_at")
        ]
    ),
    Table(
        name: "media",
        columns: [
            .text("user_id"),
            .text("hash"),
            .text("format"),
            .text("storage_path"),
            .integer("size_bytes"),
            .text("created_at")
        ]
    )
)

// MARK: - Supabase PowerSync Connector

/// Connector that bridges PowerSync with Supabase backend
final class SupabaseConnector: PowerSyncBackendConnector {

    nonisolated override init() {
        super.init()
    }

    /// Fetch credentials for PowerSync authentication
    override func fetchCredentials() async throws -> PowerSync.PowerSyncCredentials {
        let supabase = await SupabaseManager.shared

        // Wait for session check to complete (max 5 seconds)
        var attempts = 0
        while await supabase.isLoading && attempts < 50 {
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            attempts += 1
        }

        let userId = await SupabaseManager.shared.userId
        guard let userId = userId else {
            throw AuthError.notAuthenticated
        }

        let token = try await SupabaseManager.shared.getAccessToken()

        return PowerSync.PowerSyncCredentials(
            endpoint: SupabaseConfig.powerSyncURL,
            token: token,
            userId: userId.uuidString
        )
    }

    /// Upload local changes to Supabase
    override func uploadData(database: any PowerSyncDatabaseProtocol) async throws {
        guard let batch = try await database.getCrudBatch() else {
            return
        }

        let client = await SupabaseManager.shared.client
        let totalOperations = batch.crud.count
        var completedOperations = 0
        var failedOperations: [SyncError] = []

        // Update phase to uploading
        await SyncStateManager.shared.setPhase(.uploading(pending: totalOperations, total: totalOperations))

        for operation in batch.crud {
            do {
                switch operation.op {
                case .put:
                    try await upsertRecord(operation, client: client)
                case .patch:
                    try await updateRecord(operation, client: client)
                case .delete:
                    try await deleteRecord(operation, client: client)
                }

                completedOperations += 1
                await SyncStateManager.shared.confirmSynced()
                await SyncStateManager.shared.updateUploadProgress(
                    completed: completedOperations,
                    total: totalOperations
                )
            } catch {
                // Record the error but continue processing other operations
                // Mark as non-retryable since batch.complete() removes it from queue
                let syncError = SyncError(
                    id: UUID(),
                    operation: "\(operation.op):\(operation.table):\(operation.id)",
                    message: error.localizedDescription,
                    timestamp: Date(),
                    isRetryable: false
                )
                failedOperations.append(syncError)
                NSLog("Sync operation failed: \(operation.table)/\(operation.id) - \(error)")
            }
        }

        // Report all failed operations
        for error in failedOperations {
            await SyncStateManager.shared.reportError(error)
            await ToastManager.shared.showSyncError(error)
        }

        // Always complete the batch to remove successful operations
        // Failed operations will be retried through the error queue
        try await batch.complete()

        if failedOperations.isEmpty {
            await SyncStateManager.shared.setPhase(.completed)
        }
    }

    private func upsertRecord(_ op: CrudEntry, client: SupabaseClient) async throws {
        var data = op.opData ?? [:]
        data["id"] = op.id

        // Fetch current server state to detect conflicts
        let response: PostgrestResponse<[[String: AnyJSON]]> = try await client
            .from(op.table)
            .select()
            .eq("id", value: op.id)
            .execute()

        var resolution: String?

        // Check if record exists on server
        if let serverRow = response.value.first {
            // Convert AnyJSON to [String: Any] for comparison
            let serverData = serverRow.mapValues { $0.value }

            // Detect conflict and merge if needed
            resolution = applyMergeIfConflict(
                table: op.table,
                localData: &data,
                serverData: serverData
            )
        }

        // Upsert the (potentially merged) data
        try await client
            .from(op.table)
            .upsert(data)
            .execute()

        // Log conflict if one was resolved
        if let resolution = resolution {
            await SyncStateManager.shared.logConflict(
                table: op.table,
                recordId: op.id,
                resolution: resolution
            )
        }
    }

    /// Detect conflict and apply merge to localData in place
    /// - Returns: Resolution description if conflict was resolved, nil if no conflict
    private func applyMergeIfConflict<T>(
        table: String,
        localData: inout [String: T],
        serverData: [String: Any]
    ) -> String? {
        let dateFormatter = ISO8601DateFormatter()

        // Parse timestamps
        let localModified = (localData["modified_at"] as? String)
            .flatMap { dateFormatter.date(from: $0) }
        let serverModified = (serverData["modified_at"] as? String)
            .flatMap { dateFormatter.date(from: $0) }

        // Only conflict if server has data newer than our local version
        guard let serverDate = serverModified,
              let localDate = localModified,
              serverDate > localDate else {
            return nil  // No conflict - local is newer or equal
        }

        // Server is newer - we have a conflict, apply merge strategy
        switch table {
        case "cards":
            return applyCardMerge(localData: &localData, serverData: serverData)
        case "decks":
            return applyDeckMerge(localData: &localData, serverData: serverData)
        default:
            // For other tables, server wins (standard LWW)
            for (key, value) in serverData {
                if let typedValue = value as? T {
                    localData[key] = typedValue
                }
            }
            return "server_wins"
        }
    }

    /// Apply card merge in place
    private func applyCardMerge<T>(
        localData: inout [String: T],
        serverData: [String: Any]
    ) -> String {
        // Convert to dictionaries for CardModel
        var localDict: [String: Any] = [:]
        for (key, value) in localData {
            localDict[key] = value
        }

        let localCard = CardModel(row: localDict)
        let serverCard = CardModel(row: serverData)

        let (merged, resolution) = CardModel.merge(local: localCard, server: serverCard)
        let dict = merged.toDict()

        // Update localData with merged values
        for (key, value) in dict {
            if let v = value, let typedValue = v as? T {
                localData[key] = typedValue
            }
        }

        return resolution.description
    }

    /// Apply deck merge in place
    private func applyDeckMerge<T>(
        localData: inout [String: T],
        serverData: [String: Any]
    ) -> String {
        // Convert to dictionaries for DeckModel
        var localDict: [String: Any] = [:]
        for (key, value) in localData {
            localDict[key] = value
        }

        let localDeck = DeckModel(row: localDict)
        let serverDeck = DeckModel(row: serverData)

        let (merged, hadConflict) = DeckModel.merge(local: localDeck, server: serverDeck)
        let dict = merged.toDict()

        // Update localData with merged values
        for (key, value) in dict {
            if let v = value, let typedValue = v as? T {
                localData[key] = typedValue
            }
        }

        return hadConflict ? "server_wins" : "no_change"
    }

    private func updateRecord(_ op: CrudEntry, client: SupabaseClient) async throws {
        guard let data = op.opData else { return }

        try await client
            .from(op.table)
            .update(data)
            .eq("id", value: op.id)
            .execute()
    }

    private func deleteRecord(_ op: CrudEntry, client: SupabaseClient) async throws {
        try await client
            .from(op.table)
            .delete()
            .eq("id", value: op.id)
            .execute()
    }
}

// MARK: - Database Manager

/// Manages the PowerSync database lifecycle
@MainActor
final class DatabaseManager: ObservableObject {
    static let shared = DatabaseManager()

    /// The PowerSync database instance
    private(set) var database: (any PowerSyncDatabaseProtocol)?

    /// Connector for Supabase communication
    private var connector: SupabaseConnector?

    /// Whether the database is connected and syncing
    @Published private(set) var isConnected = false

    /// Current sync status
    @Published private(set) var syncStatus: SyncStatus = .idle

    private init() {}

    /// Initialize and connect the database
    /// - Parameter supabase: The Supabase manager instance
    func initialize(supabase: SupabaseManager) async throws {
        // Create database instance
        let db = PowerSyncDatabase(
            schema: powerSyncSchema,
            dbFilename: "saegim.sqlite"
        )

        // Set database immediately so local operations work (offline-first)
        database = db
        connector = SupabaseConnector()

        // Update state to connecting
        await SyncStateManager.shared.setPhase(.connecting)
        syncStatus = .syncing

        // Connect to PowerSync service (don't fail if sync connection fails)
        do {
            try await db.connect(connector: connector!)
            isConnected = true
            syncStatus = .synced
            await SyncStateManager.shared.setPhase(.completed)
        } catch {
            // Sync failed but local database still works
            isConnected = false
            syncStatus = .error("Connection failed: \(error.localizedDescription)")

            let syncError = SyncStateManager.createError(
                operation: "connect",
                table: "database",
                id: "powersync",
                error: error
            )
            await SyncStateManager.shared.reportError(syncError)
            NSLog("PowerSync connection failed (offline mode): \(error)")
        }
    }

    /// Disconnect from PowerSync
    func disconnect() async {
        try? await database?.disconnect()
        database = nil
        connector = nil
        isConnected = false
        syncStatus = .idle
    }

    /// Force a sync with the server
    func forceSync() async throws {
        guard let db = database, let connector = connector else { return }

        await SyncStateManager.shared.setPhase(.connecting)
        syncStatus = .syncing

        do {
            try await db.connect(connector: connector)
            isConnected = true
            syncStatus = .synced
            await SyncStateManager.shared.setPhase(.completed)
        } catch {
            isConnected = false
            syncStatus = .error("Sync failed: \(error.localizedDescription)")

            let syncError = SyncStateManager.createError(
                operation: "sync",
                table: "database",
                id: "powersync",
                error: error
            )
            await SyncStateManager.shared.reportError(syncError)
            throw error
        }
    }

    /// Update sync status manually
    func updateSyncStatus(_ status: SyncStatus) {
        self.syncStatus = status
    }
}

// MARK: - Sync Status

enum SyncStatus {
    case idle
    case syncing
    case synced
    case offline
    case error(String)

    var description: String {
        switch self {
        case .idle: return "Not connected"
        case .syncing: return "Syncing..."
        case .synced: return "Synced"
        case .offline: return "Offline"
        case .error(let message): return "Error: \(message)"
        }
    }

    var systemImage: String {
        switch self {
        case .idle: return "icloud.slash"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .synced: return "checkmark.icloud"
        case .offline: return "icloud.slash"
        case .error: return "exclamationmark.icloud"
        }
    }
}
