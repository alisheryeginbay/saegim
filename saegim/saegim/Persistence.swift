//
//  Persistence.swift
//  saegim
//
//  Shared persistence configuration with iCloud sync
//

import Foundation
import SwiftData

enum Persistence {
    /// iCloud container identifier (must match entitlements)
    static let cloudKitContainerID = "iCloud.com.yeginbay.saegim"

    /// Create a ModelContainer with CloudKit sync enabled
    static func createCloudKitContainer() throws -> ModelContainer {
        let schema = Schema([
            Card.self,
            Deck.self,
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    /// Create a local-only ModelContainer (for testing or offline mode)
    static func createLocalContainer() throws -> ModelContainer {
        let schema = Schema([
            Card.self,
            Deck.self,
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    /// Shared model container - attempts CloudKit first, falls back to local
    static let sharedModelContainer: ModelContainer = {
        #if DEBUG
        // In DEBUG, try CloudKit but silently fall back to local storage
        // This allows development without Apple Developer Program membership
        do {
            return try createCloudKitContainer()
        } catch {
            print("[Persistence] CloudKit unavailable (requires Apple Developer Program): \(error.localizedDescription)")
            print("[Persistence] Using local storage for development")
            do {
                return try createLocalContainer()
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
        #else
        // In RELEASE, prefer CloudKit with graceful fallback
        do {
            return try createCloudKitContainer()
        } catch {
            print("[Persistence] CloudKit sync unavailable: \(error.localizedDescription)")
            print("[Persistence] Falling back to local storage")
            do {
                return try createLocalContainer()
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
        #endif
    }()
}
