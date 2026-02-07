import AppIntents
import SwiftUI
import os.log

// MARK: - Logger
private let logger = Logger(subsystem: "com.curaknot.app", category: "SiriShortcuts")

// MARK: - Query Last Handoff Intent

/// Intent for querying the most recent handoff.
/// PLUS/FAMILY tier only.
struct QueryLastHandoffIntent: AppIntent {

    // MARK: - Intent Metadata

    static var title: LocalizedStringResource = "Last Care Update"

    static var description = IntentDescription(
        "Find out about the most recent care update.",
        categoryName: "Handoffs",
        searchKeywords: ["handoff", "update", "last", "recent", "latest"]
    )

    static var openAppWhenRun: Bool = false

    // MARK: - Parameters

    @Parameter(
        title: "Patient",
        description: "Whose last update to check",
        default: nil,
        requestValueDialog: IntentDialog("Whose last update would you like to hear?")
    )
    var patient: PatientEntity?

    // MARK: - Parameter Summary

    static var parameterSummary: some ParameterSummary {
        When(\.$patient, .hasAnyValue) {
            Summary("Get last update for \(\.$patient)")
        } otherwise: {
            Summary("Get last care update")
        }
    }

    // MARK: - Perform

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let service = SiriShortcutsService.shared

        // Check tier gating - this is a PLUS+ feature
        guard service.hasFeatureAccess(.advancedSiri) else {
            return .result(
                dialog: "Checking handoff history with Siri requires CuraKnot Plus.",
                view: HandoffUpgradeView()
            )
        }

        // Validate context
        guard service.currentUserId != nil else {
            return .result(
                dialog: "Please open CuraKnot and sign in first.",
                view: HandoffErrorView(message: "Sign in required")
            )
        }

        guard service.currentCircleId != nil else {
            return .result(
                dialog: "Please select a care circle in CuraKnot first.",
                view: HandoffErrorView(message: "No care circle")
            )
        }

        // Resolve patient
        let targetPatientId: String?
        let patientName: String

        if let patient = patient {
            targetPatientId = patient.id
            patientName = patient.displayName
        } else {
            targetPatientId = nil
            patientName = "your care circle"
        }
        
        // Apply privacy settings
        let safePatientName = service.safePatientName(patientName)

        // Fetch last handoff
        do {
            guard let handoff = try service.getLastHandoff(patientId: targetPatientId) else {
                return .result(
                    dialog: "No recent handoffs found for \(safePatientName).",
                    view: NoHandoffsView(patientName: safePatientName)
                )
            }

            let summary = service.safeHandoffSummary(handoff.summary ?? "No summary available")
            let timeAgo = formatTimeAgo(handoff.createdAt)

            return .result(
                dialog: "The last update for \(safePatientName) was \(timeAgo): \(summary)",
                view: SiriHandoffDetailView(handoff: handoff)
            )

        } catch {
            logger.error("Failed to fetch last handoff: \(error.localizedDescription)")
            return .result(
                dialog: "I couldn't fetch the handoff history. Please try again.",
                view: HandoffErrorView(message: "Fetch failed")
            )
        }
    }

    // MARK: - Helpers

    private func formatTimeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func buildHandoffDialog(_ handoff: Handoff, patientName: String?) -> String {
        var parts: [String] = []

        // When
        if let publishedAt = handoff.publishedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let relativeDate = formatter.localizedString(for: publishedAt, relativeTo: Date())
            parts.append("The last update was \(relativeDate)")
        }

        // Type
        parts.append("It was a \(handoff.type.displayName.lowercased())")

        // Title
        parts.append("titled: \(handoff.title)")

        // Summary preview
        if let summary = handoff.summary, !summary.isEmpty {
            let preview = String(summary.prefix(100))
            if summary.count > 100 {
                parts.append("Summary: \(preview)...")
            } else {
                parts.append("Summary: \(preview)")
            }
        }

        return parts.joined(separator: ". ") + "."
    }
}

// MARK: - Views

@available(iOS 16.0, *)
struct SiriHandoffDetailView: View {
    let handoff: Handoff

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: handoff.type.icon)
                    .foregroundStyle(.blue)
                Text(handoff.title)
                    .font(.headline)
                    .lineLimit(2)
            }

            if let publishedAt = handoff.publishedAt {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text(publishedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let summary = handoff.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .lineLimit(3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

struct NoHandoffsView: View {
    let patientName: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .font(.title)
            Text("No updates yet")
                .font(.headline)
            if let name = patientName {
                Text("for \(name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

struct HandoffUpgradeView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
                .font(.title)
            Text("Plus Feature")
                .font(.headline)
            Text("Upgrade to check updates with Siri")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct HandoffErrorView: View {
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
