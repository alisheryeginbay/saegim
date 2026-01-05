//
//  SyncStatusDetailView.swift
//  saegim
//
//  Detailed sync status popover view
//

import SwiftUI

struct SyncStatusDetailView: View {
    @ObservedObject private var syncState = SyncStateManager.shared

    @State private var isSyncing = false

    private var statusTitle: String {
        if !syncState.isOnline {
            return "Offline"
        }

        switch syncState.phase {
        case .idle:
            return "Ready"
        case .connecting:
            return "Connecting..."
        case .uploading:
            return "Syncing..."
        case .downloading:
            return "Downloading..."
        case .completed:
            return "Synced"
        case .failed:
            return "Sync Failed"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                SyncStatusIcon(phase: syncState.phase, isOnline: syncState.isOnline)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.headline)

                    if let lastSync = syncState.lastSyncTime {
                        Text("Last synced \(lastSync, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            Divider()

            // Stats
            VStack(alignment: .leading, spacing: 8) {
                if syncState.pendingChangesCount > 0 {
                    Label("\(syncState.pendingChangesCount) changes pending", systemImage: "arrow.up.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !syncState.isOnline {
                    Label("No internet connection", systemImage: "wifi.slash")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }

            // Error list
            if !syncState.errorQueue.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Failed Operations")
                        .font(.subheadline.weight(.medium))

                    ForEach(syncState.errorQueue.prefix(5)) { error in
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.red)

                            Text(error.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Spacer()

                            if error.isRetryable {
                                Button("Retry") {
                                    Task {
                                        await syncState.retryFailed(error)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        }
                    }

                    if syncState.errorQueue.count > 5 {
                        Text("+ \(syncState.errorQueue.count - 5) more...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            // Actions
            HStack {
                Button {
                    syncNow()
                } label: {
                    HStack(spacing: 4) {
                        if isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text("Sync Now")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isSyncing || syncState.phase.isActive)

                Spacer()

                if !syncState.errorQueue.isEmpty {
                    Button("Clear Errors") {
                        syncState.clearErrors()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .frame(width: 300)
    }

    private func syncNow() {
        isSyncing = true
        Task {
            defer { isSyncing = false }
            do {
                try await DatabaseManager.shared.forceSync()
            } catch {
                // Error is already handled by DatabaseManager
            }
        }
    }
}

#Preview {
    SyncStatusDetailView()
}
