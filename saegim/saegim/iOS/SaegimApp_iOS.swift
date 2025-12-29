//
//  SaegimApp_iOS.swift
//  saegim
//
//  iOS app entry point
//

import SwiftUI
import SwiftData

@main
struct SaegimApp_iOS: App {
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
            ContentView_iOS()
        }
        .modelContainer(sharedModelContainer)
    }
}
