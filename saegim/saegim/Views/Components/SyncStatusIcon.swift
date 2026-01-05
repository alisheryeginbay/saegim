//
//  SyncStatusIcon.swift
//  saegim
//
//  Animated sync status icon component
//

import SwiftUI

struct SyncStatusIcon: View {
    let phase: SyncPhase
    let isOnline: Bool

    @State private var isAnimating = false

    private var iconColor: Color {
        if !isOnline {
            return .orange
        }

        switch phase {
        case .idle, .completed:
            return .green
        case .connecting, .uploading, .downloading:
            return .blue
        case .failed:
            return .red
        }
    }

    var body: some View {
        Group {
            switch phase {
            case .idle where isOnline:
                Image(systemName: "checkmark.icloud")
                    .foregroundStyle(iconColor)

            case .idle where !isOnline:
                Image(systemName: "icloud.slash")
                    .foregroundStyle(iconColor)

            case .completed:
                Image(systemName: "checkmark.icloud.fill")
                    .foregroundStyle(iconColor)

            case .connecting, .uploading, .downloading:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(iconColor)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(
                        .linear(duration: 1.0).repeatForever(autoreverses: false),
                        value: isAnimating
                    )
                    .onAppear { isAnimating = true }
                    .onDisappear { isAnimating = false }

            case .failed:
                Image(systemName: "exclamationmark.icloud")
                    .foregroundStyle(iconColor)

            default:
                Image(systemName: "icloud")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.body)
        .onChange(of: phase) { _, newPhase in
            isAnimating = newPhase.isActive
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            SyncStatusIcon(phase: .idle, isOnline: true)
            Text("Idle (Online)")
        }
        HStack(spacing: 20) {
            SyncStatusIcon(phase: .idle, isOnline: false)
            Text("Idle (Offline)")
        }
        HStack(spacing: 20) {
            SyncStatusIcon(phase: .uploading(pending: 3, total: 5), isOnline: true)
            Text("Uploading")
        }
        HStack(spacing: 20) {
            SyncStatusIcon(phase: .completed, isOnline: true)
            Text("Completed")
        }
        HStack(spacing: 20) {
            SyncStatusIcon(phase: .failed(SyncError(
                id: UUID(),
                operation: "test",
                message: "Test error",
                timestamp: Date(),
                isRetryable: true
            )), isOnline: true)
            Text("Failed")
        }
    }
    .padding()
}
