import SwiftUI

// MARK: - Scenario Card

struct ScenarioCard: View {
    let estimate: CareCostEstimate
    let currentMonthly: Decimal?
    let isCurrent: Bool

    private var delta: Decimal? {
        guard let current = currentMonthly, !isCurrent else { return nil }
        return estimate.totalMonthly - current
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: estimate.scenarioType.systemImage)
                    .font(.title3)
                    .foregroundStyle(isCurrent ? .blue : .purple)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(estimate.scenarioName)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        if isCurrent {
                            Text("Current")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                    }

                    Text(estimate.scenarioType.scenarioDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

            Divider()

            // Costs
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(estimate.formattedMonthlyTotal)
                        .font(.system(.title2, design: .rounded, weight: .bold))

                    Text("/month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(estimate.formattedAnnualTotal)
                        .font(.headline)
                        .fontWeight(.medium)

                    Text("/year")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Delta from current
            if let delta = delta {
                HStack(spacing: 4) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2)

                    let absDelta = abs(delta)
                    Text("\(delta >= 0 ? "+" : "-")\(absDelta, format: .currency(code: "USD"))/mo from current")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(delta >= 0 ? .red : .green)
                .accessibilityLabel(
                    delta >= 0
                    ? "\(abs(delta), format: .currency(code: "USD")) more per month than current"
                    : "\(abs(delta), format: .currency(code: "USD")) less per month than current"
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Preview

#Preview("Current Scenario") {
    ScenarioCard(
        estimate: CareCostEstimate(
            id: "1",
            circleId: "c1",
            patientId: "p1",
            scenarioName: "Current Care",
            scenarioType: .current,
            isCurrent: true,
            totalMonthly: 4720,
            dataSource: "GENWORTH",
            dataYear: 2023,
            createdAt: Date(),
            updatedAt: Date()
        ),
        currentMonthly: nil,
        isCurrent: true
    )
    .padding()
}

#Preview("Projected Scenario") {
    ScenarioCard(
        estimate: CareCostEstimate(
            id: "2",
            circleId: "c1",
            patientId: "p1",
            scenarioName: "Assisted Living",
            scenarioType: .assistedLiving,
            isCurrent: false,
            medicationsMonthly: 150,
            facilityMonthly: 5350,
            totalMonthly: 6500,
            dataSource: "GENWORTH",
            dataYear: 2023,
            createdAt: Date(),
            updatedAt: Date()
        ),
        currentMonthly: 4720,
        isCurrent: false
    )
    .padding()
}
