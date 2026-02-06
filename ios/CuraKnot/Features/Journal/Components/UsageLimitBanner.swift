import SwiftUI

// MARK: - Usage Limit Banner

/// A banner showing journal entry usage for free tier users
struct UsageLimitBanner: View {
    let current: Int
    let limit: Int
    let onUpgrade: () -> Void

    private var remaining: Int {
        max(0, limit - current)
    }

    private var isAtLimit: Bool {
        current >= limit
    }

    private var isNearLimit: Bool {
        remaining <= 1 && !isAtLimit
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: isAtLimit ? "exclamationmark.circle.fill" : "info.circle.fill")
                .font(.title3)
                .foregroundStyle(isAtLimit ? .red : .orange)

            // Message
            VStack(alignment: .leading, spacing: 2) {
                if isAtLimit {
                    Text("You've reached your monthly limit")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Upgrade for unlimited entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isNearLimit {
                    Text("\(remaining) entry left this month")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Free plan: \(current)/\(limit) used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(remaining) entries remaining")
                        .font(.subheadline)
                    Text("Free plan: \(current)/\(limit) this month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Upgrade button
            Button(action: onUpgrade) {
                Text("Upgrade")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isAtLimit ? Color.red.opacity(0.1) : Color.orange.opacity(0.1))
        )
    }
}

// MARK: - Compact Usage Indicator

/// A compact usage indicator for toolbar or inline display
struct UsageIndicator: View {
    let current: Int
    let limit: Int

    private var remaining: Int {
        max(0, limit - current)
    }

    private var isAtLimit: Bool {
        current >= limit
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text")
                .font(.caption)

            Text("\(remaining) left")
                .font(.caption)
        }
        .foregroundStyle(isAtLimit ? .red : (remaining <= 1 ? .orange : .secondary))
    }
}

#Preview {
    VStack(spacing: 20) {
        UsageLimitBanner(current: 3, limit: 5) {
            print("Upgrade tapped")
        }

        UsageLimitBanner(current: 4, limit: 5) {
            print("Upgrade tapped")
        }

        UsageLimitBanner(current: 5, limit: 5) {
            print("Upgrade tapped")
        }

        HStack {
            UsageIndicator(current: 2, limit: 5)
            UsageIndicator(current: 4, limit: 5)
            UsageIndicator(current: 5, limit: 5)
        }
    }
    .padding()
}
