import SwiftUI
import AuthenticationServices
import GoogleSignIn

// MARK: - Auth View

struct AuthView: View {
    private let googleClientID = "985369434455-hvpnt18t6vdpf03ne5d7mqpg4tveh6oq.apps.googleusercontent.com"

    @EnvironmentObject var appState: AppState
    @State private var isLoading = false
    @State private var error: Error?
    @State private var showError = false
    @State private var showEmailAuth = false
    @State private var showSuccessMessage = false
    @State private var successMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // Logo and tagline
                VStack(spacing: 12) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.pink)

                    Text("CuraKnot")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Coordinate care with your circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Features list
                VStack(alignment: .leading, spacing: 16) {
                    AuthFeatureRow(icon: "waveform.circle.fill", text: "Voice handoffs")
                    AuthFeatureRow(icon: "checklist", text: "Task management")
                    AuthFeatureRow(icon: "folder.fill", text: "Care binder")
                    AuthFeatureRow(icon: "person.3.fill", text: "Family coordination")
                }
                .padding(.horizontal, 32)

                Spacer()

                // Sign in buttons
                VStack(spacing: 12) {
                    SignInWithAppleButton { request in
                        request.requestedScopes = [.email, .fullName]
                    } onCompletion: { result in
                        handleAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .cornerRadius(12)
                    .accessibilityLabel("Sign in with Apple")

                    Button {
                        handleGoogleSignIn()
                    } label: {
                        HStack(spacing: 12) {
                            Image("GoogleLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            Text("Continue with Google")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                    }
                    .accessibilityLabel("Continue with Google")

                    // Email sign in button
                    Button {
                        showEmailAuth = true
                    } label: {
                        HStack {
                            Image(systemName: "envelope.fill")
                            Text("Continue with Email")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                    }
                    .accessibilityLabel("Continue with Email")
                }
                .padding(.horizontal, 24)

                Text("By signing in, you agree to our Terms of Service and Privacy Policy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
            }
            .overlay {
                if isLoading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }
            }
            .alert("Sign In Error", isPresented: $showError, presenting: error) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.localizedDescription)
            }
            .alert("Success", isPresented: $showSuccessMessage) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(successMessage)
            }
            .sheet(isPresented: $showEmailAuth) {
                EmailAuthView(
                    isLoading: $isLoading,
                    onSignIn: handleEmailSignIn,
                    onSignUp: handleEmailSignUp,
                    onForgotPassword: handleForgotPassword
                )
            }
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success:
            Task {
                isLoading = true
                do {
                    try await appState.signIn()
                } catch {
                    self.error = error
                    showError = true
                }
                isLoading = false
            }
        case .failure(let error):
            // User cancelled is not an error
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                self.error = error
                showError = true
            }
        }
    }

    private func handleGoogleSignIn() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }

        let config = GIDConfiguration(clientID: googleClientID)
        GIDSignIn.sharedInstance.configuration = config

        Task {
            do {
                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

                guard let idToken = result.user.idToken?.tokenString else {
                    throw AuthError.missingIdToken
                }

                let accessToken = result.user.accessToken.tokenString
                guard !accessToken.isEmpty else {
                    throw AuthError.missingIdToken
                }

                isLoading = true
                try await appState.signInWithGoogle(idToken: idToken, accessToken: accessToken)
            } catch GIDSignInError.canceled {
                // User cancelled - ignore
            } catch {
                self.error = error
                showError = true
            }
            isLoading = false
        }
    }

    private func handleEmailSignIn(email: String, password: String) {
        Task {
            isLoading = true
            do {
                try await appState.signInWithEmail(email: email, password: password)
                await MainActor.run {
                    showEmailAuth = false
                }
            } catch AuthError.emailConfirmationRequired {
                await MainActor.run {
                    showEmailAuth = false
                    successMessage = "Please check your email and click the confirmation link before signing in."
                    showSuccessMessage = true
                }
            } catch {
                self.error = error
                showError = true
            }
            isLoading = false
        }
    }

    private func handleEmailSignUp(email: String, password: String, displayName: String) {
        Task {
            isLoading = true
            do {
                try await appState.signUp(email: email, password: password, displayName: displayName.isEmpty ? nil : displayName)
                await MainActor.run {
                    showEmailAuth = false
                }
            } catch AuthError.emailConfirmationRequired {
                await MainActor.run {
                    showEmailAuth = false
                    successMessage = "Please check your email to confirm your account, then sign in."
                    showSuccessMessage = true
                }
            } catch {
                self.error = error
                showError = true
            }
            isLoading = false
        }
    }

    private func handleForgotPassword(email: String) {
        Task {
            isLoading = true
            do {
                try await appState.resetPassword(email: email)
                await MainActor.run {
                    successMessage = "Password reset email sent. Check your inbox."
                    showSuccessMessage = true
                }
            } catch {
                self.error = error
                showError = true
            }
            isLoading = false
        }
    }
}

