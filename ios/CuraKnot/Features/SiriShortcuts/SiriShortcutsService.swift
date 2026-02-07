import Foundation
import GRDB
import os
import os.log
import UserNotifications

// MARK: - Logger
private let logger = Logger(subsystem: "com.curaknot.app", category: "SiriShortcuts")

// MARK: - Match Confidence Thresholds

/// Confidence scores for patient name/alias matching in Siri resolution
private enum MatchConfidence {
    static let exactAlias: Double = 1.0
    static let exactName: Double = 0.95
    static let firstName: Double = 0.8
    static let aliasPrefix: Double = 0.7
    static let partialMatch: Double = 0.5
    static let highConfidenceThreshold: Double = 0.8
}

// MARK: - Service Constants

private enum SiriConstants {
    static let maxTitleLength = 80
    static let draftRetentionDays = 7
    static let summaryPreviewLength = 100
    static let notificationDelay: TimeInterval = 1.0
}

// MARK: - Siri Privacy Settings

/// User preferences for Siri privacy controls
struct SiriPrivacySettings: Codable, Equatable {
    /// When true, Siri will not speak medication names, doses, or health details aloud
    var redactSpokenPHI: Bool = false
    
    /// When true, Siri responses will use generic terms like "your care recipient" instead of patient names
    var redactPatientNames: Bool = false
    
    static let `default` = SiriPrivacySettings()
}

// MARK: - Siri Feature Types

enum SiriFeature: String {
    case basicSiri = "basic_siri"
    case advancedSiri = "advanced_siri"
}

// MARK: - Patient Status

struct PatientStatus: Equatable {
    let patientId: String
    let patientName: String
    let lastHandoffDate: Date?
    let lastHandoffSummary: String?
    let pendingTaskCount: Int
    let overdueTaskCount: Int
    let activeMedicationCount: Int

    var hasRecentActivity: Bool {
        guard let lastDate = lastHandoffDate else { return false }
        return Calendar.current.isDateInToday(lastDate) ||
               Calendar.current.isDateInYesterday(lastDate)
    }

    var statusSummary: String {
        var parts: [String] = []

        if let lastDate = lastHandoffDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            parts.append("Last update \(formatter.localizedString(for: lastDate, relativeTo: Date()))")
        } else {
            parts.append("No recent updates")
        }

        if overdueTaskCount > 0 {
            parts.append("\(overdueTaskCount) overdue task\(overdueTaskCount == 1 ? "" : "s")")
        } else if pendingTaskCount > 0 {
            parts.append("\(pendingTaskCount) pending task\(pendingTaskCount == 1 ? "" : "s")")
        }

        if activeMedicationCount > 0 {
            parts.append("\(activeMedicationCount) active medication\(activeMedicationCount == 1 ? "" : "s")")
        }

        return parts.joined(separator: ". ")
    }
}

// MARK: - Siri Shortcuts Service

/// Service providing business logic for Siri Shortcuts integration.
/// Handles patient resolution, draft creation, queries, and tier gating.
final class SiriShortcutsService {

    // MARK: - Singleton

    static let shared = SiriShortcutsService()

    // MARK: - Properties

    private var databaseManager: DatabaseManager?
    private var notificationManager: NotificationManager?

    // Thread safety lock for context access
    private let lock = NSLock()
    
    // User context - set when app is active (protected by lock)
    private var _currentUserId: String?
    private var _currentCircleId: String?
    private var _currentCirclePlan: Circle.Plan?
    private var _privacySettings: SiriPrivacySettings = .default
    
    var currentUserId: String? {
        get { lock.withLock { _currentUserId } }
        set { lock.withLock { _currentUserId = newValue } }
    }
    
    var currentCircleId: String? {
        get { lock.withLock { _currentCircleId } }
        set { lock.withLock { _currentCircleId = newValue } }
    }
    
    var currentCirclePlan: Circle.Plan? {
        get { lock.withLock { _currentCirclePlan } }
        set { lock.withLock { _currentCirclePlan = newValue } }
    }
    
    /// Privacy settings for Siri responses
    var privacySettings: SiriPrivacySettings {
        get { lock.withLock { _privacySettings } }
        set { lock.withLock { _privacySettings = newValue } }
    }

    // MARK: - Configuration

    func configure(
        databaseManager: DatabaseManager,
        notificationManager: NotificationManager
    ) {
        self.databaseManager = databaseManager
        self.notificationManager = notificationManager
        loadPrivacySettings()
    }

    func updateContext(userId: String?, circleId: String?, plan: Circle.Plan?) {
        lock.withLock {
            self._currentUserId = userId
            self._currentCircleId = circleId
            self._currentCirclePlan = plan
        }
    }
    
