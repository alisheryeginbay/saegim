//
//  SupabaseManager.swift
//  saegim
//
//  Supabase authentication and client management
//

import Foundation
import Combine
import Supabase

/// Manages Supabase authentication and provides the shared client instance
@MainActor
final class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()

    /// Supabase client instance
    let client: SupabaseClient

    /// Currently authenticated user
    @Published private(set) var currentUser: User?

    /// Whether user is authenticated
    @Published private(set) var isAuthenticated = false

    /// Loading state for auth operations
    @Published private(set) var isLoading = true

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.supabaseURL,
            supabaseKey: SupabaseConfig.supabaseAnonKey
        )

        // Check for existing session on init
        Task {
            await checkSession()
            isLoading = false
        }
    }

    // MARK: - Session Management

    /// Check for existing session
    func checkSession() async {
        do {
            let session = try await client.auth.session
            currentUser = session.user
            isAuthenticated = true
        } catch {
            currentUser = nil
            isAuthenticated = false
        }
    }

    // MARK: - Authentication Methods

    /// Sign up with email and password
    func signUp(email: String, password: String) async throws {
        let response = try await client.auth.signUp(
            email: email,
            password: password
        )

        // Check if session exists (email confirmation might be required)
        if response.session != nil {
            currentUser = response.user
            isAuthenticated = true
        } else {
            // Email confirmation required - throw informative error
            throw AuthError.emailConfirmationRequired
        }
    }

    /// Sign in with email and password
    func signIn(email: String, password: String) async throws {
        let session = try await client.auth.signIn(
            email: email,
            password: password
        )
        currentUser = session.user
        isAuthenticated = true
    }

    /// Sign out the current user
    func signOut() async throws {
        try await client.auth.signOut()
        currentUser = nil
        isAuthenticated = false
    }

    /// Send password reset email
    func resetPassword(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email)
    }

    /// Get current user ID
    var userId: UUID? {
        currentUser?.id
    }

    /// Get current access token for PowerSync
    func getAccessToken() async throws -> String {
        let session = try await client.auth.session
        return session.accessToken
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case notAuthenticated
    case invalidCredentials
    case emailConfirmationRequired
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to perform this action."
        case .invalidCredentials:
            return "Invalid email or password."
        case .emailConfirmationRequired:
            return "Please check your email and confirm your account before signing in."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
