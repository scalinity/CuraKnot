import SwiftUI
import LocalAuthentication

// MARK: - Biometric Gate View

/// Generic wrapper that requires biometric authentication before revealing content.
/// Used to protect condition photos from unauthorized viewing.
struct BiometricGateView<Content: View>: View {
    @ObservedObject var biometricManager: BiometricSessionManager
    let reason: String
    @ViewBuilder let content: () -> Content
    @State private var cachedBiometricIcon: String = "touchid"

    var body: some View {
        Group {
            if biometricManager.isAuthenticated {
                content()
            } else {
                lockedView
            }
        }
        .task {
            // Evaluate biometric type once on appear and cache the result
            let context = LAContext()
            _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
            cachedBiometricIcon = context.biometryType == .faceID ? "faceid" : "touchid"

            if !biometricManager.isSessionValid() {
                _ = await biometricManager.authenticate(reason: reason)
            }
        }
    }

    private var lockedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: cachedBiometricIcon)
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("Photos are protected")
                    .font(.headline)

                Text("Authenticate to view condition photos")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let error = biometricManager.authError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                Task {
                    _ = await biometricManager.authenticate(reason: reason)
                }
            } label: {
                Label("Unlock", systemImage: cachedBiometricIcon)
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .padding()
    }

}
