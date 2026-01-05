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

    @State private var isSigningOut = false

    var body: some View {
        Form {
            Section("Account") {
                if let user = supabase.currentUser {
                    LabeledContent("Email", value: user.email ?? "Unknown")

                    HStack {
                        Text("Sync Status")
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: database.syncStatus.systemImage)
                                .foregroundStyle(syncStatusColor)
                            Text(database.syncStatus.description)
                                .foregroundStyle(.secondary)
                        }
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

    private var syncStatusColor: Color {
        switch database.syncStatus {
        case .synced: return .green
        case .syncing: return .blue
        case .offline: return .orange
        case .error: return .red
        case .idle: return .secondary
        }
    }

    private func signOut() {
        isSigningOut = true
        Task {
            do {
                repository.stopWatching()
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