    // MARK: - Privacy Settings
    
    /// Load privacy settings from UserDefaults
    private func loadPrivacySettings() {
        if let data = UserDefaults.standard.data(forKey: "siri_privacy_settings"),
           let settings = try? JSONDecoder().decode(SiriPrivacySettings.self, from: data) {
            lock.withLock { _privacySettings = settings }
        }
    }
    
    /// Save privacy settings to UserDefaults
    func updatePrivacySettings(_ settings: SiriPrivacySettings) {
        lock.withLock { _privacySettings = settings }
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "siri_privacy_settings")
        }
    }
    
    // MARK: - Privacy Helpers
    
    /// Returns a privacy-safe patient name based on current settings
    func safePatientName(_ name: String) -> String {
        if privacySettings.redactPatientNames {
            return "your care recipient"
        }
        return name
    }
    
    /// Returns a privacy-safe medication description based on current settings
    func safeMedicationDetails(_ details: String) -> String {
        if privacySettings.redactSpokenPHI {
            return "(details hidden for privacy)"
        }
        return details
    }
    
    /// Returns a privacy-safe handoff summary based on current settings
    func safeHandoffSummary(_ summary: String) -> String {
        if privacySettings.redactSpokenPHI {
            return "Care update recorded. Open the app to view details."
        }
        return summary
    }
    
    // MARK: - SQL Safety Helpers
    
    /// Escapes SQL LIKE pattern wildcards for safe use in queries.
    /// This prevents user input from being interpreted as wildcards.
    /// - Parameter input: The raw user input string
    /// - Returns: String with %, _, and \ escaped for LIKE patterns
    private func escapeLikePattern(_ input: String) -> String {
        var escaped = input
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "%", with: "\\%")
        escaped = escaped.replacingOccurrences(of: "_", with: "\\_")
        return escaped
    }

    /// Validate that user context is set up for Siri operations
    func validateContext() -> SiriContextValidation {
        guard let userId = currentUserId else {
            return .missingUser
        }
        guard let circleId = currentCircleId else {
            return .missingCircle
        }
        return .valid(userId: userId, circleId: circleId)
    }

    // MARK: - Feature Access

    /// Check if the current user has access to a Siri feature based on their plan
    func hasFeatureAccess(_ feature: SiriFeature) -> Bool {
        guard let plan = currentCirclePlan else {
            // Default to FREE tier if we can't determine plan
            return feature == .basicSiri
        }

        switch feature {
        case .basicSiri:
            // All tiers have basic Siri
            return true
        case .advancedSiri:
            // Only PLUS and FAMILY have advanced Siri
            return plan == .plus || plan == .family
        }
    }

    // MARK: - Patient Resolution

    /// Resolve a patient by name or alias using fuzzy matching
    func resolvePatient(name: String, circleId: String? = nil) throws -> [PatientAliasMatch] {
        guard let db = databaseManager else {
            throw SiriShortcutsError.notConfigured
        }

        let targetCircleId = circleId ?? currentCircleId
        guard let circleId = targetCircleId else {
            throw SiriShortcutsError.noActiveCircle
        }

        let normalizedQuery = name.lowercased().trimmingCharacters(in: .whitespaces)
        
        // Early return for empty or whitespace-only queries
        guard !normalizedQuery.isEmpty else {
            return []
        }

        return try db.read { database in
            var matches: [PatientAliasMatch] = []

            // Get all patients in the circle
            let patients = try Patient
                .filter(Column("circleId") == circleId)
                .filter(Column("archivedAt") == nil)
                .fetchAll(database)

            // Get all aliases for the circle
            let aliases = try PatientAlias
                .filter(Column("circleId") == circleId)
                .fetchAll(database)

            // Build patient lookup
            let patientById = Dictionary(uniqueKeysWithValues: patients.map { ($0.id, $0) })

            // Check aliases first (higher priority for voice recognition)
            for alias in aliases {
                guard let patient = patientById[alias.patientId] else { continue }
                let normalizedAlias = alias.alias.lowercased().trimmingCharacters(in: .whitespaces)
                
                // Skip empty aliases
                guard !normalizedAlias.isEmpty else { continue }
                
                if normalizedAlias == normalizedQuery {
                    // Exact alias match
                    matches.append(PatientAliasMatch(
                        patient: patient,
                        matchType: .aliasExact,
                        confidence: MatchConfidence.exactAlias
                    ))
                } else if normalizedAlias.hasPrefix(normalizedQuery) {
                    // Alias starts with query
                    matches.append(PatientAliasMatch(
                        patient: patient,
                        matchType: .aliasPrefix,
                        confidence: MatchConfidence.aliasPrefix
                    ))
                }
            }

            // Check patient names
            for patient in patients {
                let normalizedName = patient.displayName.lowercased()
                let firstName = normalizedName.split(separator: " ").first.map(String.init) ?? ""

                if normalizedName == normalizedQuery {
                    matches.append(PatientAliasMatch(
                        patient: patient,
                        matchType: .nameExact,
                        confidence: MatchConfidence.exactName
                    ))
                } else if firstName == normalizedQuery {
                    matches.append(PatientAliasMatch(
                        patient: patient,
                        matchType: .firstName,
                        confidence: MatchConfidence.firstName
                    ))
                } else if normalizedName.contains(normalizedQuery) {
                    matches.append(PatientAliasMatch(
                        patient: patient,
                        matchType: .contains,
                        confidence: MatchConfidence.partialMatch
                    ))
                }
            }

            // Sort by confidence (highest first) and remove duplicates
            var seen = Set<String>()
            return matches
                .sorted { $0.confidence > $1.confidence }
                .filter { seen.insert($0.patient.id).inserted }
        }
    }

    /// Get all patients in the current circle
    func getAllPatients(circleId: String? = nil) throws -> [Patient] {
        guard let db = databaseManager else {
            throw SiriShortcutsError.notConfigured
        }

        let targetCircleId = circleId ?? currentCircleId
        guard let circleId = targetCircleId else {
            throw SiriShortcutsError.noActiveCircle
        }

        return try db.read { database in
            try Patient
                .filter(Column("circleId") == circleId)
                .filter(Column("archivedAt") == nil)
                .order(Column("displayName"))
                .fetchAll(database)
        }
    }

    /// Get patients by specific IDs (efficient lookup)
    func getPatientsByIds(_ ids: [String]) throws -> [Patient] {
        guard !ids.isEmpty else { return [] }
        
        guard let db = databaseManager else {
            throw SiriShortcutsError.notConfigured
        }

        guard let circleId = currentCircleId else {
            throw SiriShortcutsError.noActiveCircle
        }

        return try db.read { database in
            try Patient
                .filter(Column("circleId") == circleId)
                .filter(ids.contains(Column("id")))
                .filter(Column("archivedAt") == nil)
                .fetchAll(database)
        }
    }

    /// Get the user's default patient (first patient if only one, or configured default)
    func getDefaultPatient() throws -> Patient? {
        guard let db = databaseManager else {
            throw SiriShortcutsError.notConfigured
        }

        guard let circleId = currentCircleId else {
            throw SiriShortcutsError.noActiveCircle
        }

        return try db.read { database in
            // For now, return the first (and often only) patient
            // TODO: Read from user settings for configured default
            try Patient
                .filter(Column("circleId") == circleId)
                .filter(Column("archivedAt") == nil)
                .order(Column("createdAt"))
                .fetchOne(database)
        }
    }

    // MARK: - Handoff Operations

    /// Create a Siri draft handoff
    func createSiriDraft(
        message: String,
        patientId: String,
        circleId: String? = nil,
        type: Handoff.HandoffType = .other
    ) throws -> Handoff {
        guard let db = databaseManager else {
            throw SiriShortcutsError.notConfigured
        }

        guard let userId = currentUserId else {
            throw SiriShortcutsError.notAuthenticated
        }

        let targetCircleId = circleId ?? currentCircleId
        guard let circleId = targetCircleId else {
            throw SiriShortcutsError.noActiveCircle
        }

        let now = Date()
        let handoff = Handoff(
            id: UUID().uuidString,
            circleId: circleId,
            patientId: patientId,
            createdBy: userId,
            type: type,
            title: generateTitle(from: message),
            summary: message,
            keywordsJson: nil,
            status: .siriDraft,
            publishedAt: nil,
            currentRevision: 1,
            rawTranscript: nil,
            audioStorageKey: nil,
            confidenceJson: nil,
            source: .siri,
            siriRawText: message,
            createdAt: now,
            updatedAt: now,
            sourceLanguage: nil
        )

        try db.write { database in
            try handoff.save(database)
        }

        // Schedule notification for review (notification errors are logged internally)
        Task { @MainActor in
            await self.scheduleSiriDraftNotification(handoffId: handoff.id)
        }

        return handoff
    }

    /// Get the most recent handoff for a patient
    func getLastHandoff(patientId: String? = nil) throws -> Handoff? {
        guard let db = databaseManager else {
            throw SiriShortcutsError.notConfigured
        }

        guard let circleId = currentCircleId else {
            throw SiriShortcutsError.noActiveCircle
        }

        return try db.read { database in
            var query = Handoff
                .filter(Column("circleId") == circleId)
                .filter(Column("status") == Handoff.Status.published.rawValue)

            if let patientId = patientId {
                query = query.filter(Column("patientId") == patientId)
            }

            return try query
                .order(Column("publishedAt").desc)
                .fetchOne(database)
        }
    }

    /// Get pending Siri drafts for the current user
    func getPendingSiriDrafts() throws -> [Handoff] {
        guard let databaseManager = databaseManager else {
            throw SiriShortcutsError.notConfigured
        }
        
        guard let userId = currentUserId else {
            throw SiriShortcutsError.notAuthenticated
        }
        
        // Get drafts from last N days
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -SiriConstants.draftRetentionDays, to: Date()) ?? Date.distantPast

        return try databaseManager.read { database in
            try Handoff
                .filter(Column("createdBy") == userId)
                .filter(Column("status") == Handoff.Status.siriDraft.rawValue)
                .filter(Column("createdAt") > cutoffDate)
                .order(Column("createdAt").desc)
                .fetchAll(database)
        }
    }

    // MARK: - Task Operations

    /// Get the next (most urgent) task for the current user
    func getNextTask() throws -> CareTask? {
        guard let db = databaseManager else {
            throw SiriShortcutsError.notConfigured
        }

        guard let userId = currentUserId else {
            throw SiriShortcutsError.notAuthenticated
        }

        return try db.read { database in
            // Get open tasks assigned to user, ordered by due date then priority
            let priorityOrder = SQL("CASE priority WHEN 'HIGH' THEN 1 WHEN 'MED' THEN 2 WHEN 'LOW' THEN 3 END")
            return try CareTask
                .filter(Column("ownerUserId") == userId)
                .filter(Column("status") == CareTask.Status.open.rawValue)
                .order(Column("dueAt").ascNullsLast)
                .order(priorityOrder)
                .fetchOne(database)
        }
    }

    // MARK: - Medication Operations

    /// Get medications for a patient
    func getMedications(patientId: String? = nil, searchName: String? = nil) throws -> [BinderItem] {
        guard let db = databaseManager else {
            throw SiriShortcutsError.notConfigured
        }

        guard let circleId = currentCircleId else {
            throw SiriShortcutsError.noActiveCircle
        }

        return try db.read { database in
            var query = BinderItem
                .filter(Column("circleId") == circleId)
                .filter(Column("type") == BinderItem.ItemType.med.rawValue)
                .filter(Column("isActive") == true)

            if let patientId = patientId {
                query = query.filter(Column("patientId") == patientId)
            }

            // Push name filtering to SQL with case-insensitive LIKE
            // Escape wildcards in user input for defense-in-depth
            if let searchName = searchName, !searchName.isEmpty {
                let escapedSearch = escapeLikePattern(searchName)
                query = query.filter(Column("title").collating(.localizedCaseInsensitiveCompare).like("%\(escapedSearch)%"))
            }

            return try query
                .order(Column("title"))
                .fetchAll(database)
        }
    }

    // MARK: - Patient Status

    /// Get aggregated status for a patient
    func getPatientStatus(patientId: String) throws -> PatientStatus {
        guard let db = databaseManager else {
            throw SiriShortcutsError.notConfigured
        }

        guard let circleId = currentCircleId else {
            throw SiriShortcutsError.noActiveCircle
        }

        return try db.read { database in
            // Get patient
            guard let patient = try Patient.fetchOne(database, key: patientId) else {
                throw SiriShortcutsError.patientNotFound
            }

            // Get last handoff
            let lastHandoff = try Handoff
                .filter(Column("patientId") == patientId)
                .filter(Column("status") == Handoff.Status.published.rawValue)
                .order(Column("publishedAt").desc)
                .fetchOne(database)

            let now = Date()
            
            // Get pending task count (using SQL COUNT)
            let pendingTaskCount = try CareTask
                .filter(Column("circleId") == circleId)
                .filter(Column("patientId") == patientId)
                .filter(Column("status") == CareTask.Status.open.rawValue)
                .fetchCount(database)

            // Get overdue task count (using SQL COUNT with date filter)
            let overdueTaskCount = try CareTask
                .filter(Column("circleId") == circleId)
                .filter(Column("patientId") == patientId)
                .filter(Column("status") == CareTask.Status.open.rawValue)
                .filter(Column("dueAt") != nil)
                .filter(Column("dueAt") < now)
                .fetchCount(database)

            // Get active medications count
            let activeMedCount = try BinderItem
                .filter(Column("circleId") == circleId)
                .filter(Column("patientId") == patientId)
                .filter(Column("type") == BinderItem.ItemType.med.rawValue)
                .filter(Column("isActive") == true)
                .fetchCount(database)

            return PatientStatus(
                patientId: patientId,
                patientName: patient.displayName,
                lastHandoffDate: lastHandoff?.publishedAt,
                lastHandoffSummary: lastHandoff?.summary,
                pendingTaskCount: pendingTaskCount,
                overdueTaskCount: overdueTaskCount,
                activeMedicationCount: activeMedCount
            )
        }
    }

    // MARK: - Notifications

    /// Schedule a notification for a Siri draft
    @MainActor
    func scheduleSiriDraftNotification(handoffId: String) async {
        guard let notificationManager = notificationManager else {
            logger.warning("NotificationManager not configured, skipping Siri draft notification")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Siri Handoff Saved"
        content.body = "Tap to review and publish your care update."
        content.sound = .default
        content.categoryIdentifier = "SIRI_DRAFT"
        content.userInfo = ["handoffId": handoffId]

        // Show immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "siri-draft-\(handoffId)",
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("Scheduled Siri draft notification for handoff: \(handoffId)")
        } catch {
            logger.error("Failed to schedule Siri draft notification: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    /// Generate a title from the Siri raw text
    private func generateTitle(from message: String) -> String {
        let maxLength = SiriConstants.maxTitleLength

        // Try to get first sentence
        let sentences = message.split(separator: ".", omittingEmptySubsequences: true)
        if let first = sentences.first {
            let sentence = String(first).trimmingCharacters(in: .whitespaces)
            if sentence.count <= maxLength {
                return sentence
            }
        }

        // Truncate if too long
        if message.count <= maxLength {
            return message.trimmingCharacters(in: .whitespaces)
        }

        let truncated = String(message.prefix(maxLength - 3))
        // Try to break at word boundary
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        return truncated + "..."
    }
}

// MARK: - Errors

enum SiriShortcutsError: Error, LocalizedError {
    case notConfigured
    case notAuthenticated
    case noActiveCircle
    case patientNotFound
    case featureRequiresUpgrade

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Siri shortcuts service not configured"
        case .notAuthenticated:
            return "Please sign in to CuraKnot first"
        case .noActiveCircle:
            return "Please select a care circle in CuraKnot"
        case .patientNotFound:
            return "Patient not found"
        case .featureRequiresUpgrade:
            return "This feature requires CuraKnot Plus"
        }
    }
}

