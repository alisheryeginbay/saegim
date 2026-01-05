//
//  ToastView.swift
//  saegim
//
//  Toast notification component with action support
//

import SwiftUI

struct ToastView: View {
    let toast: Toast
    let onDismiss: () -> Void

    private var iconColor: Color {
        switch toast.type {
        case .success: return .green
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.type.systemImage)
                .font(.title3)
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.subheadline.weight(.medium))

                if let message = toast.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if let actionLabel = toast.actionLabel, toast.action != nil {
                Button(actionLabel) {
                    toast.action?()
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Toast Container Modifier

struct ToastContainerModifier: ViewModifier {
    @ObservedObject private var toastManager = ToastManager.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = toastManager.currentToast {
                    ToastView(toast: toast) {
                        toastManager.dismiss()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
            .animation(.spring(duration: 0.3), value: toastManager.currentToast?.id)
    }
}

extension View {
    /// Add toast notification support to this view
    func withToasts() -> some View {
        modifier(ToastContainerModifier())
    }
}

#Preview {
    VStack {
        ToastView(
            toast: Toast(type: .error, title: "Sync Failed", message: "Network connection lost", actionLabel: "Retry"),
            onDismiss: {}
        )
        .padding()

        ToastView(
            toast: Toast(type: .success, title: "Sync Complete", message: nil),
            onDismiss: {}
        )
        .padding()

        ToastView(
            toast: Toast(type: .warning, title: "You're Offline", message: "Changes will sync when connected"),
            onDismiss: {}
        )
        .padding()
    }
}
