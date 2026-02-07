import SwiftUI

// MARK: - Plus Required View

struct PlusRequiredView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // Watch Icon
            Image(systemName: "applewatch")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            // Title
            Text("Watch App")
                .font(.title3.bold())

            // Description
            Text("Upgrade to Plus or Family to access CuraKnot on your Apple Watch.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Spacer()

            // Instructions
            Text("Open CuraKnot on iPhone to upgrade")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom)
        }
        .padding()
        .accessibilityIdentifier("PlusRequiredView")
    }
}

#Preview {
    PlusRequiredView()
}
