//
//  saegimApp.swift
//  saegim
//
//  Created by Alisher on 12/26/25.
//

import SwiftUI

@main
struct SaegimApp: App {
    @StateObject private var supabase = SupabaseManager.shared
    @StateObject private var database = DatabaseManager.shared
    @StateObject private var repository = DataRepository.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if supabase.isLoading {
                    // Show loading while checking auth state
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if supabase.isAuthenticated {
                    ContentView()
                        .environmentObject(supabase)
                        .environmentObject(database)
                        .environmentObject(repository)
                } else {
                    AuthView()
                }
            }
            .withToasts()
            .onAppear {
                SyncStateManager.shared.startNetworkMonitoring()
            }
            .onChange(of: supabase.isAuthenticated) { _, isAuthenticated in
                if isAuthenticated && database.database == nil {
                    Task {
                        do {
                            try await database.initialize(supabase: supabase)
                            try await repository.fetchDecks()
                            repository.startWatching()
                        } catch {
                            NSLog("Failed to initialize after auth: %@", error.localizedDescription)
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .windowStyle(.automatic)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Deck") {
                    NotificationCenter.default.post(
                        name: .newDeck,
                        object: nil
                    )
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("New Card") {
                    NotificationCenter.default.post(
                        name: .newCard,
                        object: nil
                    )
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Import from Anki...") {
                    NotificationCenter.default.post(
                        name: .importAnki,
                        object: nil
                    )
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("Import from CSV...") {
                    NotificationCenter.default.post(
                        name: .importCSV,
                        object: nil
                    )
                }

                Divider()

                Button("Sync Now") {
                    Task {
                        try? await DatabaseManager.shared.forceSync()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(supabase)
                .environmentObject(database)
                .environmentObject(repository)
        }
        #endif
    }
}

extension Notification.Name {
    static let newDeck = Notification.Name("newDeck")
    static let newCard = Notification.Name("newCard")
    static let importAnki = Notification.Name("importAnki")
    static let importCSV = Notification.Name("importCSV")
}
