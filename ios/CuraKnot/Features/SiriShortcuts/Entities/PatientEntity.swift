import AppIntents
import Foundation

// MARK: - Patient Entity

/// AppEntity representing a patient for Siri disambiguation
struct PatientEntity: AppEntity {
    // MARK: - Properties

    let id: String
    let displayName: String
    let circleId: String
    let initials: String

    // MARK: - AppEntity Requirements

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: "Patient",
            numericFormat: "\(placeholder: .int) patients"
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(displayName)",
            subtitle: initials.isEmpty ? nil : LocalizedStringResource(stringLiteral: initials),
            image: .init(systemName: "person.fill")
        )
    }

    static var defaultQuery = PatientEntityQuery()

    // MARK: - Initialization from Patient

    init(id: String, displayName: String, circleId: String, initials: String) {
        self.id = id
        self.displayName = displayName
        self.circleId = circleId
        self.initials = initials
    }

    init(from patient: Patient) {
        self.id = patient.id
        self.displayName = patient.displayName
        self.circleId = patient.circleId
        self.initials = patient.displayInitials
    }
}

// MARK: - Identifiable

extension PatientEntity: Identifiable {}

// MARK: - Equatable

extension PatientEntity: Equatable {
    static func == (lhs: PatientEntity, rhs: PatientEntity) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable

extension PatientEntity: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
