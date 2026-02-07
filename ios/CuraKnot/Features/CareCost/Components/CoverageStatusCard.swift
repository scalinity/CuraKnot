import SwiftUI

// MARK: - Coverage Status Card

struct CoverageStatusCard: View {
    let totalAmount: Decimal
    let insuranceCovered: Decimal
    let outOfPocket: Decimal

    private var insurancePercentage: Int {
        guard totalAmount > 0 else { return 0 }
        let fraction = NSDecimalNumber(decimal: insuranceCovered / totalAmount).doubleValue
        return Int((fraction * 100).rounded())
    }

    private var outOfPocketPercentage: Int {
        guard totalAmount > 0 else { return 0 }
        return 100 - insurancePercentage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coverage Breakdown")
                .font(.subheadline)
                .fontWeight(.semibold)

            VStack(spacing: 8) {
                coverageRow(
                    label: "Insurance Covered",
                    percentage: insurancePercentage,
                    amount: insuranceCovered,
                    color: .green
                )

                coverageRow(
                    label: "Out of Pocket",
                    percentage: outOfPocketPercentage,
                    amount: outOfPocket,
                    color: .orange
                )
            }

            // Coverage bar
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    if insurancePercentage > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green)
                            .frame(width: geometry.size.width * CGFloat(insurancePercentage) / 100)
                    }
                    if outOfPocketPercentage > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.orange)
                            .frame(width: geometry.size.width * CGFloat(outOfPocketPercentage) / 100)
                    }
                }
            }
            .frame(height: 8)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .accessibilityElement(children: .contain)
    }

    private func coverageRow(label: String, percentage: Int, amount: Decimal, color: Color) -> some View {
        HStack {
            SwiftUI.Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(percentage)%")
                .font(.caption)
                .fontWeight(.medium)

            Text(amount, format: .currency(code: "USD"))
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(percentage) percent, \(amount, format: .currency(code: "USD"))")
    }
}

// MARK: - Preview

#Preview {
    CoverageStatusCard(
        totalAmount: 4720,
        insuranceCovered: 2830,
        outOfPocket: 1890
    )
    .padding()
}
