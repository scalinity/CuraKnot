import SwiftUI

// MARK: - Monthly Cost Card

struct MonthlyCostCard: View {
    let total: Decimal
    let breakdown: [ExpenseCategory: Decimal]

    private var sortedBreakdown: [(category: ExpenseCategory, amount: Decimal)] {
        breakdown
            .sorted { $0.value > $1.value }
            .map { (category: $0.key, amount: $0.value) }
    }

    private var maxAmount: Decimal {
        sortedBreakdown.first?.amount ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(total, format: .currency(code: "USD"))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .accessibilityLabel("Total monthly cost, \(total, format: .currency(code: "USD"))")

                Text("this month (estimated)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !sortedBreakdown.isEmpty {
                Divider()

                VStack(spacing: 8) {
                    ForEach(sortedBreakdown, id: \.category) { item in
                        categoryBar(item.category, amount: item.amount)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .accessibilityElement(children: .contain)
    }

    private func categoryBar(_ category: ExpenseCategory, amount: Decimal) -> some View {
        VStack(spacing: 4) {
            HStack {
                Label(category.displayName, systemImage: category.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleOnly)

                Spacer()

                Text(amount, format: .currency(code: "USD"))
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                let fraction = maxAmount > 0 ? NSDecimalNumber(decimal: amount / maxAmount).doubleValue : 0
                let barWidth = max(4, geometry.size.width * CGFloat(min(fraction, 1.0)))

                RoundedRectangle(cornerRadius: 3)
                    .fill(category.color)
                    .frame(width: barWidth, height: 6)
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category.displayName), \(amount, format: .currency(code: "USD"))")
    }
}

// MARK: - Preview

#Preview {
    MonthlyCostCard(
        total: 4720,
        breakdown: [
            .homeCare: 2400,
            .medications: 850,
            .supplies: 320,
            .transportation: 450,
            .insurance: 700
        ]
    )
    .padding()
}
