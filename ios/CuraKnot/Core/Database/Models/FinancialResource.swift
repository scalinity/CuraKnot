import Foundation
import GRDB

// MARK: - Resource Type

enum ResourceType: String, Codable {
    case article = "ARTICLE"
    case calculator = "CALCULATOR"
    case directory = "DIRECTORY"
    case officialLink = "OFFICIAL_LINK"

    var displayName: String {
        switch self {
        case .article: return "Article"
        case .calculator: return "Calculator"
        case .directory: return "Directory"
        case .officialLink: return "Official Link"
        }
    }

    var systemImage: String {
        switch self {
        case .article: return "doc.text.fill"
        case .calculator: return "function"
        case .directory: return "list.bullet"
        case .officialLink: return "link"
        }
    }
}

// MARK: - Resource Category

enum ResourceCategory: String, Codable, CaseIterable {
    case medicare = "MEDICARE"
    case medicaid = "MEDICAID"
    case va = "VA"
    case tax = "TAX"
    case planning = "PLANNING"

    var displayName: String {
        switch self {
        case .medicare: return "Medicare"
        case .medicaid: return "Medicaid"
        case .va: return "Veterans Affairs"
        case .tax: return "Tax Deductions"
        case .planning: return "Financial Planning"
        }
    }

    var systemImage: String {
        switch self {
        case .medicare: return "cross.circle.fill"
        case .medicaid: return "heart.circle.fill"
        case .va: return "star.circle.fill"
        case .tax: return "doc.text.fill"
        case .planning: return "chart.line.uptrend.xyaxis"
        }
    }
}

// MARK: - Financial Resource Model (Read-Only)

/// Educational and reference resources for care financing.
/// Read-only -- data is fetched from the backend and cached locally.
struct FinancialResource: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var title: String
    var resourceDescription: String
    var url: String?
    var resourceType: ResourceType
    var category: ResourceCategory
    var contentMarkdown: String?
    var states: [String]?
    var isFeatured: Bool
    var isActive: Bool
    let createdAt: Date
    var updatedAt: Date

    // Map 'resourceDescription' to the 'description' column in both
    // Supabase (via JSONDecoder .convertFromSnakeCase) and GRDB (via FetchableRecord).
    enum CodingKeys: String, CodingKey {
        case id, title, url, category
        case resourceDescription = "description"
        case resourceType
        case contentMarkdown
        case states
        case isFeatured
        case isActive
        case createdAt, updatedAt
    }

    // MARK: - Computed Properties

    var resourceURL: URL? {
        url.flatMap { URL(string: $0) }
    }

    var isStateSpecific: Bool {
        guard let states = states else { return false }
        return !states.isEmpty
    }
}

// MARK: - GRDB Conformance

extension FinancialResource: FetchableRecord, PersistableRecord {
    static let databaseTableName = "financialResources"
}
