import AppIntents
import SwiftUI
import os.log

// MARK: - Logger
private let logger = Logger(subsystem: "com.curaknot.app", category: "SiriShortcuts")

// MARK: - Query Patient Status Intent

/// Intent for getting an aggregated status overview for a patient.
/// PLUS/FAMILY tier only.
struct QueryPatientStatusIntent: AppIntent {

    // MARK: - Intent Metadata

    static var title: LocalizedStringResource = "How is Patient Doing"

    static var description = IntentDescription(
        "Get a quick status overview for a patient, including recent activity and pending items.",
        categoryName: "Patients",
        searchKeywords: ["status", "how", "doing", "patient", "overview"]
    )

    static var openAppWhenRun: Bool = false

    // MARK: - Parameters

    @Parameter(
        title: "Patient",
        description: "Who to check on",
        default: nil,
        requestValueDialog: IntentDialog("Who would you like to check on?")
    )
    var patient: PatientEntity?

    // MARK: - Parameter Summary

    static var parameterSummary: some ParameterSummary {
        When(\.$patient, .hasAnyValue) {
            Summary("How is \(\.$patient) doing")
        } otherwise: {
            Summary("How is patient doing")
        }
    }

    // MARK: - Perform

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let service = SiriShortcutsService.shared

        // Check tier gating - this is a PLUS+ feature
        guard service.hasFeatureAccess(.advancedSiri) else {
            return .result(
                dialog: "Checking patient status with Siri requires CuraKnot Plus.",
                view: StatusUpgradeView()
            )
        }

        // Validate context
        guard service.currentUserId != nil else {
            return .result(
                dialog: "Please open CuraKnot and sign in first.",
                view: StatusErrorView(message: "Sign in required")
            )
        }

        guard service.currentCircleId != nil else {
            return .result(
                dialog: "Please select a care circle in CuraKnot first.",
                view: StatusErrorView(message: "No care circle")
            )
        }

        // Resolve patient
        let targetPatientId: String

        if let patient = patient {
            targetPatientId = patient.id
        } else {
            // Try to get default patient
            do {
                if let defaultPatient = try service.getDefaultPatient() {
                    targetPatientId = defaultPatient.id
                } else {
                    return .result(
                        dialog: "Please specify which patient you want to check.",
                        view: StatusErrorView(message: "No patient specified")
                    )
                }
            } catch {
                return .result(
                    dialog: "I couldn't determine the patient. Please try again.",
                    view: StatusErrorView(message: "Patient lookup failed")
                )
            }
        }

        // Fetch patient status
        do {
            let status = try service.getPatientStatus(patientId: targetPatientId)
            
            // Apply privacy settings to spoken response
            let safePatientName = service.safePatientName(status.patientName)
            let dialog = buildStatusDialog(status, safePatientName: safePatientName, redactPHI: service.privacySettings.redactSpokenPHI)

            return .result(
                dialog: IntentDialog(stringLiteral: dialog),
                view: PatientStatusView(status: status, displayName: safePatientName)
            )

        } catch {
            logger.error("Failed to fetch patient status: \(error.localizedDescription)")
            return .result(
                dialog: "I couldn't fetch the status right now. Please try again.",
                view: StatusErrorView(message: "Fetch failed")
            )
        }
    }

    // MARK: - Helpers

    private func buildStatusDialog(_ status: PatientStatus, safePatientName: String, redactPHI: Bool = false) -> String {
        var parts: [String] = []
        
        if redactPHI {
            // Minimal info when PHI is redacted
            if status.overdueTaskCount > 0 {
                parts.append("\(safePatientName) has \(status.overdueTaskCount) overdue task\(status.overdueTaskCount == 1 ? "" : "s")")
            } else if status.pendingTaskCount > 0 {
                parts.append("\(safePatientName) has \(status.pendingTaskCount) pending task\(status.pendingTaskCount == 1 ? "" : "s")")
            } else {
                parts.append("\(safePatientName) has no pending tasks")
            }
            parts.append("Open the app for more details.")
            return parts.joined(separator: ". ")
        }

        // Full status with patient name
        if let lastDate = status.lastHandoffDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            parts.append("Last update for \(safePatientName) was \(formatter.localizedString(for: lastDate, relativeTo: Date()))")
        } else {
            parts.append("No recent updates for \(safePatientName)")
        }

        if status.overdueTaskCount > 0 {
            parts.append("\(status.overdueTaskCount) overdue task\(status.overdueTaskCount == 1 ? "" : "s")")
        } else if status.pendingTaskCount > 0 {
            parts.append("\(status.pendingTaskCount) pending task\(status.pendingTaskCount == 1 ? "" : "s")")
        }

        if status.activeMedicationCount > 0 {
            parts.append("\(status.activeMedicationCount) active medication\(status.activeMedicationCount == 1 ? "" : "s")")
        }

        return parts.joined(separator: ". ") + "."
    }
}

// MARK: - Status Views

struct PatientStatusView: View {
    let status: PatientStatus
    let displayName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "person.fill")
                    .foregroundStyle(.blue)
                Text(displayName)
                    .font(.headline)
            }

            // Stats grid
            HStack(spacing: 16) {
                // Last update
                StatusStatView(
                    icon: "clock",
                    value: status.lastHandoffDate != nil ? "Recent" : "None",
                    label: "Updates",
                    color: status.hasRecentActivity ? .green : .gray
                )

                // Tasks
                StatusStatView(
                    icon: "checklist",
                    value: "\(status.pendingTaskCount)",
                    label: "Pending",
                    color: status.overdueTaskCount > 0 ? .red : (status.pendingTaskCount > 0 ? .orange : .green)
                )

                // Medications
                StatusStatView(
                    icon: "pill.fill",
                    value: "\(status.activeMedicationCount)",
                    label: "Meds",
                    color: .blue
                )
            }

            // Alerts
            if status.overdueTaskCount > 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("\(status.overdueTaskCount) overdue task\(status.overdueTaskCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding()
    }
}

struct StatusStatView: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct StatusUpgradeView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
                .font(.title)
            Text("Plus Feature")
                .font(.headline)
            Text("Upgrade to check patient status with Siri")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct StatusErrorView: View {
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
