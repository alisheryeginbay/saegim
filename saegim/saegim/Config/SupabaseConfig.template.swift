//
//  SupabaseConfig.swift
//  saegim
//
//  Configuration for Supabase and PowerSync services
//
//  SETUP:
//  1. Copy this file to SupabaseConfig.swift
//  2. Replace placeholder values with your credentials
//

import Foundation

enum SupabaseConfig {
    /// Supabase project URL (Settings > API > Project URL)
    static let supabaseURL = URL(string: "https://YOUR_PROJECT.supabase.co") ?? {
        fatalError("Invalid Supabase URL in SupabaseConfig.swift")
    }()

    /// Supabase anonymous/public key (Settings > API > anon/public)
    static let supabaseAnonKey = "YOUR_SUPABASE_ANON_KEY"

    /// PowerSync instance URL (PowerSync Dashboard)
    static let powerSyncURL = "https://YOUR_INSTANCE.powersync.journeyapps.com"
}
