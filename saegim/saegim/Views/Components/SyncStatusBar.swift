//
//  SyncStatusBar.swift
//  saegim
//
//  Global compact sync status indicator
//

import SwiftUI

struct SyncStatusBar: View {
    @ObservedObject private var syncState = SyncStateManager.shared

    @State private var showingDetail = false

    var body: some View {
        Button {
            showingDetail.toggle()
        } label: {
            HStack(spacing: 6) {
                SyncStatusIcon(phase: syncState.phase, isOnline: syncState.isOnline)

                // Show pending count when syncing or has pending changes
                if syncState.pendingChangesCount > 0 {
                    Text("\(syncState.pendingChangesCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                // Error badge
                if !syncState.errorQueue.isEmpty {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingDetail) {
            SyncStatusDetailView()
        }
        .help(syncState.phase.description)
    }
}

#Preview {
    SyncStatusBar()
        .padding()
}
