import SwiftUI

// MARK: - Wellness Preview View

/// Preview shown to FREE tier users who don't have access to wellness features
/// Encourages upgrade to Plus or Family plan
struct WellnessPreviewView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue.gradient)

                    Text("Caregiver Wellness")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Track your wellbeing and get personalized support")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                // Feature list
                VStack(alignment: .leading, spacing: 20) {
                    WellnessFeatureRow(
                        icon: "checkmark.circle.fill",
                        iconColor: .green,
                        title: "Weekly Check-Ins",
                        description: "Quick 30-second wellness assessments"
                    )

                    WellnessFeatureRow(
                        icon: "chart.line.uptrend.xyaxis",
                        iconColor: .blue,
                        title: "Wellness Tracking",
                        description: "Monitor your stress, sleep, and capacity over time"
                    )

                    WellnessFeatureRow(
                        icon: "bell.badge.fill",
                        iconColor: .orange,
                        title: "Burnout Detection",
                        description: "Get gentle alerts when you need to slow down"
                    )

                    WellnessFeatureRow(
                        icon: "person.2.fill",
                        iconColor: .purple,
                        title: "Delegation Suggestions",
                        description: "Personalized suggestions for sharing the load"
                    )

                    WellnessFeatureRow(
                        icon: "lock.fill",
                        iconColor: .gray,
                        title: "Private & Secure",
                        description: "Your wellness data stays private - never shared"
                    )
                }
                .padding(.horizontal)

                Spacer(minLength: 32)

                // Upgrade CTA
                VStack(spacing: 16) {
                    Text("Available with Plus or Family")
                        .font(.headline)

                    Button {
                        // Navigate to subscription screen
                    } label: {
                        Text("Upgrade Now")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text("Starting at $9.99/month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Wellness Feature Row

private struct WellnessFeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    WellnessPreviewView()
}