// MARK: - Email Auth View

struct EmailAuthView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isLoading: Bool

    let onSignIn: (String, String) -> Void
    let onSignUp: (String, String, String) -> Void
    let onForgotPassword: (String) -> Void

    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var displayName = ""
    @State private var showForgotPassword = false

    enum Field {
        case email, password, confirmPassword, displayName
    }

    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "envelope.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.pink)

                        Text(isSignUp ? "Create Account" : "Welcome Back")
                            .font(.title)
                            .fontWeight(.bold)

                        Text(isSignUp ? "Sign up with your email" : "Sign in with your email")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 32)

                    // Form fields
                    VStack(spacing: 16) {
                        if isSignUp {
                            TextField("Display Name", text: $displayName)
                                .textContentType(.name)
                                .focused($focusedField, equals: .displayName)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }

                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .focused($focusedField, equals: .email)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)

                        SecureField("Password", text: $password)
                            .textContentType(isSignUp ? .newPassword : .password)
                            .focused($focusedField, equals: .password)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)

                        if isSignUp {
                            SecureField("Confirm Password", text: $confirmPassword)
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .confirmPassword)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 24)

                    // Action button
                    Button {
                        if isSignUp {
                            onSignUp(email, password, displayName)
                        } else {
                            onSignIn(email, password)
                        }
                    } label: {
                        Text(isSignUp ? "Create Account" : "Sign In")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(isFormValid ? Color.pink : Color.gray)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                    .disabled(!isFormValid || isLoading)
                    .padding(.horizontal, 24)

                    // Forgot password (sign in only)
                    if !isSignUp {
                        Button("Forgot Password?") {
                            showForgotPassword = true
                        }
                        .font(.subheadline)
                        .foregroundStyle(.pink)
                    }

                    // Toggle sign in/sign up
                    HStack {
                        Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                            .foregroundStyle(.secondary)
                        Button(isSignUp ? "Sign In" : "Sign Up") {
                            withAnimation {
                                isSignUp.toggle()
                                clearForm()
                            }
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(.pink)
                    }
                    .font(.subheadline)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Reset Password", isPresented: $showForgotPassword) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                Button("Send Reset Link") {
                    onForgotPassword(email)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter your email to receive a password reset link.")
            }
        }
    }

    private var isFormValid: Bool {
        let emailValid = email.contains("@") && email.contains(".")
        let passwordValid = password.count >= 6

        if isSignUp {
            return emailValid && passwordValid && password == confirmPassword
        } else {
            return emailValid && passwordValid
        }
    }

    private func clearForm() {
        password = ""
        confirmPassword = ""
    }
}

// MARK: - Auth Feature Row

private struct AuthFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.pink)
                .frame(width: 32)
                .accessibilityHidden(true)

            Text(text)
                .font(.body)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

#Preview {
    AuthView()
        .environmentObject(AppState())
}
