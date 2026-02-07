import Foundation
import GRDB

// MARK: - Patient Alias Model

/// Represents an alias (nickname) for a patient used in voice recognition.
/// Examples: "Mom" -> Margaret Johnson, "Grandma" -> Rose Smith
struct PatientAlias: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let patientId: String
    let circleId: String
    var alias: String
    let createdBy: String
    let createdAt: Date

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        patientId: String,
        circleId: String,
        alias: String,
        createdBy: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.patientId = patientId
        self.circleId = circleId
        self.alias = alias
        self.createdBy = createdBy
        self.createdAt = createdAt
    }

    // MARK: - Computed Properties

    /// Returns the alias in lowercase for case-insensitive comparison
    var normalizedAlias: String {
        alias.lowercased().trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - GRDB Conformance

extension PatientAlias: FetchableRecord, PersistableRecord {
    static let databaseTableName = "patientAliases"

    // MARK: - Relationships

    static let patient = belongsTo(Patient.self)

    var patient: QueryInterfaceRequest<Patient> {
        request(for: PatientAlias.patient)
    }
}

// MARK: - Patient Extension for Aliases

extension Patient {
    static let aliases = hasMany(PatientAlias.self)

    var aliases: QueryInterfaceRequest<PatientAlias> {
        request(for: Patient.aliases)
    }
}

// MARK: - Alias Match Result

/// Result from patient alias resolution with confidence scoring
struct PatientAliasMatch: Equatable {
    let patient: Patient
    let matchType: MatchType
    let confidence: Double

    enum MatchType: String {
        case aliasExact = "ALIAS_EXACT"
        case nameExact = "NAME_EXACT"
        case firstName = "FIRST_NAME"
        case aliasPrefix = "ALIAS_PREFIX"
        case contains = "CONTAINS"

        var displayName: String {
            switch self {
            case .aliasExact: return "Exact alias match"
            case .nameExact: return "Exact name match"
            case .firstName: return "First name match"
            case .aliasPrefix: return "Alias prefix match"
            case .contains: return "Name contains query"
            }
        }
    }
}

// MARK: - Common Aliases

/// Predefined common aliases that users frequently use
enum CommonAliasCategory: CaseIterable {
    case maternal
    case paternal
    case spouse
    case sibling
    case child
    case other

    var suggestions: [String] {
        switch self {
        case .maternal:
            return ["Mom", "Mother", "Mama", "Ma", "Mommy"]
        case .paternal:
            return ["Dad", "Father", "Papa", "Pa", "Daddy", "Pop"]
        case .spouse:
            return ["Wife", "Husband", "Spouse", "Partner"]
        case .sibling:
            return ["Brother", "Sister", "Bro", "Sis"]
        case .child:
            return ["Son", "Daughter", "Kid"]
        case .other:
            return ["Grandma", "Grandpa", "Nana", "Nanna", "Granny", "Grampa", "Gramps", "Auntie", "Uncle"]
        }
    }

    static var allSuggestions: [String] {
        allCases.flatMap { $0.suggestions }
    }
}
