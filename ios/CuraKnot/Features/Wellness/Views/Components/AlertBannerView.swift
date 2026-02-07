import SwiftUI

// MARK: - Alert Banner View

/// Banner view for displaying wellness alerts with delegation suggestions
/// Designed to be gentle and non-guilt-inducing
struct AlertBannerView: View {
    let alert: WellnessAlert
    let onDismiss: () -> Void

    @State private var isExpanded = false

    private var backgroundColor: Color {
        switch alert.riskLevel {
        case .high: return .red.opacity(0.1)
        case .moderate: return .orange.opacity(0.1)
        case .low: return .green.opacity(0.1)
        }
    }

    private var accentColor: Color {
        switch alert.riskLevel {
        case .high: return .red
        case .moderate: return .orange
        case .low: return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .top) {
                Image(systemName: alert.iconName)
                    .font(.title2)
                    .foregroundStyle(accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(alert.title)
                        .font(.headline)

                    Text(alert.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color(.systemGray5))
                        .clipShape(SwiftUI.Circle())
                }
            }

            // Delegation suggestions
            if let suggestions = alert.delegationSuggestions, !suggestions.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        withAnimation {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "person.2.fill")
                                .font(.caption)
                            Text("People who can help")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                        }
                        .foregroundStyle(.primary)
                    }

                    if isExpanded {
                        ForEach(suggestions) { suggestion in
                            DelegationSuggestionRow(suggestion: suggestion)
                        }
                    }
                }
            }
        }
        .padding()
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accentColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Delegation Suggestion Row

private struct DelegationSuggestionRow: View {
    let suggestion: DelegationSuggestion

    var body: some View {
        HStack(spacing: 12) {
            // Avatar placeholder
            SwiftUI.Circle()
                .fill(Color(.systemGray4))
                .frame(width: 32, height: 32)
                .overlay(
                    Text(initials(from: suggestion.fullName))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.fullName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let circleName = suggestion.circleName {
                    Text(circleName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Action button could be added here for direct messaging
        }
        .padding(.vertical, 4)
    }

    private func initials(from name: String) -> String {
        let components = name.components(separatedBy: " ")
        let firstInitial = components.first?.first.map(String.init) ?? ""
        let lastInitial = components.count > 1 ? components.last?.first.map(String.init) ?? "" : ""
        return (firstInitial + lastInitial).uppercased()
    }
}
