import Foundation
import GRDB
import os

private let logger = Logger(subsystem: "com.curaknot.app", category: "CareCostService")

// MARK: - Care Cost Error

enum CareCostError: LocalizedError {
    case featureNotAvailable
    case invalidAmount
    case coverageExceedsAmount
    case invalidZipCode
    case descriptionTooLong
    case vendorNameTooLong
    case receiptTooLarge
    case uploadFailed(String)
    case exportFailed(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .featureNotAvailable:
            return "Upgrade to Plus to track care costs."
        case .invalidAmount:
            return "Amount must be greater than zero."
        case .coverageExceedsAmount:
            return "Insurance coverage cannot exceed the total amount."
        case .invalidZipCode:
            return "Please enter a valid 5-digit zip code."
        case .descriptionTooLong:
            return "Description must be 1,000 characters or fewer."
        case .vendorNameTooLong:
            return "Vendor name must be 200 characters or fewer."
        case .receiptTooLarge:
            return "Receipt image must be under 10 MB."
        case .uploadFailed(let msg):
            return "Failed to upload receipt: \(msg)"
        case .exportFailed(let msg):
            return "Failed to generate report: \(msg)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Export Format

enum ExportFormat: String, Codable {
    case pdf = "PDF"
    case csv = "CSV"
}

// MARK: - Estimate Request/Response (for Edge Function)

struct EstimateCostsRequest: Encodable {
    let circleId: String
    let patientId: String
    let zipCode: String
    let scenarios: [ScenarioRequest]

    struct ScenarioRequest: Encodable {
        let type: String
        let homeCareHours: Int?
    }
}

struct EstimateCostsResponse: Decodable {
    let success: Bool
    let scenarios: [ScenarioResult]
    let localCostData: LocalCostInfo

    struct ScenarioResult: Decodable {
        let type: String
        let scenarioName: String
        let monthlyTotal: Decimal
        let yearlyTotal: Decimal
        let breakdown: [BreakdownItem]
        let comparedToCurrent: Decimal
    }

    struct BreakdownItem: Decodable {
        let category: String
        let amount: Decimal
    }

    struct LocalCostInfo: Decodable {
        let source: String
        let year: Int
        let areaName: String
    }
}

struct ExpenseReportRequest: Encodable {
    let circleId: String
    let patientId: String
    let startDate: String
    let endDate: String
    let format: String
    let includeReceipts: Bool
}

struct ExpenseReportResponse: Decodable {
    let success: Bool
    let reportUrl: String
    let totalExpenses: Decimal
    let byCategory: [String: Decimal]
    let expenseCount: Int
    let expiresAt: String
}

// MARK: - Care Cost Service

final class CareCostService {
    let databaseManager: DatabaseManager
    let supabaseClient: SupabaseClient
    let subscriptionManager: SubscriptionManager

    /// Maximum receipt image size: 10 MB
    private static let maxReceiptSize = 10_485_760

    init(databaseManager: DatabaseManager, supabaseClient: SupabaseClient, subscriptionManager: SubscriptionManager) {
        self.databaseManager = databaseManager
        self.supabaseClient = supabaseClient
        self.subscriptionManager = subscriptionManager
    }

    // MARK: - Feature Access

    @MainActor
    func hasExpenseAccess() -> Bool {
        subscriptionManager.hasFeature(.careCostTracking)
    }

    @MainActor
    func hasProjectionAccess() -> Bool {
        subscriptionManager.hasFeature(.careCostProjections)
    }

    @MainActor
    func hasExportAccess() -> Bool {
        subscriptionManager.hasFeature(.careCostExport)
    }

    // MARK: - Expense CRUD

    /// Maximum description length
    private static let maxDescriptionLength = 1000
    /// Maximum vendor name length
    private static let maxVendorNameLength = 200

    func createExpense(_ expense: CareExpense) async throws -> CareExpense {
        guard await hasExpenseAccess() else { throw CareCostError.featureNotAvailable }
        guard expense.amount > 0 else { throw CareCostError.invalidAmount }
        guard expense.coveredByInsurance <= expense.amount else { throw CareCostError.coverageExceedsAmount }
        guard expense.description.count <= Self.maxDescriptionLength else { throw CareCostError.descriptionTooLong }
        guard (expense.vendorName ?? "").count <= Self.maxVendorNameLength else { throw CareCostError.vendorNameTooLong }

        try databaseManager.write { db in
            var record = expense
            try record.insert(db)
        }

        do {
            try await supabaseClient.from("care_expenses").insert(expense).execute()
        } catch {
            logger.error("Failed to sync expense to server: \(error.localizedDescription)")
        }

        return expense
    }

    func fetchExpenses(circleId: String, patientId: String? = nil, month: Date? = nil) async throws -> [CareExpense] {
        do {
            var query = await supabaseClient.from("care_expenses")
                .select()
                .eq("circle_id", circleId)

            if let patientId = patientId {
                query = query.eq("patient_id", patientId)
            }

            let expenses: [CareExpense] = try await query
                .order("expense_date", ascending: false)
                .execute()

            try databaseManager.write { db in
                for var expense in expenses {
                    try expense.save(db)
                }
            }

            return filterByMonth(expenses, month: month)
        } catch {
            logger.warning("Fetching expenses from local DB: \(error.localizedDescription)")
            return try databaseManager.read { db in
                var request = CareExpense
                    .filter(Column("circleId") == circleId)

                if let patientId = patientId {
                    request = request.filter(Column("patientId") == patientId)
                }

                let expenses = try request
                    .order(Column("expenseDate").desc)
                    .fetchAll(db)

                return self.filterByMonth(expenses, month: month)
            }
        }
    }

    func updateExpense(_ expense: CareExpense) async throws {
        guard await hasExpenseAccess() else { throw CareCostError.featureNotAvailable }
        guard expense.amount > 0 else { throw CareCostError.invalidAmount }
        guard expense.coveredByInsurance <= expense.amount else { throw CareCostError.coverageExceedsAmount }
        guard expense.description.count <= Self.maxDescriptionLength else { throw CareCostError.descriptionTooLong }
        guard (expense.vendorName ?? "").count <= Self.maxVendorNameLength else { throw CareCostError.vendorNameTooLong }

        try databaseManager.write { db in
            var record = expense
            try record.update(db)
        }

        do {
            try await supabaseClient.from("care_expenses")
                .update(expense)
                .eq("id", expense.id)
                .execute()
        } catch {
            logger.error("Failed to sync expense update: \(error.localizedDescription)")
        }
    }

    func deleteExpense(id: String) async throws {
        guard await hasExpenseAccess() else { throw CareCostError.featureNotAvailable }

        _ = try databaseManager.write { db in
            try CareExpense.deleteOne(db, key: id)
        }

        do {
            try await supabaseClient.from("care_expenses")
                .eq("id", id)
                .delete()
        } catch {
            logger.error("Failed to sync expense deletion: \(error.localizedDescription)")
        }
    }

    // MARK: - Receipt Upload

    func uploadReceipt(expenseId: String, circleId: String, imageData: Data) async throws -> String {
        guard await hasExpenseAccess() else { throw CareCostError.featureNotAvailable }
        guard imageData.count <= Self.maxReceiptSize else { throw CareCostError.receiptTooLarge }

        let storagePath = "\(circleId)/\(expenseId)/receipt.jpg"

        do {
            _ = try await supabaseClient.storage("care-expense-receipts")
                .upload(path: storagePath, data: imageData, contentType: "image/jpeg")

            let now = Date()
            try databaseManager.write { db in
                guard var expense = try CareExpense.fetchOne(db, key: expenseId) else {
                    throw CareCostError.uploadFailed("Expense not found")
                }
                expense.receiptStorageKey = storagePath
                expense.updatedAt = now
                try expense.update(db)
            }

            let isoDate = ISO8601DateFormatter().string(from: now)
            try await supabaseClient.from("care_expenses")
                .update(["receipt_storage_key": storagePath, "updated_at": isoDate])
                .eq("id", expenseId)
                .execute()

            return storagePath
        } catch let error as CareCostError {
            throw error
        } catch {
            throw CareCostError.uploadFailed(error.localizedDescription)
        }
    }

    func getReceiptURL(storagePath: String) async throws -> URL {
        try await supabaseClient.storage("care-expense-receipts")
            .createSignedURL(path: storagePath, expiresIn: 3600)
    }

    // MARK: - Cost Estimates

    func generateCostEstimates(circleId: String, patientId: String, zipCode: String, scenarios: [ScenarioType]) async throws -> EstimateCostsResponse {
        guard await hasProjectionAccess() else { throw CareCostError.featureNotAvailable }
        guard zipCode.count == 5, zipCode.allSatisfy(\.isNumber) else {
            throw CareCostError.invalidZipCode
        }

        let request = EstimateCostsRequest(
            circleId: circleId,
            patientId: patientId,
            zipCode: zipCode,
            scenarios: scenarios.map { .init(type: $0.rawValue, homeCareHours: nil) }
        )

        do {
            let response: EstimateCostsResponse = try await supabaseClient
                .functions("estimate-care-costs")
                .invoke(body: request)

            return response
        } catch let error as CareCostError {
            throw error
        } catch {
            throw CareCostError.networkError(error)
        }
    }

    func fetchEstimates(circleId: String, patientId: String) async throws -> [CareCostEstimate] {
        let estimates: [CareCostEstimate] = try await supabaseClient.from("care_cost_estimates")
            .select()
            .eq("circle_id", circleId)
            .eq("patient_id", patientId)
            .order("is_current", ascending: false)
            .execute()

        try databaseManager.write { db in
            for var estimate in estimates {
                try estimate.save(db)
            }
        }

        return estimates
    }

    // MARK: - Financial Resources

    func fetchFinancialResources(category: ResourceCategory? = nil) async throws -> [FinancialResource] {
        do {
            var query = await supabaseClient.from("financial_resources")
                .select()
                .eq("is_active", "true")

            if let category = category {
                query = query.eq("category", category.rawValue)
            }

            let resources: [FinancialResource] = try await query
                .order("is_featured", ascending: false)
                .execute()

            try databaseManager.write { db in
                for var resource in resources {
                    try resource.save(db)
                }
            }

            return resources
        } catch {
            logger.warning("Fetching financial resources from local DB: \(error.localizedDescription)")
            return try databaseManager.read { db in
                var request = FinancialResource
                    .filter(Column("isActive") == true)

                if let category = category {
                    request = request.filter(Column("category") == category.rawValue)
                }

                return try request
                    .order(Column("isFeatured").desc)
                    .fetchAll(db)
            }
        }
    }

    // MARK: - Export

    func generateExpenseReport(circleId: String, patientId: String, startDate: Date, endDate: Date, format: ExportFormat, includeReceipts: Bool = false) async throws -> URL {
        guard await hasExportAccess() else { throw CareCostError.featureNotAvailable }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let request = ExpenseReportRequest(
            circleId: circleId,
            patientId: patientId,
            startDate: dateFormatter.string(from: startDate),
            endDate: dateFormatter.string(from: endDate),
            format: format.rawValue,
            includeReceipts: includeReceipts
        )

        do {
            let response: ExpenseReportResponse = try await supabaseClient
                .functions("generate-expense-report")
                .invoke(body: request)

            guard let url = URL(string: response.reportUrl) else {
                throw CareCostError.exportFailed("Invalid download URL")
            }

            return url
        } catch let error as CareCostError {
            throw error
        } catch {
            throw CareCostError.networkError(error)
        }
    }

    // MARK: - Monthly Summary

    func calculateMonthlySummary(expenses: [CareExpense]) -> (total: Decimal, breakdown: [ExpenseCategory: Decimal], insuranceCovered: Decimal, outOfPocket: Decimal) {
        var breakdown: [ExpenseCategory: Decimal] = [:]
        var totalInsurance: Decimal = 0

        for expense in expenses {
            breakdown[expense.category, default: 0] += expense.amount
            totalInsurance += expense.coveredByInsurance
        }

        let total = expenses.reduce(Decimal(0)) { $0 + $1.amount }
        let oop = total - totalInsurance

        return (total, breakdown, totalInsurance, oop)
    }

    // MARK: - Preview Support

    #if DEBUG
    @MainActor
    static var preview: CareCostService {
        let container = DependencyContainer()
        return CareCostService(
            databaseManager: container.databaseManager,
            supabaseClient: container.supabaseClient,
            subscriptionManager: container.subscriptionManager
        )
    }
    #endif

    // MARK: - Helpers

    private func filterByMonth(_ expenses: [CareExpense], month: Date?) -> [CareExpense] {
        guard let month = month else { return expenses }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: month)
        return expenses.filter { expense in
            let expComponents = calendar.dateComponents([.year, .month], from: expense.expenseDate)
            return expComponents.year == components.year && expComponents.month == components.month
        }
    }
}
