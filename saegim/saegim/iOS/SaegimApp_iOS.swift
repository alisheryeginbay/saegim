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
    var sharedModelContainer: ModelContainer = Persistence.sharedModelContainer

    var body: some Scene {
        WindowGroup {
            ContentView_iOS()
        }
        .modelContainer(sharedModelContainer)
    }
}
