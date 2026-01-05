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

    @AppStorage("dailyNewCards") private var dailyNewCards = 20
    @AppStorage("dailyReviewCards") private var dailyReviewCards = 100
    @AppStorage("showTimer") private var showTimer = true
    @AppStorage("autoPlayAudio") private var autoPlayAudio = false

    @State private var isSigningOut = false

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

#Preview {
    NavigationStack {
        SettingsView_iOS()
            .navigationTitle("Settings")
    }
}
