//
//  SyncStateManager.swift
//  saegim
//
//  Centralized sync state tracking with network monitoring and retry logic
//

import Combine
import Foundation
import Network

// MARK: - Sync Types

/// Represents the current phase of sync operations
enum SyncPhase: Equatable {
    case idle
    case connecting
    case uploading(pending: Int, total: Int)
    case downloading
    case completed
    case failed(SyncError)

    var description: String {
        switch self {
        case .idle:
            return "Ready"
        case .connecting:
            return "Connecting..."
        case .uploading(let pending, let total):
            if total > 0 {
                return "Syncing \(total - pending)/\(total)..."
            }
            return "Syncing..."
        case .downloading:
            return "Downloading..."
        case .completed:
            return "Synced"
        case .failed(let error):
            return "Failed: \(error.message)"
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            return "checkmark.icloud"
        case .connecting, .uploading, .downloading:
            return "arrow.triangle.2.circlepath"
        case .completed:
            return "checkmark.icloud.fill"
        case .failed:
            return "exclamationmark.icloud"
        }
    }

    var isActive: Bool {
        switch self {
        case .connecting, .uploading, .downloading:
            return true
        default:
            return false
        }
    }
}

/// Represents a sync operation that failed
struct SyncError: Identifiable, Equatable {
    let id: UUID
    let operation: String
    let message: String
    let timestamp: Date
    let isRetryable: Bool

    static func == (lhs: SyncError, rhs: SyncError) -> Bool {
        lhs.id == rhs.id
    }
}

/// Represents a conflict that was automatically resolved during sync
struct ConflictRecord: Identifiable, Equatable {
    let id: UUID
    let table: String
    let recordId: String
    let resolution: String
    let timestamp: Date

    init(table: String, recordId: String, resolution: String) {
        self.id = UUID()
        self.table = table
        self.recordId = recordId
        self.resolution = resolution
        self.timestamp = Date()
    }
}

// MARK: - SyncStateManager

/// Manages sync state, network monitoring, and retry logic
@MainActor
final class SyncStateManager: ObservableObject {
    static let shared = SyncStateManager()

    // MARK: - Published State

    /// Current sync phase
    @Published private(set) var phase: SyncPhase = .idle

    /// Number of local changes pending sync
    @Published private(set) var pendingChangesCount: Int = 0

    /// Last successful sync timestamp
    @Published private(set) var lastSyncTime: Date?

    /// Whether device has network connectivity
    @Published private(set) var isOnline: Bool = true

    /// Queue of failed operations awaiting retry
    @Published private(set) var errorQueue: [SyncError] = []

    /// Number of conflicts auto-resolved this session
    @Published private(set) var conflictsResolved: Int = 0

    /// History of resolved conflicts (capped at 100)
    @Published private(set) var conflictHistory: [ConflictRecord] = []

    // MARK: - Private Properties

    private let maxConflictHistorySize = 100

    private var networkMonitor: NWPathMonitor?
    private var networkQueue = DispatchQueue(label: "com.saegim.networkMonitor")
    private var retryTasks: [UUID: Task<Void, Never>] = [:]

    // Retry configuration
    private let maxRetries = 3
    private let baseRetryDelay: TimeInterval = 2.0
    private let maxErrorQueueSize = 50

    // MARK: - Initialization

    private init() {}

    // MARK: - Network Monitoring

