import AppIntents
import Foundation
import SwiftUI
import os.log

// MARK: - Logger
private let logger = Logger(subsystem: "com.curaknot.app", category: "SiriShortcuts")

// MARK: - Create Handoff Intent

/// Intent for creating a handoff via Siri voice input.
/// FREE tier: Works with default patient only.
/// PLUS/FAMILY tier: Supports patient selection.
struct CreateHandoffIntent: AppIntent {

    // MARK: - Intent Metadata

    static var title: LocalizedStringResource = "Log Care Update"

    static var description = IntentDescription(
        "Capture a care update via voice. The update will be saved as a draft for you to review.",
        categoryName: "Handoffs",
        searchKeywords: ["handoff", "care", "update", "log", "note", "record"]
    )

    static var openAppWhenRun: Bool = false

    // MARK: - Parameters

    @Parameter(
        title: "Message",
        description: "What you want to record about the care recipient",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var message: String

    @Parameter(
        title: "Patient",
        description: "Who this update is about",
        default: nil,
        requestValueDialog: IntentDialog("Who is this update about?")
    )
    var patient: PatientEntity?

    // MARK: - Parameter Summary

    static var parameterSummary: some ParameterSummary {
        When(\.$patient, .hasAnyValue) {
            Summary("Log '\(\.$message)' for \(\.$patient)")
        } otherwise: {
            Summary("Log '\(\.$message)'")
        }
    }

    // MARK: - Perform

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let service = SiriShortcutsService.shared

        // Validate we have required context
        guard service.currentUserId != nil else {
            return .result(
                dialog: "Please open CuraKnot and sign in first.",
                view: SiriErrorView(message: "Sign in required")
            )
        }

        guard service.currentCircleId != nil else {
            return .result(
                dialog: "Please open CuraKnot and select a care circle first.",
                view: SiriErrorView(message: "No care circle selected")
            )
        }

        // Resolve patient
        let patientResult: PatientSelectionResult
        do {
            // Check if user explicitly provided a patient (requires advanced Siri)
            if patient != nil {
                // User wants to specify patient - check tier
                if !service.hasFeatureAccess(.advancedSiri) {
                    return .result(
                        dialog: "Upgrade to CuraKnot Plus to select patients with Siri. I'll save this to your default patient instead.",
                        view: SiriUpgradePromptView(feature: "Patient selection")
                    )
                }
                guard let resolvedPatient = patient else {
                    return .result(
                        dialog: "I couldn't determine which patient this is for. Please try again.",
                        view: SiriErrorView(message: "Patient resolution failed")
                    )
                }
                patientResult = .success(resolvedPatient)
            } else {
                // No patient specified - use default
                patientResult = try service.resolvePatientForSiri(
                    patientName: nil,
                    requiresAdvancedSiri: false
                )
            }
        } catch {
            return .result(
                dialog: "I couldn't determine which patient this is for. Please try again.",
                view: SiriErrorView(message: "Patient resolution failed")
            )
        }

        // Handle patient result
        let targetPatient: PatientEntity
        switch patientResult {
        case .success(let patient):
            targetPatient = patient

        case .ambiguous(let matches):
            let names = matches.prefix(3).map { $0.displayName }.joined(separator: ", ")
            return .result(
                dialog: "Did you mean \(names)? Please be more specific.",
                view: SiriAmbiguousPatientView(patients: Array(matches.prefix(3)))
            )

        case .notFound:
            return .result(
                dialog: "I couldn't find that patient in your care circle.",
                view: SiriErrorView(message: "Patient not found")
            )

        case .needsUpgrade:
            // Use default patient for free tier
            do {
                if let defaultPatient = try service.getDefaultPatient() {
                    targetPatient = PatientEntity(from: defaultPatient)
                } else {
                    return .result(
                        dialog: "Please add a patient in CuraKnot first.",
                        view: SiriErrorView(message: "No patients found")
                    )
                }
            } catch {
                return .result(
                    dialog: "Please open CuraKnot and add a patient first.",
                    view: SiriErrorView(message: "Setup required")
                )
            }
        }

        // Create the Siri draft
        do {
            _ = try service.createSiriDraft(
                message: message,
                patientId: targetPatient.id,
                circleId: service.currentCircleId,
                type: .other
            )

            return .result(
                dialog: "Got it. I've saved a care update for \(targetPatient.displayName). Tap the notification to review and publish.",
                view: SiriDraftCreatedView(
                    patientName: targetPatient.displayName,
                    preview: String(message.prefix(100))
                )
            )
        } catch {
            logger.error("Failed to create Siri draft: \(error.localizedDescription)")
            return .result(
                dialog: "I couldn't save your update. Please try again or open CuraKnot directly.",
                view: SiriErrorView(message: "Save failed")
            )
        }
    }
}

// MARK: - Siri Views

struct SiriDraftCreatedView: View {
    let patientName: String
    let preview: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Draft Saved")
                    .font(.headline)
            }

            Text("For \(patientName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(preview)
                .font(.caption)
                .lineLimit(2)
        }
        .padding()
    }
}

struct SiriErrorView: View {
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

struct SiriUpgradePromptView: View {
    let feature: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
                .font(.title)
            Text("\(feature) requires Plus")
                .font(.subheadline)
        }
        .padding()
    }
}

struct SiriAmbiguousPatientView: View {
    let patients: [PatientEntity]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Multiple matches:")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(patients, id: \.id) { patient in
                Text(patient.displayName)
                    .font(.subheadline)
            }
        }
        .padding()
    }
}
