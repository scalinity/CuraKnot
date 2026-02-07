import SwiftUI

// MARK: - Expense Row

struct ExpenseRow: View {
    let expense: CareExpense

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(expense.category.color.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: expense.category.systemImage)
                    .font(.title3)
                    .foregroundStyle(expense.category.color)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.description)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let vendor = expense.vendorName, !vendor.isEmpty {
                        Text(vendor)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if expense.isRecurring {
                        Label("Recurring", systemImage: "arrow.trianglehead.2.clockwise")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }

                    if expense.receiptStorageKey != nil {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Amount
            VStack(alignment: .trailing, spacing: 2) {
                Text(expense.formattedAmount)
                    .font(.body.monospacedDigit())
                    .fontWeight(.medium)

                Text(expense.expenseDate, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var parts: [String] = [
            expense.category.displayName,
            expense.description,
            expense.formattedAmount
        ]
        if let vendor = expense.vendorName, !vendor.isEmpty {
            parts.append("from \(vendor)")
        }
        if expense.isRecurring {
            parts.append("recurring")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Preview

#Preview {
    List {
        ExpenseRow(expense: CareExpense(
            id: "1",
            circleId: "c1",
            patientId: "p1",
            createdBy: "u1",
            category: .medications,
            description: "Monthly Prescriptions",
            vendorName: "CVS Pharmacy",
            amount: 285.50,
            expenseDate: Date(),
            isRecurring: true,
            recurrenceRule: .monthly,
            parentExpenseId: nil,
            coveredByInsurance: 200.00,
            receiptStorageKey: "receipt-123",
            createdAt: Date(),
            updatedAt: Date()
        ))

        ExpenseRow(expense: CareExpense(
            id: "2",
            circleId: "c1",
            patientId: "p1",
            createdBy: "u1",
            category: .homeCare,
            description: "Home Aide - Week of Feb 3",
            vendorName: "Comfort Keepers",
            amount: 600.00,
            expenseDate: Date(),
            isRecurring: false,
            recurrenceRule: nil,
            parentExpenseId: nil,
            coveredByInsurance: 0,
            receiptStorageKey: nil,
            createdAt: Date(),
            updatedAt: Date()
        ))
    }
}
