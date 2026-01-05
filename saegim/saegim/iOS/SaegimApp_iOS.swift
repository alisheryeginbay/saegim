//
//  SaegimApp_iOS.swift
//  saegim
//
//  iOS app entry point
//

import SwiftUI

@main
struct SaegimApp_iOS: App {
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
                    ContentView_iOS()
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
                        try? await database.initialize(supabase: supabase)
                        try? await repository.fetchDecks()
                        repository.startWatching()
                    }
                }
            }
        }
    }
}