// MARK: - Context Validation

enum SiriContextValidation {
    case valid(userId: String, circleId: String)
    case missingUser
    case missingCircle
}

// MARK: - Patient Selection Result

/// Result type for patient selection in Siri intents
enum PatientSelectionResult {
    case success(PatientEntity)
    case ambiguous([PatientEntity])
    case notFound
    case needsUpgrade

    var patient: PatientEntity? {
        if case .success(let patient) = self {
            return patient
        }
        return nil
    }
}

// MARK: - Patient Resolution for Siri

extension SiriShortcutsService {

    /// Resolve a patient for Siri, handling ambiguity and tier gating
    func resolvePatientForSiri(
        patientName: String?,
        requiresAdvancedSiri: Bool = false
    ) throws -> PatientSelectionResult {

        // Check tier gating for patient selection
        if requiresAdvancedSiri && !hasFeatureAccess(.advancedSiri) {
            // For basic Siri, try to use default patient
            if let defaultPatient = try getDefaultPatient() {
                return .success(PatientEntity(from: defaultPatient))
            }
            return .needsUpgrade
        }

        // If no name provided, use default patient
        guard let name = patientName, !name.isEmpty else {
            if let defaultPatient = try getDefaultPatient() {
                return .success(PatientEntity(from: defaultPatient))
            }
            return .notFound
        }

        // Try to resolve by name
        let matches = try resolvePatient(name: name)

        if matches.isEmpty {
            return .notFound
        }

        if matches.count == 1 {
            return .success(PatientEntity(from: matches[0].patient))
        }

        // Multiple matches with same high confidence = ambiguous
        let highConfidence = matches.filter { $0.confidence >= MatchConfidence.highConfidenceThreshold }
        if highConfidence.count == 1 {
            return .success(PatientEntity(from: highConfidence[0].patient))
        }

        // Return all matches for disambiguation
        return .ambiguous(matches.map { PatientEntity(from: $0.patient) })
    }
}
