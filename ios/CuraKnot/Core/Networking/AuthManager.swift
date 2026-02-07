import Foundation
import AuthenticationServices
import os

private let logger = Logger(subsystem: "com.curaknot.app", category: "AuthManager")

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case invalidCredentials
    case missingIdToken
    case emailConfirmationRequired
    case userNotFound
    case accountNotFound
    case sessionExpired
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Incorrect email or password. Please try again."
        case .missingIdToken:
            return "Unable to retrieve authentication token"
        case .emailConfirmationRequired:
            return "Please check your email to confirm your account"
        case .userNotFound:
            return "User not found"
        case .accountNotFound:
            return "No account found with this email. Please sign up first."
        case .sessionExpired:
            return "Your session has expired. Please sign in again"
        case .unknown(let message):
            return message
        }
    }
}

// MARK: - Auth Manager

@MainActor
final class AuthManager: NSObject, ObservableObject {
    // MARK: - Properties
    
    private let supabaseClient: SupabaseClient
    private var authContinuation: CheckedContinuation<User, Error>?
    
    @Published var currentUser: User?
    
    // MARK: - Keychain Keys
    
    private enum KeychainKey {
        static let accessToken = "com.curaknot.accessToken"
        static let refreshToken = "com.curaknot.refreshToken"
        static let userId = "com.curaknot.userId"
    }
    
    // MARK: - Initialization
    
    init(supabaseClient: SupabaseClient) {
        self.supabaseClient = supabaseClient
        super.init()
    }
    
    // MARK: - Public Methods
    
    func getCurrentUser() async throws -> User? {
        // Check for stored tokens
        guard let accessToken = KeychainHelper.load(key: KeychainKey.accessToken),
              let refreshToken = KeychainHelper.load(key: KeychainKey.refreshToken) else {
            return nil
        }
        
        // Set tokens on client
        await supabaseClient.setSession(accessToken: accessToken, refreshToken: refreshToken)
        
        // Fetch current user
        guard let userId = KeychainHelper.load(key: KeychainKey.userId) else {
            return nil
        }
        
        do {
            let users: [User] = try await supabaseClient
                .from("users")
                .select()
                .eq("id", userId)
                .execute()
            
            currentUser = users.first
            return currentUser
        } catch {
            // Token might be expired, clear and return nil
            try? await signOut()
            return nil
        }
    }
    
