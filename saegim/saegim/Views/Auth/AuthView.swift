//
//  AuthView.swift
//  saegim
//
//  Sign in and sign up view
//

import SwiftUI

struct AuthView: View {
    @ObservedObject private var supabase = SupabaseManager.shared
    @ObservedObject private var database = DatabaseManager.shared
    @ObservedObject private var repository = DataRepository.shared

    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showResetPassword = false
    @State private var resetEmail = ""
    @State private var resetEmailSent = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Logo and Title
            VStack(spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 64))
                    .foregroundStyle(.accent)

                Text("Saegim")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Master anything with spaced repetition")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Form
            VStack(spacing: 16) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(isSignUp ? .newPassword : .password)

                if isSignUp {
                    SecureField("Confirm Password", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.newPassword)
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .frame(maxWidth: 320)

            // Actions
            VStack(spacing: 12) {
                Button(action: submit) {
                    Group {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(isSignUp ? "Create Account" : "Sign In")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isLoading || !isFormValid)

                Button(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSignUp.toggle()
                        errorMessage = ""
                        confirmPassword = ""
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.accent)

                if !isSignUp {
                    Button("Forgot Password?") {
                        resetEmail = email
                        showResetPassword = true
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 320)

            Spacer()
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 500)
        #endif
        .sheet(isPresented: $showResetPassword) {
            ResetPasswordSheet(
                email: $resetEmail,
                emailSent: $resetEmailSent,
                isPresented: $showResetPassword
            )
        }
    }

    private var isFormValid: Bool {
        let emailValid = email.contains("@") && email.contains(".")
        let passwordValid = password.count >= 6

        if isSignUp {
            return emailValid && passwordValid && password == confirmPassword
        }
        return emailValid && passwordValid
    }

    private func submit() {
        guard isFormValid else { return }

        isLoading = true
        errorMessage = ""

        Task {
            do {
                if isSignUp {
                    try await supabase.signUp(email: email, password: password)
                } else {
                    try await supabase.signIn(email: email, password: password)
                }

                // Initialize database after successful auth
                try await database.initialize(supabase: supabase)

                // Fetch initial data
                try await repository.fetchDecks()
                repository.startWatching()

            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Reset Password Sheet

struct ResetPasswordSheet: View {
    @Binding var email: String
    @Binding var emailSent: Bool
    @Binding var isPresented: Bool

    @State private var isLoading = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 24) {
            Text("Reset Password")
                .font(.title2)
                .fontWeight(.semibold)

            if emailSent {
                VStack(spacing: 16) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)

                    Text("Check your email")
                        .font(.headline)

                    Text("We've sent a password reset link to \(email)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Done") {
                        isPresented = false
                        emailSent = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 16) {
                    Text("Enter your email address and we'll send you a link to reset your password.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    HStack(spacing: 12) {
                        Button("Cancel") {
                            isPresented = false
                        }
                        .buttonStyle(.bordered)

                        Button("Send Reset Link") {
                            sendResetLink()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isLoading || !email.contains("@"))
                    }
                }
            }
        }
        .padding(32)
        .frame(maxWidth: 400)
        #if os(macOS)
        .frame(minWidth: 350, minHeight: 250)
        #endif
    }

    private func sendResetLink() {
        isLoading = true
        errorMessage = ""

        Task {
            do {
                try await SupabaseManager.shared.resetPassword(email: email)
                emailSent = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview("Auth View") {
    AuthView()
}

#Preview("Sign Up") {
    AuthView()
}
