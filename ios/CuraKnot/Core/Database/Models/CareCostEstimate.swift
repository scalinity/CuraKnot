import Foundation
import GRDB

// MARK: - Scenario Type

enum ScenarioType: String, Codable, CaseIterable, Identifiable {
    case current = "CURRENT"
    case fullTimeHome = "FULL_TIME_HOME"
    case twentyFourSeven = "TWENTY_FOUR_SEVEN"
    case assistedLiving = "ASSISTED_LIVING"
    case memoryCare = "MEMORY_CARE"
    case nursingHome = "NURSING_HOME"
    case custom = "CUSTOM"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .current: return "Current Care"
        case .fullTimeHome: return "Full-Time Home Care"
        case .twentyFourSeven: return "24/7 Home Care"
        case .assistedLiving: return "Assisted Living"
        case .memoryCare: return "Memory Care"
        case .nursingHome: return "Nursing Home"
        case .custom: return "Custom Scenario"
        }
    }

    var scenarioDescription: String {
        switch self {
        case .current: return "Based on your actual tracked expenses"
        case .fullTimeHome: return "Full-time home aide during business hours (40 hrs/week)"
        case .twentyFourSeven: return "Round-the-clock home care with multiple caregivers"
        case .assistedLiving: return "Assisted living facility with shared services"
        case .memoryCare: return "Specialized memory care unit with secured environment"
        case .nursingHome: return "Skilled nursing facility with 24/7 medical staff"
        case .custom: return "Your own customized care scenario"
        }
    }

    var systemImage: String {
        switch self {
        case .current: return "chart.bar.fill"
        case .fullTimeHome: return "house.fill"
        case .twentyFourSeven: return "clock.fill"
        case .assistedLiving: return "building.fill"
        case .memoryCare: return "brain.head.profile"
        case .nursingHome: return "cross.case.fill"
        case .custom: return "slider.horizontal.3"
        }
    }
}

// MARK: - Care Cost Estimate Model

struct CareCostEstimate: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var circleId: String
    var patientId: String
    var scenarioName: String
    var scenarioType: ScenarioType
    var isCurrent: Bool
    var homeCareHoursWeekly: Int?
    var homeCareHourlyRate: Decimal?
    var homeCareMonthly: Decimal?
    var medicationsMonthly: Decimal?
    var suppliesMonthly: Decimal?
    var transportationMonthly: Decimal?
    var facilityMonthly: Decimal?
    var otherMonthly: Decimal?
    var totalMonthly: Decimal
    var medicareCoveragePct: Decimal?
    var medicaidCoveragePct: Decimal?
    var privateInsurancePct: Decimal?
    var outOfPocketMonthly: Decimal?
    var notes: String?
    var dataSource: String
    var dataYear: Int
    let createdAt: Date
    var updatedAt: Date

    // MARK: - Computed Properties

    var annualTotal: Decimal {
        totalMonthly * 12
    }

    var formattedMonthlyTotal: String {
        Self.currencyFormatter.string(from: totalMonthly as NSDecimalNumber) ?? "$0.00"
    }

    var formattedAnnualTotal: String {
        Self.currencyFormatter.string(from: annualTotal as NSDecimalNumber) ?? "$0.00"
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    /// Breakdown of costs by category
    var breakdown: [String: Decimal] {
        var result: [String: Decimal] = [:]
        if let v = homeCareMonthly, v > 0 { result["Home Care"] = v }
        if let v = medicationsMonthly, v > 0 { result["Medications"] = v }
        if let v = suppliesMonthly, v > 0 { result["Supplies"] = v }
        if let v = transportationMonthly, v > 0 { result["Transportation"] = v }
        if let v = facilityMonthly, v > 0 { result["Facility"] = v }
        if let v = otherMonthly, v > 0 { result["Other"] = v }
        return result
    }
}

// MARK: - GRDB Conformance

extension CareCostEstimate: FetchableRecord, PersistableRecord {
    static let databaseTableName = "careCostEstimates"
}
