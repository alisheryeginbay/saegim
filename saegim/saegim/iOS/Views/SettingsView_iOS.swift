//
//  SettingsView_iOS.swift
//  saegim
//
//  iOS settings view
//

import SwiftUI

struct SettingsView_iOS: View {
    @AppStorage("dailyNewCards") private var dailyNewCards = 20
    @AppStorage("dailyReviewCards") private var dailyReviewCards = 100
    @AppStorage("showTimer") private var showTimer = true
    @AppStorage("autoPlayAudio") private var autoPlayAudio = false

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
}

#Preview {
    NavigationStack {
        SettingsView_iOS()
            .navigationTitle("Settings")
    }
}
