//
//  ToastManager.swift
//  saegim
//
//  Toast notification queue management
//

import Foundation
import Combine

// MARK: - Toast Types

enum ToastType {
    case success
    case error
    case warning
    case info

    var systemImage: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let type: ToastType
    let title: String
    let message: String?
    let actionLabel: String?
    let action: (() -> Void)?

    init(
        type: ToastType,
        title: String,
        message: String? = nil,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.type = type
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.action = action
    }

    static func == (lhs: Toast, rhs: Toast) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - ToastManager

@MainActor
final class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published private(set) var currentToast: Toast?

    private var queue: [Toast] = []
    private var dismissTask: Task<Void, Never>?
    private let displayDuration: TimeInterval = 4.0

    private init() {}

    /// Show a toast notification
    func show(_ toast: Toast) {
        queue.append(toast)
        showNextIfNeeded()
    }

    /// Show a sync error toast with retry action
    func showSyncError(_ error: SyncError) {
        let toast = Toast(
            type: .error,
            title: "Sync Failed",
            message: error.message,
            actionLabel: error.isRetryable ? "Retry" : nil,
            action: error.isRetryable ? {
                Task { @MainActor in
                    await SyncStateManager.shared.retryFailed(error)
                }
            } : nil
        )
        show(toast)
    }

    /// Show offline notification
    func showOffline() {
        show(Toast(
            type: .warning,
            title: "You're Offline",
            message: "Changes will sync when connected"
        ))
    }

    /// Show online restored notification
    func showOnlineRestored() {
        show(Toast(
            type: .info,
            title: "Back Online",
            message: "Syncing your changes..."
        ))
    }

    /// Dismiss current toast
    func dismiss() {
        dismissTask?.cancel()
        currentToast = nil

        // Show next toast after brief delay
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            showNextIfNeeded()
        }
    }

    // MARK: - Private

    private func showNextIfNeeded() {
        guard currentToast == nil, !queue.isEmpty else { return }

        currentToast = queue.removeFirst()
        scheduleDismiss()
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(displayDuration * 1_000_000_000))
            if !Task.isCancelled {
                dismiss()
            }
        }
    }
}
