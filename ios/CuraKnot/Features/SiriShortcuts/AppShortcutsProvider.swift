import AppIntents

// MARK: - CuraKnot Shortcuts Provider

/// Defines all Siri Shortcuts available for CuraKnot.
/// These appear in the Shortcuts app and can be triggered via "Hey Siri".
struct CuraKnotShortcuts: AppShortcutsProvider {

    // MARK: - App Shortcuts

    static var appShortcuts: [AppShortcut] {
        // =====================================================================
        // FREE TIER SHORTCUTS
        // =====================================================================

        // Create Handoff - Basic voice capture
        // Note: String parameters cannot be interpolated in phrases - only AppEntity/AppEnum
        AppShortcut(
            intent: CreateHandoffIntent(),
            phrases: [
                "Log care update in \(.applicationName)",
                "Record a care update in \(.applicationName)",
                "Add care note in \(.applicationName)",
                "Save update in \(.applicationName)"
            ],
            shortTitle: "Log Care Update",
            systemImageName: "waveform"
        )

        // Query Next Task - What's my most urgent task
        AppShortcut(
            intent: QueryNextTaskIntent(),
            phrases: [
                "What's my next task in \(.applicationName)",
                "What do I need to do in \(.applicationName)",
                "Show my tasks in \(.applicationName)",
                "Next care task in \(.applicationName)"
            ],
            shortTitle: "Next Task",
            systemImageName: "checklist"
        )

        // =====================================================================
        // PLUS/FAMILY TIER SHORTCUTS
        // These work but show upgrade prompt for FREE tier
        // =====================================================================

        // Query Medications
        AppShortcut(
            intent: QueryMedicationIntent(),
            phrases: [
                "What medications in \(.applicationName)",
                "Check medications in \(.applicationName)",
                "List meds in \(.applicationName)",
                "Ask \(.applicationName) about medications"
            ],
            shortTitle: "Check Medications",
            systemImageName: "pill"
        )

        // Query Last Handoff
        AppShortcut(
            intent: QueryLastHandoffIntent(),
            phrases: [
                "What was the last update in \(.applicationName)",
                "Last care update in \(.applicationName)",
                "Recent handoff in \(.applicationName)",
                "Latest update in \(.applicationName)"
            ],
            shortTitle: "Last Update",
            systemImageName: "clock.arrow.circlepath"
        )

        // Query Patient Status
        AppShortcut(
            intent: QueryPatientStatusIntent(),
            phrases: [
                "How is patient doing in \(.applicationName)",
                "Patient status in \(.applicationName)",
                "Check on patient in \(.applicationName)",
                "Care summary in \(.applicationName)"
            ],
            shortTitle: "Patient Status",
            systemImageName: "person.fill.checkmark"
        )
    }

    // MARK: - Shortcut Tile Color

    static var shortcutTileColor: ShortcutTileColor {
        .teal
    }
}

// MARK: - App Intents Extension

/// Extension point for App Intents framework.
/// This ensures all intents are properly registered with the system.
@available(iOS 16.0, *)
extension CreateHandoffIntent: ForegroundContinuableIntent {}

@available(iOS 16.0, *)
extension QueryNextTaskIntent: ForegroundContinuableIntent {}

@available(iOS 16.0, *)
extension QueryMedicationIntent: ForegroundContinuableIntent {}

@available(iOS 16.0, *)
extension QueryLastHandoffIntent: ForegroundContinuableIntent {}

@available(iOS 16.0, *)
extension QueryPatientStatusIntent: ForegroundContinuableIntent {}
