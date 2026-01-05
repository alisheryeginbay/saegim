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
            } catch {
                throw error
            }
        }

        try await batch.complete()
    }

    private func upsertRecord(_ op: CrudEntry, client: SupabaseClient) async throws {
        var data = op.opData ?? [:]
        data["id"] = op.id

        try await client
            .from(op.table)
            .upsert(data)
            .execute()
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

        // Connect to PowerSync service (don't fail if sync connection fails)
        do {
            try await db.connect(connector: connector!)
            isConnected = true
            syncStatus = .synced
        } catch {
            // Sync failed but local database still works
            isConnected = false
            syncStatus = .error("Connection failed: \(error.localizedDescription)")
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
        try await db.connect(connector: connector)
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
