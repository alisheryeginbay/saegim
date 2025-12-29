//
//  saegimApp.swift
//  saegim
//
//  Created by Alisher on 12/26/25.
//

import SwiftUI
import SwiftData

@main
struct SaegimApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Card.self,
            Deck.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
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
            }
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
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
