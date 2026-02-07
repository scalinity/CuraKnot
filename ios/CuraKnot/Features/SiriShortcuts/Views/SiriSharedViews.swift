import SwiftUI

// MARK: - Shared Siri Snippet Views

/// Generic error view for Siri intent snippets
@available(iOS 16.0, *)
struct SiriErrorView: View {
    let message: String
    let icon: String
    let iconColor: Color

    init(message: String, icon: String = "exclamationmark.triangle.fill", iconColor: Color = .orange) {
        self.message = message
        self.icon = icon
        self.iconColor = iconColor
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .font(.title)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

/// Upgrade prompt view for features requiring Plus tier
@available(iOS 16.0, *)
struct SiriUpgradeView: View {
    let feature: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
                .font(.title)
            Text("Upgrade to Plus")
                .font(.headline)
            Text("\(feature) requires CuraKnot Plus")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - Standard Error Messages

/// Standardized error messages for Siri intents
enum SiriErrorMessages {
    static let signInRequired = "Please open CuraKnot and sign in first."
    static let noCircle = "Please select a care circle in CuraKnot first."
    static let noPatient = "Please add a patient in CuraKnot first."
    static let upgradeRequired = "This feature requires CuraKnot Plus."
    static let genericError = "Something went wrong. Please try again."
}
