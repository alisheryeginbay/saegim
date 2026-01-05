//
//  OfflineBanner.swift
//  saegim
//
//  Offline mode indicator banner
//

import SwiftUI

struct OfflineBanner: View {
    @ObservedObject private var syncState = SyncStateManager.shared

    @State private var isDismissed = false

    var body: some View {
        if !syncState.isOnline && !isDismissed {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.caption)

                Text("You're offline. Changes will sync when connected.")
                    .font(.caption)

                Spacer()

                Button {
                    withAnimation {
                        isDismissed = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.orange.opacity(0.15))
            .foregroundStyle(.orange)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

#Preview {
    VStack {
        OfflineBanner()
        Spacer()
    }
}
