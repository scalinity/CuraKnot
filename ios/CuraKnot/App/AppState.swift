import Foundation
import Combine
import os

// MARK: - Auth State

enum AuthState: Equatable {
    case loading
    case unauthenticated
    case authenticated
}

private let logger = Logger(subsystem: "com.curaknot.app", category: "AppState")

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    // MARK: - Published Properties
    
    @Published var authState: AuthState = .loading
    @Published var currentUser: User?
    @Published var currentCircle: Circle?
    @Published var circles: [Circle] = []
    @Published var patients: [Patient] = []

    // MARK: - Computed Properties

    /// Current circle ID for convenience
    var currentCircleId: String? {
        currentCircle?.id
    }

    /// Current patient ID (first patient in circle, if any)
    var currentPatientId: String? {
        patients.first?.id
    }

    /// Current patient (first patient in circle, if any)
    var currentPatient: Patient? {
        patients.first
    }
    
    // MARK: - Dependencies
    
    private var authManager: AuthManager?
    private var syncCoordinator: SyncCoordinator?
    
    // MARK: - Initialization
    
    init() {}
    
    func configure(authManager: AuthManager, syncCoordinator: SyncCoordinator) {
        self.authManager = authManager
        self.syncCoordinator = syncCoordinator
    }
    
    // MARK: - Auth Methods
    
    func checkAuthStatus() async {
        authState = .loading
        
        // Check for existing session
        guard let authManager = authManager else {
            authState = .unauthenticated
            updateSiriContext()
            return
        }
        
        do {
            if let user = try await authManager.getCurrentUser() {
                currentUser = user
                await loadUserData()
                authState = .authenticated
            } else {
                authState = .unauthenticated
            }
            updateSiriContext()
        } catch {
            logger.error("Auth check failed: \(error.localizedDescription)")
            authState = .unauthenticated
            updateSiriContext()
        }
    }
    
    func signIn() async throws {
        guard let authManager = authManager else { return }
        
        let user = try await authManager.signInWithApple()
        currentUser = user
        await loadUserData()
        authState = .authenticated
        updateSiriContext()
    }
    
    /// Sign in with Google OAuth tokens
    func signInWithGoogle(idToken: String, accessToken: String) async throws {
        guard let authManager = authManager else { return }
        
        let user = try await authManager.signInWithGoogle(idToken: idToken, accessToken: accessToken)
        currentUser = user
        await loadUserData()
        authState = .authenticated
        updateSiriContext()
    }
    
    /// Sign in with email and password
    func signInWithEmail(email: String, password: String) async throws {
        guard let authManager = authManager else { return }
        
        let user = try await authManager.signInWithEmail(email: email, password: password)
        currentUser = user
        await loadUserData()
        authState = .authenticated
        updateSiriContext()
    }
    
    /// Sign up with email and password
    func signUp(email: String, password: String, displayName: String?) async throws {
        guard let authManager = authManager else { return }
        
        let user = try await authManager.signUp(email: email, password: password, displayName: displayName)
        currentUser = user
        await loadUserData()
        authState = .authenticated
        updateSiriContext()
    }
    
    /// Send password reset email
    func resetPassword(email: String) async throws {
        guard let authManager = authManager else { return }
        
        try await authManager.resetPassword(email: email)
    }
    
    func signOut() async {
        guard let authManager = authManager else { return }
        
        try? await authManager.signOut()
        currentUser = nil
        currentCircle = nil
        circles = []
        patients = []
        authState = .unauthenticated
        updateSiriContext()
    }
    
    // MARK: - Data Loading
    
    private func loadUserData() async {
        guard let syncCoordinator = syncCoordinator else { return }
        
        do {
            // Sync circles
            try await syncCoordinator.syncCircles()
            circles = try await syncCoordinator.fetchLocalCircles()
            
            // Set current circle to first one if not set
            if currentCircle == nil, let firstCircle = circles.first {
                selectCircle(firstCircle)
            }
        } catch {
            logger.error("Failed to load user data: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Circle Management
    
    func selectCircle(_ circle: Circle) {
        currentCircle = circle
        updateSiriContext()
        
        Task {
            await loadCircleData()
        }
    }
    
    private func loadCircleData() async {
        guard let syncCoordinator = syncCoordinator,
              let circleId = currentCircle?.id else { return }
        
        do {
            try await syncCoordinator.syncPatients(circleId: circleId)
            patients = try await syncCoordinator.fetchLocalPatients(circleId: circleId)
        } catch {
            logger.error("Failed to load circle data: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Refresh
    
    func refresh() async {
        await loadUserData()
        if currentCircle != nil {
            await loadCircleData()
        }
    }
    
    // MARK: - Siri Context
    
    /// Updates SiriShortcutsService context whenever auth or circle state changes.
    /// This ensures Siri intents have access to current user/circle/plan information.
    private func updateSiriContext() {
        SiriShortcutsService.shared.updateContext(
            userId: currentUser?.id,
            circleId: currentCircle?.id,
            plan: currentCircle?.plan
        )
    }
}
