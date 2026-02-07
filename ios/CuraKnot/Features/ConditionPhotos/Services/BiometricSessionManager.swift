import Foundation
import LocalAuthentication
import UIKit
import Combine

// MARK: - Biometric Session Manager

@MainActor
final class BiometricSessionManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var authError: String?

    // MARK: - Private Properties

    private var lastAuthDate: Date?
    private let sessionTimeout: TimeInterval = 60 // 60 seconds for PHI data
    private var backgroundObserver: AnyCancellable?
    private var foregroundObserver: AnyCancellable?

    // MARK: - Initialization

    init() {
        observeAppLifecycle()
    }

    deinit {
        backgroundObserver?.cancel()
        foregroundObserver?.cancel()
    }

    // MARK: - Authentication

    /// Authenticate with biometrics (Face ID / Touch ID) — no passcode fallback
    func authenticate(reason: String = "Authenticate to view condition photos") async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "" // Hide fallback button
        var error: NSError?

        // Check biometric availability — biometrics only, no passcode fallback
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            authError = error?.localizedDescription ?? "Biometric authentication not available on this device."
            return false
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )

            if success {
                lastAuthDate = Date()
                isAuthenticated = true
                authError = nil
            }

            return success
        } catch let authErr as LAError {
            invalidateSession()
            switch authErr.code {
            case .userCancel:
                authError = nil // User chose to cancel, not an error
            case .biometryLockout:
                authError = "Too many failed attempts. Biometric authentication is locked."
            case .biometryNotAvailable:
                authError = "Biometric authentication not available."
            case .biometryNotEnrolled:
                authError = "No biometric data enrolled. Set up Face ID or Touch ID in Settings."
            case .userFallback:
                authError = "Biometric authentication is required to view condition photos."
            default:
                authError = "Authentication failed. Try again."
            }
            return false
        } catch {
            invalidateSession()
            authError = "Authentication failed unexpectedly."
            return false
        }
    }

    /// Check if current session is still valid (within timeout)
    func isSessionValid() -> Bool {
        guard let lastAuth = lastAuthDate else {
            isAuthenticated = false
            return false
        }
        let valid = Date().timeIntervalSince(lastAuth) < sessionTimeout
        if !valid {
            isAuthenticated = false
            lastAuthDate = nil
        }
        return valid
    }

    /// Invalidate the current session (e.g., on app background)
    func invalidateSession() {
        lastAuthDate = nil
        isAuthenticated = false
    }

    /// Ensure authenticated, re-prompting if session expired
    func ensureAuthenticated(reason: String = "Authenticate to view condition photos") async -> Bool {
        if isSessionValid() {
            return true
        }
        return await authenticate(reason: reason)
    }

    // MARK: - App Lifecycle Observers

    private func observeAppLifecycle() {
        backgroundObserver = NotificationCenter.default
            .publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.invalidateSession()
                }
            }

        foregroundObserver = NotificationCenter.default
            .publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    // Re-validate session on foreground return
                    _ = self?.isSessionValid()
                }
            }
    }
}
