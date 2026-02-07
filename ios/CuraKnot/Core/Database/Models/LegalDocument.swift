import Foundation
import GRDB

// MARK: - Legal Document Type

enum LegalDocumentType: String, Codable, CaseIterable {
    case powerOfAttorney = "POA"
    case healthcareProxy = "HEALTHCARE_PROXY"
    case advanceDirective = "ADVANCE_DIRECTIVE"
    case hipaaAuthorization = "HIPAA_AUTH"
    case doNotResuscitate = "DNR"
    case polst = "POLST"
    case will = "WILL"
    case trust = "TRUST"
    case guardianship = "GUARDIANSHIP"
    case other = "OTHER"

    var displayName: String {
        switch self {
        case .powerOfAttorney: return "Power of Attorney"
        case .healthcareProxy: return "Healthcare Proxy"
        case .advanceDirective: return "Advance Directive / Living Will"
        case .hipaaAuthorization: return "HIPAA Authorization"
        case .doNotResuscitate: return "Do Not Resuscitate (DNR)"
        case .polst: return "POLST / MOLST"
        case .will: return "Will"
        case .trust: return "Trust"
        case .guardianship: return "Guardianship"
        case .other: return "Other Legal Document"
        }
    }

    var icon: String {
        switch self {
        case .powerOfAttorney: return "doc.text.fill"
        case .healthcareProxy: return "heart.text.square.fill"
        case .advanceDirective: return "list.bullet.clipboard.fill"
        case .hipaaAuthorization: return "lock.doc.fill"
        case .doNotResuscitate: return "exclamationmark.triangle.fill"
        case .polst: return "cross.case.fill"
        case .will: return "doc.richtext.fill"
        case .trust: return "building.columns.fill"
        case .guardianship: return "person.badge.shield.checkmark.fill"
        case .other: return "doc.fill"
        }
    }

    var category: LegalDocumentCategory {
        switch self {
        case .healthcareProxy, .advanceDirective, .hipaaAuthorization,
             .doNotResuscitate, .polst:
            return .healthcare
        case .powerOfAttorney, .guardianship:
            return .financial
        case .will, .trust:
            return .estate
        case .other:
            return .other
        }
    }

    /// Recommended days before expiration to send reminders
    var expirationReminderDays: Int? {
        switch self {
        case .powerOfAttorney: return 365
        case .hipaaAuthorization: return 365
        case .polst: return 365
        default: return nil
        }
    }
}

// MARK: - Legal Document Category

enum LegalDocumentCategory: String, Codable, CaseIterable {
    case healthcare
    case financial
    case estate
    case other

    var displayName: String {
        switch self {
        case .healthcare: return "Healthcare Decisions"
        case .financial: return "Financial & Legal"
        case .estate: return "Estate Planning"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .healthcare: return "heart.text.square"
        case .financial: return "banknote"
        case .estate: return "building.columns"
        case .other: return "doc"
        }
    }
}

// MARK: - Legal Document Status

enum LegalDocumentStatus: String, Codable {
    case active = "ACTIVE"
    case expired = "EXPIRED"
    case revoked = "REVOKED"
    case superseded = "SUPERSEDED"

    var displayName: String {
        switch self {
        case .active: return "Active"
        case .expired: return "Expired"
        case .revoked: return "Revoked"
        case .superseded: return "Superseded"
        }
    }
}

// MARK: - Legal Document Model

struct LegalDocument: Codable, Identifiable, Equatable {
    let id: String
    let circleId: String
    let patientId: String
    let createdBy: String

    var documentType: LegalDocumentType
    var title: String
    var description: String?

    // Storage
    var storageKey: String
    var fileType: String
    var fileSizeBytes: Int64
    var ocrText: String?

    // Dates
    var executionDate: Date?
    var expirationDate: Date?

    // Parties
    var principalName: String?
    var agentName: String?
    var alternateAgentName: String?

    // Verification
    var notarized: Bool
    var notarizedDate: Date?
    var witnessNames: [String]

    // Status
    var status: LegalDocumentStatus
    var supersededBy: String?

    // Emergency
    var includeInEmergency: Bool

    let createdAt: Date
    var updatedAt: Date

    // MARK: - Computed Properties

    var category: LegalDocumentCategory {
        documentType.category
    }

    var daysUntilExpiration: Int? {
        guard let expirationDate = expirationDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day
    }

    var isExpiringSoon: Bool {
        guard let days = daysUntilExpiration else { return false }
        return days >= 0 && days <= 90
    }

    var isExpired: Bool {
        status == .expired || (daysUntilExpiration.map { $0 < 0 } ?? false)
    }

    var isActive: Bool {
        status == .active && !isExpired
    }

    // witnessNames is stored directly as [String], matching the Postgres text[] column.
    // Supabase SDK serializes/deserializes Postgres arrays as JSON arrays automatically.
}

// MARK: - GRDB Conformance

extension LegalDocument: FetchableRecord, PersistableRecord {
    static let databaseTableName = "legal_documents"
}

// MARK: - Legal Document Access

struct LegalDocumentAccess: Codable, Identifiable, Equatable {
    let id: String
    let documentId: String
    let userId: String
    var canView: Bool
    var canShare: Bool
    var canEdit: Bool
    let grantedBy: String
    let grantedAt: Date
}

extension LegalDocumentAccess: FetchableRecord, PersistableRecord {
    static let databaseTableName = "legal_document_access"
}

// MARK: - Legal Document Share

struct LegalDocumentShare: Codable, Identifiable, Equatable {
    let id: String
    let documentId: String
    let sharedBy: String
    let shareToken: String
    var accessCode: String?
    let expiresAt: Date
    var maxViews: Int?
    var viewCount: Int
    var lastViewedAt: Date?
    let createdAt: Date
}

extension LegalDocumentShare: FetchableRecord, PersistableRecord {
    static let databaseTableName = "legal_document_shares"
}

// MARK: - Legal Document Audit Entry

struct LegalDocumentAuditEntry: Codable, Identifiable {
    let id: String
    let documentId: String
    let userId: String?
    let action: String
    let detailsJson: String?
    let ipAddress: String?
    let userAgent: String?
    let createdAt: Date
}

extension LegalDocumentAuditEntry: FetchableRecord, PersistableRecord {
    static let databaseTableName = "legal_document_audit"
}
