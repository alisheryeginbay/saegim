//
//  SettingsView_iOS.swift
//  saegim
//
//  iOS settings view
//

import SwiftUI
import Supabase

struct SettingsView_iOS: View {
    @EnvironmentObject private var supabase: SupabaseManager
    @EnvironmentObject private var database: DatabaseManager
    @EnvironmentObject private var repository: DataRepository
    @ObservedObject private var syncState = SyncStateManager.shared

    @AppStorage("showTimer") private var showTimer = true
    @AppStorage("autoPlayAudio") private var autoPlayAudio = false

    @State private var isSigningOut = false

    var body: some View {
        Form {
            Section("Study Session") {
                Toggle("Show session timer", isOn: $showTimer)
                Toggle("Auto-play audio", isOn: $autoPlayAudio)
            }

            Section("Account") {
                if let user = supabase.currentUser {
                    HStack {
                        Text("Email")
                        Spacer()
                        Text(user.email ?? "Unknown")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Sync") {
                // Status row
                HStack {
                    SyncStatusIcon(phase: syncState.phase, isOnline: syncState.isOnline)
                    Text(syncState.phase.description)
                    Spacer()
                    if let lastSync = syncState.lastSyncTime {
                        Text(lastSync, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Network status
                if !syncState.isOnline {
                    HStack {
                        Image(systemName: "wifi.slash")
                            .foregroundStyle(.orange)
                        Text("No internet connection")
                            .foregroundStyle(.orange)
                    }
                }

                // Sync errors (for troubleshooting)
                if !syncState.errorQueue.isEmpty {
                    DisclosureGroup("Issues (\(syncState.errorQueue.count))") {
                        ForEach(syncState.errorQueue.prefix(5)) { error in
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.red)
                                    .font(.caption)
                                Text(error.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Spacer()
                                if error.isRetryable {
                                    Button("Retry") {
                                        Task { await syncState.retryFailed(error) }
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

                        Button("Clear All") {
                            syncState.clearErrors()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    signOut()
                } label: {
                    if isSigningOut {
                        HStack {
                            ProgressView()
                            Text("Signing out...")
                        }
                    } else {
                        Text("Sign Out")
                    }
                }
                .disabled(isSigningOut)
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Algorithm")
                    Spacer()
                    Text("FSRS v6")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                VStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)

                    Text("Saegim")
                        .font(.headline)

                    Text("A native flashcard app using spaced repetition to help you learn and remember anything.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
    }

    private func signOut() {
        isSigningOut = true
        Task {
            do {
                repository.stopWatching()
                SyncStateManager.shared.stopNetworkMonitoring()
                await database.disconnect()
                try await supabase.signOut()
            } catch {
                print("Sign out failed: \(error)")
            }
            isSigningOut = false
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView_iOS()
            .navigationTitle("Settings")
    }
}
