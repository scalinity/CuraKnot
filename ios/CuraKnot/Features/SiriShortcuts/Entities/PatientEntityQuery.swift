import AppIntents
import Foundation
import os.log

// MARK: - Logger
private let logger = Logger(subsystem: "com.curaknot.app", category: "SiriShortcuts")

// MARK: - Constants

private let highConfidenceThreshold: Double = 0.8

// MARK: - Patient Entity Query

/// Query for resolving patients from Siri voice input
struct PatientEntityQuery: EntityQuery {

    // MARK: - EntityQuery Requirements

    /// Fetch patients by their IDs
    func entities(for identifiers: [PatientEntity.ID]) async throws -> [PatientEntity] {
        let service = SiriShortcutsService.shared

        guard !identifiers.isEmpty else { return [] }

        do {
            let patients = try service.getPatientsByIds(identifiers)
            return patients.map { PatientEntity(from: $0) }
        } catch {
            logger.error("Failed to fetch patients by IDs: \(error.localizedDescription)")
            return []
        }
    }

    /// Suggest all patients in the current circle
    func suggestedEntities() async throws -> [PatientEntity] {
        let service = SiriShortcutsService.shared

        do {
            let patients = try service.getAllPatients()
            return patients.map { PatientEntity(from: $0) }
        } catch {
            logger.error("Failed to fetch suggested patients: \(error.localizedDescription)")
            return []
        }
    }

    /// Return the user's default patient (if configured or single patient)
    func defaultResult() async -> PatientEntity? {
        let service = SiriShortcutsService.shared

        do {
            if let defaultPatient = try service.getDefaultPatient() {
                return PatientEntity(from: defaultPatient)
            }
        } catch {
            logger.error("Failed to fetch default patient: \(error.localizedDescription)")
        }

        return nil
    }
}

// MARK: - String Query Support

extension PatientEntityQuery: EntityStringQuery {

    /// Resolve patient from spoken name or alias
    func entities(matching string: String) async throws -> [PatientEntity] {
        let service = SiriShortcutsService.shared

        // For very short strings, return all suggested entities
        guard string.count >= 2 else {
            return try await suggestedEntities()
        }

        do {
            let matches = try service.resolvePatient(name: string)

            // matches are already sorted by confidence in resolvePatient()
            return matches.map { PatientEntity(from: $0.patient) }
        } catch {
            logger.error("Failed to search patients: \(error.localizedDescription)")
            return []
        }
    }
}
