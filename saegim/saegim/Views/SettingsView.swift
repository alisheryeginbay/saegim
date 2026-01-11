//
//  SettingsView.swift
//  saegim
//

import SwiftUI
import Supabase

struct SettingsView: View {
    @EnvironmentObject private var supabase: SupabaseManager
    @EnvironmentObject private var database: DatabaseManager
    @EnvironmentObject private var repository: DataRepository

    @AppStorage("dailyNewCards") private var dailyNewCards = 20
    @AppStorage("dailyReviewCards") private var dailyReviewCards = 100
    @AppStorage("showTimer") private var showTimer = true
    @AppStorage("autoPlayAudio") private var autoPlayAudio = false

    var body: some View {
        TabView {
            GeneralSettingsView(
                dailyNewCards: $dailyNewCards,
                dailyReviewCards: $dailyReviewCards
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }

            StudySettingsView(
                showTimer: $showTimer,
                autoPlayAudio: $autoPlayAudio
            )
            .tabItem {
                Label("Study", systemImage: "book")
            }

            AccountSettingsView()
            .tabItem {
                Label("Account", systemImage: "person.circle")
            }

            AboutView()
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .frame(width: 450, height: 350)
    }
}

struct GeneralSettingsView: View {
    @Binding var dailyNewCards: Int
    @Binding var dailyReviewCards: Int

    var body: some View {
        Form {
            Section("Daily Limits") {
                Stepper(value: $dailyNewCards, in: 1...100) {
                    HStack {
                        Text("New cards per day")
                        Spacer()
                        Text("\(dailyNewCards)")
                            .foregroundStyle(.secondary)
                    }
                }

                Stepper(value: $dailyReviewCards, in: 10...500, step: 10) {
                    HStack {
                        Text("Review cards per day")
                        Spacer()
                        Text("\(dailyReviewCards)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct StudySettingsView: View {
    @Binding var showTimer: Bool
    @Binding var autoPlayAudio: Bool

    var body: some View {
        Form {
            Section("Study Session") {
                Toggle("Show session timer", isOn: $showTimer)
                Toggle("Auto-play audio (if available)", isOn: $autoPlayAudio)
            }

            Section("Keyboard Shortcuts") {
                LabeledContent("Show Answer", value: "Space / Enter")
                LabeledContent("Again", value: "1")
                LabeledContent("Hard", value: "2")
                LabeledContent("Good", value: "3")
                LabeledContent("Easy", value: "4")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AccountSettingsView: View {
    @EnvironmentObject private var supabase: SupabaseManager
    @EnvironmentObject private var database: DatabaseManager
    @EnvironmentObject private var repository: DataRepository
    @ObservedObject private var syncState = SyncStateManager.shared

    @State private var isSigningOut = false

    var body: some View {
        Form {
            Section("Account") {
                if let user = supabase.currentUser {
                    LabeledContent("Email", value: user.email ?? "Unknown")
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
                Button(role: .destructive, action: signOut) {
                    if isSigningOut {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Sign Out")
                    }
                }
                .disabled(isSigningOut)
            }
        }
        .formStyle(.grouped)
        .padding()
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

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Saegim")
                .font(.title.bold())

            Text("Version 1.0.0")
                .foregroundStyle(.secondary)

            Divider()

            Text("A native macOS flashcard app using spaced repetition to help you learn and remember anything.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
    }
}

#Preview {
    SettingsView()
}
