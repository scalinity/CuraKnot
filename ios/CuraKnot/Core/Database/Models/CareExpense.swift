import Foundation
import GRDB
import SwiftUI

// MARK: - Expense Category

enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case homeCare = "HOME_CARE"
    case medications = "MEDICATIONS"
    case supplies = "SUPPLIES"
    case transportation = "TRANSPORTATION"
    case insurance = "INSURANCE"
    case equipment = "EQUIPMENT"
    case facility = "FACILITY"
    case professional = "PROFESSIONAL"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .homeCare: return "Home Care"
        case .medications: return "Medications"
        case .supplies: return "Medical Supplies"
        case .transportation: return "Transportation"
        case .insurance: return "Insurance"
        case .equipment: return "Equipment"
        case .facility: return "Facility"
        case .professional: return "Professional"
        }
    }

    var systemImage: String {
        switch self {
        case .homeCare: return "house.fill"
        case .medications: return "pill.fill"
        case .supplies: return "cross.case.fill"
        case .transportation: return "car.fill"
        case .insurance: return "shield.fill"
        case .equipment: return "wrench.and.screwdriver.fill"
        case .facility: return "building.2.fill"
        case .professional: return "person.fill"
        }
    }

    var color: Color {
        switch self {
        case .homeCare: return .blue
        case .medications: return .green
        case .supplies: return .orange
        case .transportation: return .purple
        case .insurance: return .teal
        case .equipment: return .indigo
        case .facility: return .pink
        case .professional: return .brown
        }
    }
}

// MARK: - Recurrence Rule

enum RecurrenceRule: String, Codable, CaseIterable {
    case weekly = "WEEKLY"
    case biweekly = "BIWEEKLY"
    case monthly = "MONTHLY"

    var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .biweekly: return "Every 2 Weeks"
        case .monthly: return "Monthly"
        }
    }
}

// MARK: - Care Expense Model

struct CareExpense: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let circleId: String
    let patientId: String
    let createdBy: String
    var category: ExpenseCategory
    var description: String
    var vendorName: String?
    var amount: Decimal
    var expenseDate: Date
    var isRecurring: Bool
    var recurrenceRule: RecurrenceRule?
    var parentExpenseId: String?
    var coveredByInsurance: Decimal
    var receiptStorageKey: String?
    let createdAt: Date
    var updatedAt: Date

    // MARK: - Computed Properties

    var outOfPocket: Decimal {
        amount - coveredByInsurance
    }

    var formattedAmount: String {
        Self.currencyFormatter.string(from: amount as NSDecimalNumber) ?? "$0.00"
    }

    var formattedOutOfPocket: String {
        Self.currencyFormatter.string(from: outOfPocket as NSDecimalNumber) ?? "$0.00"
    }

    var formattedCoveredByInsurance: String {
        Self.currencyFormatter.string(from: coveredByInsurance as NSDecimalNumber) ?? "$0.00"
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    var formattedExpenseDate: String {
        Self.dateFormatter.string(from: expenseDate)
    }
}

// MARK: - GRDB Conformance

extension CareExpense: FetchableRecord, PersistableRecord {
    static let databaseTableName = "careExpenses"
}