    /// Start monitoring network connectivity
    func startNetworkMonitoring() {
        guard networkMonitor == nil else { return }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                let wasOffline = !self.isOnline
                self.isOnline = path.status == .satisfied

                // Auto-retry when coming back online
                if wasOffline && self.isOnline {
                    await self.retryAllFailed()
                }
            }
        }
        monitor.start(queue: networkQueue)
        networkMonitor = monitor
    }

    /// Stop network monitoring
    func stopNetworkMonitoring() {
        networkMonitor?.cancel()
        networkMonitor = nil
    }

    // MARK: - Sync State Management

    /// Update the current sync phase
    func setPhase(_ phase: SyncPhase) {
        self.phase = phase

        if case .completed = phase {
            lastSyncTime = Date()
        }
    }

    /// Track a pending local change
    func trackPendingChange() {
        pendingChangesCount += 1
    }

    /// Confirm a change was synced successfully
    func confirmSynced() {
        if pendingChangesCount > 0 {
            pendingChangesCount -= 1
        }
    }

    /// Reset pending count (e.g., after full sync)
    func resetPendingCount() {
        pendingChangesCount = 0
    }

    // MARK: - Conflict Tracking

    /// Log a conflict that was automatically resolved
    func logConflict(table: String, recordId: String, resolution: String) {
        conflictsResolved += 1

        let record = ConflictRecord(table: table, recordId: recordId, resolution: resolution)

        // Cap history size
        if conflictHistory.count >= maxConflictHistorySize {
            conflictHistory.removeFirst()
        }
        conflictHistory.append(record)
    }

    /// Clear conflict history (e.g., on logout)
    func clearConflictHistory() {
        conflictsResolved = 0
        conflictHistory.removeAll()
    }

    /// Update progress during upload
    func updateUploadProgress(completed: Int, total: Int) {
        phase = .uploading(pending: total - completed, total: total)
    }

    // MARK: - Error Management

    /// Report a sync error
    func reportError(_ error: SyncError) {
        // Prevent queue from growing too large
        if errorQueue.count >= maxErrorQueueSize {
            errorQueue.removeFirst()
        }
        errorQueue.append(error)
        phase = .failed(error)
    }

    /// Remove an error from the queue
    func removeError(_ error: SyncError) {
        errorQueue.removeAll { $0.id == error.id }
        retryTasks[error.id]?.cancel()
        retryTasks.removeValue(forKey: error.id)
    }

    /// Clear all errors
    func clearErrors() {
        retryTasks.values.forEach { $0.cancel() }
        retryTasks.removeAll()
        errorQueue.removeAll()

        if case .failed = phase {
            phase = .idle
        }
    }

    // MARK: - Retry Logic

    /// Retry a specific failed operation
    func retryFailed(_ error: SyncError) async {
        guard error.isRetryable else { return }

        // Cancel existing retry task if any
        retryTasks[error.id]?.cancel()

        let task = Task { [weak self] in
            guard let self = self else { return }

            var attempts = 0
            while attempts < self.maxRetries && !Task.isCancelled {
                attempts += 1

                // Exponential backoff: 2s, 4s, 8s
                let delay = self.baseRetryDelay * pow(2.0, Double(attempts - 1))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                if Task.isCancelled { return }

                do {
                    // Trigger a force sync to retry pending operations
                    try await DatabaseManager.shared.forceSync()

                    // Success - remove from error queue
                    await MainActor.run {
                        self.errorQueue.removeAll { $0.id == error.id }
                        self.retryTasks.removeValue(forKey: error.id)

                        if self.errorQueue.isEmpty {
                            self.phase = .completed
                            self.lastSyncTime = Date()
                        }
                    }

                    // Notify success
                    await ToastManager.shared.show(Toast(
                        type: .success,
                        title: "Sync Recovered",
                        message: "Changes have been synced"
                    ))
                    return
                } catch {
                    // Continue retrying
                    NSLog("Retry attempt \(attempts) failed: \(error)")
                }
            }

            // Max retries exceeded
            if !Task.isCancelled {
                await ToastManager.shared.show(Toast(
                    type: .error,
                    title: "Sync Failed",
                    message: "Please try again later"
                ))
            }
        }

        retryTasks[error.id] = task
    }

    /// Retry all failed operations
    func retryAllFailed() async {
        let retryableErrors = errorQueue.filter { $0.isRetryable }
        for error in retryableErrors {
            await retryFailed(error)
        }
    }

    // MARK: - Helpers

    /// Determine if an error is retryable
    static func isRetryableError(_ error: Error) -> Bool {
        let nsError = error as NSError

        // Network errors are retryable
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet:
                return true
            default:
                return false
            }
        }

        // Server errors (5xx) are retryable
        if let httpCode = nsError.userInfo["HTTPStatusCode"] as? Int {
            return httpCode >= 500 && httpCode < 600
        }

        // Default to retryable for unknown errors
        return true
    }

    /// Create a SyncError from a failed operation
    static func createError(
        operation: String,
        table: String,
        id: String,
        error: Error
    ) -> SyncError {
        SyncError(
            id: UUID(),
            operation: "\(operation):\(table):\(id)",
            message: error.localizedDescription,
            timestamp: Date(),
            isRetryable: isRetryableError(error)
        )
    }
}