    func signInWithApple() async throws -> User {
        return try await withCheckedThrowingContinuation { continuation in
            self.authContinuation = continuation
            
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.email, .fullName]
            
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.performRequests()
        }
    }
    
    /// Sign in with Google OAuth tokens
    func signInWithGoogle(idToken: String, accessToken: String) async throws -> User {
        struct SignInRequest: Encodable {
            let provider: String = "google"
            let idToken: String
            let accessToken: String
            
            enum CodingKeys: String, CodingKey {
                case provider
                case idToken = "id_token"
                case accessToken = "access_token"
            }
        }
        
        struct SignInResponse: Decodable {
            let accessToken: String
            let refreshToken: String
            let user: AuthUser
            
            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case user
            }
            
            struct AuthUser: Decodable {
                let id: String
                let email: String?
                let userMetadata: UserMetadata?
                
                enum CodingKeys: String, CodingKey {
                    case id
                    case email
                    case userMetadata = "user_metadata"
                }
                
                struct UserMetadata: Decodable {
                    let fullName: String?
                    let name: String?
                    let avatarUrl: String?
                    
                    enum CodingKeys: String, CodingKey {
                        case fullName = "full_name"
                        case name
                        case avatarUrl = "avatar_url"
                    }
                }
            }
        }
        
        let request = SignInRequest(idToken: idToken, accessToken: accessToken)
        let body = try JSONEncoder.supabase.encode(request)
        
        let (data, _) = try await supabaseClient.request(
            path: "auth/v1/token?grant_type=id_token",
            method: "POST",
            body: body
        )
        
        let response = try JSONDecoder.supabase.decode(SignInResponse.self, from: data)
        
        // Store tokens
        KeychainHelper.save(key: KeychainKey.accessToken, value: response.accessToken)
        KeychainHelper.save(key: KeychainKey.refreshToken, value: response.refreshToken)
        KeychainHelper.save(key: KeychainKey.userId, value: response.user.id)
        
        // Set session on client
        await supabaseClient.setSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken
        )
        
        // Fetch or create user profile
        let users: [User] = try await supabaseClient
            .from("users")
            .select()
            .eq("id", response.user.id)
            .execute()
        
        if let existingUser = users.first {
            currentUser = existingUser
            return existingUser
        }
        
        // Create new user profile from Google data
        let displayName = response.user.userMetadata?.fullName 
            ?? response.user.userMetadata?.name 
            ?? response.user.email?.components(separatedBy: "@").first 
            ?? "User"
        
        let user = User(
            id: response.user.id,
            email: response.user.email,
            appleSub: nil,
            displayName: displayName,
            avatarUrl: response.user.userMetadata?.avatarUrl,
            settingsJson: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        try await supabaseClient.from("users").upsert(user)
        currentUser = user
        return user
    }
    
    /// Sign in with email and password
    func signInWithEmail(email: String, password: String) async throws -> User {
        struct SignInRequest: Encodable {
            let email: String
            let password: String
        }
        
        struct SignInResponse: Decodable {
            let accessToken: String
            let refreshToken: String
            let user: AuthUser
            
            // Note: No CodingKeys needed - JSONDecoder.supabase uses .convertFromSnakeCase
            
            struct AuthUser: Decodable {
                let id: String
                let email: String?
            }
        }
        
        let request = SignInRequest(email: email, password: password)
        let body = try JSONEncoder.supabase.encode(request)
        
        let (data, _) = try await supabaseClient.request(
            path: "auth/v1/token?grant_type=password",
            method: "POST",
            body: body
        )
        
        let response: SignInResponse
        do {
            response = try JSONDecoder.supabase.decode(SignInResponse.self, from: data)
        } catch let decodingError as DecodingError {
            logger.error("Decode error: \(String(describing: decodingError))")
            throw decodingError
        } catch {
            logger.error("Sign-in error: \(error.localizedDescription)")
            throw error
        }
        
        // Store tokens
        KeychainHelper.save(key: KeychainKey.accessToken, value: response.accessToken)
        KeychainHelper.save(key: KeychainKey.refreshToken, value: response.refreshToken)
        KeychainHelper.save(key: KeychainKey.userId, value: response.user.id)
        
        // Set session on client
        await supabaseClient.setSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken
        )
        
        // Fetch or create user profile
        let users: [User] = try await supabaseClient
            .from("users")
            .select()
            .eq("id", response.user.id)
            .execute()
        
        if let existingUser = users.first {
            currentUser = existingUser
            return existingUser
        }
        
        // Create new user profile
        let displayName = email.components(separatedBy: "@").first ?? "Dev User"
        let user = User(
            id: response.user.id,
            email: response.user.email ?? email,
            appleSub: nil,
            displayName: displayName,
            avatarUrl: nil,
            settingsJson: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        try await supabaseClient.from("users").upsert(user)
        currentUser = user
        return user
    }
    
    /// Sign up with email and password
    func signUp(email: String, password: String, displayName: String?) async throws -> User {
        struct SignUpRequest: Encodable {
            let email: String
            let password: String
            let data: UserData?
            
            struct UserData: Encodable {
                let displayName: String?
                
                enum CodingKeys: String, CodingKey {
                    case displayName = "display_name"
                }
            }
        }
        
        struct SignUpResponse: Decodable {
            let accessToken: String?
            let refreshToken: String?
            let user: AuthUser
            
            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case user
            }
            
            struct AuthUser: Decodable {
                let id: String
                let email: String?
                let confirmedAt: String?
                
                enum CodingKeys: String, CodingKey {
                    case id
                    case email
                    case confirmedAt = "confirmed_at"
                }
            }
        }
        
        let userData = displayName.map { SignUpRequest.UserData(displayName: $0) }
        let request = SignUpRequest(email: email, password: password, data: userData)
        let body = try JSONEncoder.supabase.encode(request)
        
        let (data, _) = try await supabaseClient.request(
            path: "auth/v1/signup",
            method: "POST",
            body: body
        )
        
        let response = try JSONDecoder.supabase.decode(SignUpResponse.self, from: data)
        
        // Check if email confirmation is required
        guard let accessToken = response.accessToken,
              let refreshToken = response.refreshToken else {
            // No session means email confirmation is required
            throw AuthError.emailConfirmationRequired
        }
        
        // Store tokens
        KeychainHelper.save(key: KeychainKey.accessToken, value: accessToken)
        KeychainHelper.save(key: KeychainKey.refreshToken, value: refreshToken)
        KeychainHelper.save(key: KeychainKey.userId, value: response.user.id)
        
        // Set session on client
        await supabaseClient.setSession(
            accessToken: accessToken,
            refreshToken: refreshToken
        )
        
        // Create user profile
        let user = User(
            id: response.user.id,
            email: response.user.email ?? email,
            appleSub: nil,
            displayName: displayName ?? email.components(separatedBy: "@").first ?? "User",
            avatarUrl: nil,
            settingsJson: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        try await supabaseClient.from("users").upsert(user)
        currentUser = user
        return user
    }
    
    /// Send password reset email
    func resetPassword(email: String) async throws {
        struct ResetRequest: Encodable {
            let email: String
        }
        
        let request = ResetRequest(email: email)
        let body = try JSONEncoder.supabase.encode(request)
        
        let (_, response) = try await supabaseClient.request(
            path: "auth/v1/recover",
            method: "POST",
            body: body
        )
        
        // 200 OK means the email was sent (or the email doesn't exist, but we don't leak that info)
        guard (200...299).contains(response.statusCode) else {
            throw AuthError.unknown("Failed to send password reset email")
        }
    }
    
    func signOut() async throws {
        // Clear keychain
        KeychainHelper.delete(key: KeychainKey.accessToken)
        KeychainHelper.delete(key: KeychainKey.refreshToken)
        KeychainHelper.delete(key: KeychainKey.userId)
        
        // Clear client session
        await supabaseClient.clearSession()
        
        currentUser = nil
    }
    
    // MARK: - Private Methods
    
    private func handleAppleSignIn(
        identityToken: Data,
        authorizationCode: Data,
        fullName: PersonNameComponents?,
        email: String?
    ) async throws -> User {
        guard let idToken = String(data: identityToken, encoding: .utf8) else {
            throw SupabaseError.authError("Invalid identity token")
        }
        
        // Exchange Apple token with Supabase
        struct SignInRequest: Encodable {
            let provider: String = "apple"
            let idToken: String
            // Note: No CodingKeys needed - JSONEncoder.supabase uses .convertToSnakeCase
        }
        
        struct SignInResponse: Decodable {
            let accessToken: String
            let refreshToken: String
            let user: AuthUser
            
            // Note: No CodingKeys needed - JSONDecoder.supabase uses .convertFromSnakeCase
            
            struct AuthUser: Decodable {
                let id: String
                let email: String?
            }
        }
        
        let request = SignInRequest(idToken: idToken)
        let body = try JSONEncoder.supabase.encode(request)
        
        let (data, _) = try await supabaseClient.request(
            path: "auth/v1/token?grant_type=id_token",
            method: "POST",
            body: body
        )
        
        let response = try JSONDecoder.supabase.decode(SignInResponse.self, from: data)
        
        // Store tokens
        KeychainHelper.save(key: KeychainKey.accessToken, value: response.accessToken)
        KeychainHelper.save(key: KeychainKey.refreshToken, value: response.refreshToken)
        KeychainHelper.save(key: KeychainKey.userId, value: response.user.id)
        
        // Set session on client
        await supabaseClient.setSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken
        )
        
        // Create or update user profile
        let displayName: String
        if let fullName = fullName {
            displayName = [fullName.givenName, fullName.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
        } else {
            displayName = email?.components(separatedBy: "@").first ?? "User"
        }
        
        let user = User(
            id: response.user.id,
            email: response.user.email ?? email,
            appleSub: nil, // Would come from token claims
            displayName: displayName.isEmpty ? "User" : displayName,
            avatarUrl: nil,
            settingsJson: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Upsert user profile
        try await supabaseClient.from("users").upsert(user)
        
        currentUser = user
        return user
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthManager: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            authContinuation?.resume(throwing: SupabaseError.authError("Invalid credential type"))
            authContinuation = nil
            return
        }
        
        guard let identityToken = appleCredential.identityToken,
              let authorizationCode = appleCredential.authorizationCode else {
            authContinuation?.resume(throwing: SupabaseError.authError("Missing tokens"))
            authContinuation = nil
            return
        }
        
        Task {
            do {
                let user = try await handleAppleSignIn(
                    identityToken: identityToken,
                    authorizationCode: authorizationCode,
                    fullName: appleCredential.fullName,
                    email: appleCredential.email
                )
                authContinuation?.resume(returning: user)
            } catch {
                authContinuation?.resume(throwing: error)
            }
            authContinuation = nil
        }
    }
    
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        authContinuation?.resume(throwing: error)
        authContinuation = nil
    }
}

// MARK: - Keychain Helper

enum KeychainHelper {
    static func save(key: String, value: String) {
        let data = Data(value.utf8)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
