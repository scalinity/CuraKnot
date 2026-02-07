import SwiftUI

// MARK: - Resource Card

struct ResourceCard: View {
    let resource: FinancialResource
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Category icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(categoryColor.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: resource.category.systemImage)
                        .font(.title3)
                        .foregroundStyle(categoryColor)
                }

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(resource.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(resource.resourceDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                // Action indicator
                VStack {
                    Image(systemName: actionIcon)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(resource.title), \(resource.resourceDescription)")
        .accessibilityHint(accessibilityHintText)
    }

    private var categoryColor: Color {
        switch resource.category {
        case .medicare: return .blue
        case .medicaid: return .green
        case .va: return .indigo
        case .tax: return .orange
        case .planning: return .purple
        }
    }

    private var actionIcon: String {
        switch resource.resourceType {
        case .directory: return "magnifyingglass"
        case .calculator: return "function"
        default: return "arrow.up.right.square"
        }
    }

    private var accessibilityHintText: String {
        switch resource.resourceType {
        case .directory: return "Opens directory search"
        case .calculator: return "Opens calculator tool"
        default: return "Opens in browser"
        }
    }
}

// MARK: - Preview

#Preview {
    List {
        ResourceCard(resource: FinancialResource(
            id: "1",
            title: "Medicare Home Health Benefits",
            resourceDescription: "Learn what home health services Medicare covers and eligibility requirements.",
            url: "https://www.medicare.gov/coverage/home-health-services",
            resourceType: .officialLink,
            category: .medicare,
            contentMarkdown: nil,
            states: nil,
            isFeatured: true,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )) {
            print("Tapped")
        }

        ResourceCard(resource: FinancialResource(
            id: "2",
            title: "Find Your State Medicaid Office",
            resourceDescription: "Search for Medicaid programs and contact information in your state.",
            url: "https://www.medicaid.gov/state-overviews",
            resourceType: .directory,
            category: .medicaid,
            contentMarkdown: nil,
            states: nil,
            isFeatured: false,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )) {
            print("Tapped")
        }
    }
}
