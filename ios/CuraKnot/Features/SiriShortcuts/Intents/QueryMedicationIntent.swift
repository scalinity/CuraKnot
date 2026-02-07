import AppIntents
import SwiftUI
import os.log

// MARK: - Logger
private let logger = Logger(subsystem: "com.curaknot.app", category: "SiriShortcuts")

// MARK: - Query Medication Intent

/// Intent for querying medications for a patient.
/// PLUS/FAMILY tier only.
struct QueryMedicationIntent: AppIntent {

    // MARK: - Intent Metadata

    static var title: LocalizedStringResource = "Check Medications"

    static var description = IntentDescription(
        "Find out what medications a patient is taking.",
        categoryName: "Binder",
        searchKeywords: ["medication", "medicine", "drug", "pill", "prescription"]
    )

    static var openAppWhenRun: Bool = false

    // MARK: - Parameters

    @Parameter(
        title: "Patient",
        description: "Whose medications to check",
        default: nil,
        requestValueDialog: IntentDialog("Whose medications would you like to check?")
    )
    var patient: PatientEntity?

    @Parameter(
        title: "Medication Name",
        description: "Specific medication to look up (optional)"
    )
    var medicationName: String?

    // MARK: - Parameter Summary

    static var parameterSummary: some ParameterSummary {
        When(\.$patient, .hasAnyValue) {
            Summary("Check \(\.$patient)'s medications")
        } otherwise: {
            Summary("Check medications")
        }
    }

    // MARK: - Perform

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let service = SiriShortcutsService.shared

        // Check tier gating - this is a PLUS+ feature
        guard service.hasFeatureAccess(.advancedSiri) else {
            return .result(
                dialog: "Checking medications with Siri requires CuraKnot Plus. Upgrade to unlock this feature.",
                view: MedicationUpgradeView()
            )
        }

        // Validate context
        guard service.currentUserId != nil else {
            return .result(
                dialog: "Please open CuraKnot and sign in first.",
                view: MedicationErrorView(message: "Sign in required")
            )
        }

        guard service.currentCircleId != nil else {
            return .result(
                dialog: "Please select a care circle in CuraKnot first.",
                view: MedicationErrorView(message: "No care circle")
            )
        }

        // Resolve patient
        let targetPatientId: String?
        let patientName: String

        if let patient = patient {
            targetPatientId = patient.id
            patientName = patient.displayName
        } else {
            // Try to get default patient
            do {
                if let defaultPatient = try service.getDefaultPatient() {
                    targetPatientId = defaultPatient.id
                    patientName = defaultPatient.displayName
                } else {
                    return .result(
                        dialog: "Please specify which patient's medications you want to check.",
                        view: MedicationErrorView(message: "No patient specified")
                    )
                }
            } catch {
                return .result(
                    dialog: "I couldn't determine the patient. Please try again.",
                    view: MedicationErrorView(message: "Patient lookup failed")
                )
            }
        }
        
        // Apply privacy settings to patient name
        let safePatientName = service.safePatientName(patientName)

        // Fetch medications
        do {
            let medications = try service.getMedications(
                patientId: targetPatientId,
                searchName: medicationName
            )

            if medications.isEmpty {
                if let searchName = medicationName {
                    return .result(
                        dialog: "I couldn't find a medication called \(searchName) for \(safePatientName).",
                        view: NoMedicationsView(patientName: safePatientName)
                    )
                } else {
                    return .result(
                        dialog: "\(safePatientName) doesn't have any active medications recorded.",
                        view: NoMedicationsView(patientName: safePatientName)
                    )
                }
            }

            // If searching for specific medication
            if let _ = medicationName, medications.count == 1 {
                let med = medications[0]
                let details = parseMedicationDetails(med)
                let safeDetails = service.safeMedicationDetails(details)
                let safeMedName = service.privacySettings.redactSpokenPHI ? "the medication" : med.title
                return .result(
                    dialog: "\(safePatientName) takes \(safeMedName). \(safeDetails)",
                    view: SingleMedicationView(medication: med, patientName: safePatientName)
                )
            }

            // List medications - use privacy-safe dialog
            let dialog = buildMedicationListDialog(
                medications: medications,
                patientName: safePatientName,
                redactPHI: service.privacySettings.redactSpokenPHI
            )

            return .result(
                dialog: IntentDialog(stringLiteral: dialog),
                view: MedicationListView(medications: medications, patientName: safePatientName)
            )

        } catch {
            logger.error("Failed to fetch medications: \(error.localizedDescription)")
            return .result(
                dialog: "I couldn't fetch medications right now. Please try again.",
                view: MedicationErrorView(message: "Fetch failed")
            )
        }
    }

    // MARK: - Helpers

    private func parseMedicationDetails(_ med: BinderItem) -> String {
        guard let data = med.contentJson.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        
        var parts: [String] = []
        
        if let dose = json["dose"] as? String, !dose.isEmpty {
            parts.append(dose)
        }
        
        if let schedule = json["schedule"] as? String, !schedule.isEmpty {
            parts.append(schedule)
        }
        
        if let purpose = json["purpose"] as? String, !purpose.isEmpty {
            parts.append(purpose)
        }
        
        return parts.joined(separator: ", ")
    }

    private func buildMedicationListDialog(medications: [BinderItem], patientName: String, redactPHI: Bool = false) -> String {
        let count = medications.count
        
        if redactPHI {
            return "\(patientName) is taking \(count) medication\(count == 1 ? "" : "s"). Open the app to view details."
        }

        if count <= 3 {
            let names = medications.map { $0.title }.joined(separator: ", ")
            return "\(patientName) is taking \(count) medication\(count == 1 ? "" : "s"): \(names)."
        } else {
            let first3 = medications.prefix(3).map { $0.title }.joined(separator: ", ")
            return "\(patientName) is taking \(count) medications including \(first3), and \(count - 3) more."
        }
    }
}

// MARK: - Medication Views

struct MedicationListView: View {
    let medications: [BinderItem]
    let patientName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(patientName)'s Medications")
                .font(.headline)

            ForEach(medications.prefix(5), id: \.id) { med in
                HStack {
                    Image(systemName: "pill.fill")
                        .foregroundStyle(.blue)
                    Text(med.title)
                        .font(.subheadline)
                }
            }

            if medications.count > 5 {
                Text("+ \(medications.count - 5) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

struct SingleMedicationView: View {
    let medication: BinderItem
    let patientName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "pill.fill")
                    .foregroundStyle(.blue)
                Text(medication.title)
                    .font(.headline)
            }

            Text("For \(patientName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct NoMedicationsView: View {
    let patientName: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "pills")
                .foregroundStyle(.secondary)
                .font(.title)
            Text("No medications found")
                .font(.subheadline)
            Text("for \(patientName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct MedicationUpgradeView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
                .font(.title)
            Text("Plus Feature")
                .font(.headline)
            Text("Upgrade to check medications with Siri")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct MedicationErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title)
            Text(message)
                .font(.subheadline)
        }
        .padding()
    }
}
