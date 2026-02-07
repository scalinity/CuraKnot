import Foundation
import SwiftUI

// MARK: - Add Expense View Model

@MainActor
final class AddExpenseViewModel: ObservableObject {
    @Published var category: ExpenseCategory = .homeCare
    @Published var expenseDescription: String = ""
    @Published var vendorName: String = ""
    @Published var amount: Decimal? = nil
    @Published var expenseDate: Date = Date()
    @Published var isRecurring: Bool = false
    @Published var recurrenceRule: RecurrenceRule = .monthly
    @Published var coveredByInsurance: Decimal? = nil
    @Published var receiptImage: UIImage?
    @Published var showingReceiptCapture = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    var outOfPocket: Decimal {
        (amount ?? 0) - (coveredByInsurance ?? 0)
    }

    var isValid: Bool {
        !expenseDescription.isEmpty &&
        (amount ?? 0) > 0 &&
        (coveredByInsurance ?? 0) <= (amount ?? 0) &&
        (coveredByInsurance ?? 0) >= 0
    }

    private let careCostService: CareCostService
    let circleId: String
    let patientId: String
    let userId: String

    init(careCostService: CareCostService, circleId: String, patientId: String, userId: String) {
        self.careCostService = careCostService
        self.circleId = circleId
        self.patientId = patientId
        self.userId = userId
    }

    func save() async -> Bool {
        guard isValid else { return false }
        isSaving = true
        defer { isSaving = false }

        do {
            let expenseId = UUID().uuidString
            let now = Date()

            let expense = CareExpense(
                id: expenseId,
                circleId: circleId,
                patientId: patientId,
                createdBy: userId,
                category: category,
                description: expenseDescription,
                vendorName: vendorName.isEmpty ? nil : vendorName,
                amount: amount ?? 0,
                expenseDate: expenseDate,
                isRecurring: isRecurring,
                recurrenceRule: isRecurring ? recurrenceRule : nil,
                parentExpenseId: nil,
                coveredByInsurance: coveredByInsurance ?? 0,
                receiptStorageKey: nil,
                createdAt: now,
                updatedAt: now
            )

            _ = try await careCostService.createExpense(expense)

            if let image = receiptImage, let jpegData = image.jpegData(compressionQuality: 0.7) {
                _ = try await careCostService.uploadReceipt(
                    expenseId: expenseId,
                    circleId: circleId,
                    imageData: jpegData
                )
            }

            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
