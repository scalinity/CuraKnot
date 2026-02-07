import Foundation
import GRDB

// MARK: - Wellness Service

/// Service for managing wellness check-ins, alerts, and preferences
/// Privacy: All wellness data is USER-PRIVATE (not shared with circle)
@MainActor
final class WellnessService: ObservableObject {

    // MARK: - Types

    enum WellnessError: LocalizedError {
        case notAuthenticated
        case subscriptionRequired
        case checkInNotFound
        case invalidInput(String)
        case networkError(Error)
        case databaseError(Error)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "Please sign in to access wellness features"
            case .subscriptionRequired:
                return "Wellness tracking requires a Plus or Family subscription. Upgrade in Settings."
            case .checkInNotFound:
                return "Check-in not found. It may have been deleted."
            case .invalidInput(let message):
                return message
            case .networkError:
                return "Connection issue. Check your internet and try again."
            case .databaseError:
                return "Something went wrong. Please restart the app or contact support."
            }
        }
    }

    struct ScoreResult: Codable {
        let success: Bool
        let wellnessScore: Int
        let behavioralScore: Int
        let totalScore: Int
        let riskLevel: String
    }

    struct DelegationCandidate: Codable, Identifiable {
        let userId: String
        let fullName: String
        let role: String
        let recentHandoffCount: Int
        let circleId: String
        let circleName: String

        var id: String { userId }
    }

    // MARK: - Properties

    private let supabaseClient: SupabaseClient
    private let databaseManager: DatabaseManager
    private let encryptionService = EncryptionService.shared

    @Published private(set) var currentCheckIn: WellnessCheckIn?
    @Published private(set) var activeAlerts: [WellnessAlert] = []
    @Published private(set) var preferences: WellnessPreferences?
    @Published private(set) var isLoading = false
    @Published private(set) var hasSubscription = false

    // Store current user ID (set from AuthManager.currentUser)
    private var currentUserId: String?

    // MARK: - Initialization

    init(supabaseClient: SupabaseClient, databaseManager: DatabaseManager) {
        self.supabaseClient = supabaseClient
        self.databaseManager = databaseManager
    }

    // MARK: - User ID Management

    func setCurrentUserId(_ userId: String?) {
        self.currentUserId = userId
    }

    private func getUserId() throws -> String {
        guard let userId = currentUserId else {
            throw WellnessError.notAuthenticated
        }
        return userId
    }

    // MARK: - Subscription Check

    func checkSubscriptionStatus() async throws {
        let userId = try getUserId()

        let response: Bool = try await supabaseClient.rpc(
            "has_feature_access",
            params: [
                "p_user_id": userId,
                "p_feature": "wellness_checkins"
            ]
        )

        hasSubscription = response
    }

    // MARK: - Check-In Operations

    /// Get current week's check-in (or nil if not submitted)
    func getCurrentWeekCheckIn() async throws -> WellnessCheckIn? {
        let userId = try getUserId()
        let weekStart = WellnessCheckIn.currentWeekStart()

        // Try local first
        if let local = try fetchLocalCheckIn(userId: userId, weekStart: weekStart) {
            currentCheckIn = local
            return local
        }

        // Fetch from remote
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let weekStartString = formatter.string(from: weekStart)

        let checkIns: [WellnessCheckIn] = try await supabaseClient
            .from("wellness_checkins")
            .select()
            .eq("user_id", userId)
            .eq("week_start", weekStartString)
            .execute()

        if let checkIn = checkIns.first {
            try saveLocalCheckIn(checkIn)
            currentCheckIn = checkIn
            return checkIn
        }

        return nil
    }

    /// Submit a new wellness check-in
    func submitCheckIn(
        stressLevel: Int,
        sleepQuality: Int,
        capacityLevel: Int,
        notes: String?
    ) async throws -> WellnessCheckIn {
        let userId = try getUserId()

        // Input validation
        guard (1...5).contains(stressLevel) else {
            throw WellnessError.invalidInput("Stress level must be between 1 and 5")
        }
        guard (1...5).contains(sleepQuality) else {
            throw WellnessError.invalidInput("Sleep quality must be between 1 and 5")
        }
        guard (1...4).contains(capacityLevel) else {
            throw WellnessError.invalidInput("Capacity level must be between 1 and 4")
        }

        if !hasSubscription {
            try await checkSubscriptionStatus()
            if !hasSubscription {
                throw WellnessError.subscriptionRequired
            }
        }

        isLoading = true
        defer { isLoading = false }

        // Encrypt notes if provided
        var encryptedNotes: String?
        var notesNonce: String?
        var notesTag: String?

        if let notes = notes, !notes.isEmpty {
            let encrypted = try encryptionService.encrypt(notes)
            encryptedNotes = encrypted.ciphertext
            notesNonce = encrypted.nonce
            notesTag = encrypted.tag
        }

        let weekStart = WellnessCheckIn.currentWeekStart()
        let checkIn = WellnessCheckIn(
            userId: userId,
            stressLevel: stressLevel,
            sleepQuality: sleepQuality,
            capacityLevel: capacityLevel,
            notesEncrypted: encryptedNotes,
            notesNonce: notesNonce,
            notesTag: notesTag,
            weekStart: weekStart
        )

        // Upsert to Supabase
        try await supabaseClient
            .from("wellness_checkins")
            .upsert(checkIn)
            .execute()

        // Calculate score via Edge Function
        let scoreResult = try await calculateScore(checkInId: checkIn.id)

        // Update local with scores
        var updatedCheckIn = checkIn
        updatedCheckIn.wellnessScore = scoreResult.wellnessScore
        updatedCheckIn.behavioralScore = scoreResult.behavioralScore
        updatedCheckIn.totalScore = scoreResult.totalScore

        try saveLocalCheckIn(updatedCheckIn)
        currentCheckIn = updatedCheckIn

        return updatedCheckIn
    }

    /// Skip this week's check-in
    func skipCheckIn() async throws {
        let userId = try getUserId()

        let weekStart = WellnessCheckIn.currentWeekStart()
        let checkIn = WellnessCheckIn(
            userId: userId,
            stressLevel: 3,  // Default neutral values
            sleepQuality: 3,
            capacityLevel: 2,
            weekStart: weekStart,
            skipped: true
        )

        try await supabaseClient
            .from("wellness_checkins")
            .upsert(checkIn)
            .execute()

        currentCheckIn = checkIn
    }

    /// Calculate wellness score via Edge Function
    private func calculateScore(checkInId: String) async throws -> ScoreResult {
        struct CheckInRequest: Encodable {
            let checkInId: String
        }

        let result: ScoreResult = try await supabaseClient
            .functions("calculate-wellness-score")
            .invoke(body: CheckInRequest(checkInId: checkInId))

        return result
    }

    // MARK: - Check-In History

    /// Get check-in history for the last N weeks
    func getCheckInHistory(weeks: Int = 12) async throws -> [WellnessCheckIn] {
        let userId = try getUserId()

        let startDate = Calendar.current.date(byAdding: .weekOfYear, value: -weeks, to: Date()) ?? Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        let checkIns: [WellnessCheckIn] = try await supabaseClient
            .from("wellness_checkins")
            .select()
            .eq("user_id", userId)
            .gt("week_start", formatter.string(from: startDate))
            .order("week_start", ascending: false)
            .execute()

        return checkIns
    }

    // MARK: - Alerts

    /// Fetch active wellness alerts
    func fetchActiveAlerts() async throws {
        let userId = try getUserId()

        let alerts: [WellnessAlert] = try await supabaseClient
            .from("wellness_alerts")
            .select()
            .eq("user_id", userId)
            .eq("status", "ACTIVE")
            .order("created_at", ascending: false)
            .execute()

        activeAlerts = alerts

        // Cache locally
        for alert in alerts {
            try saveLocalAlert(alert)
        }
    }

    /// Dismiss an alert
    func dismissAlert(_ alert: WellnessAlert) async throws {
        var updated = alert
        updated.status = .dismissed
        updated.dismissedAt = Date()
        updated.updatedAt = Date()

        try await supabaseClient
            .from("wellness_alerts")
            .eq("id", alert.id)
            .update(updated)
            .execute()

        activeAlerts.removeAll { $0.id == alert.id }
        try saveLocalAlert(updated)
    }

    // MARK: - Delegation Candidates

    /// Get delegation candidates from circle membership
    /// Privacy: Returns circle members, NOT based on wellness scores
    func getDelegationCandidates() async throws -> [DelegationCandidate] {
        struct DelegationResponse: Codable {
            let success: Bool
            let candidates: [DelegationCandidate]
            let sortedBy: String
        }

        let result: DelegationResponse = try await supabaseClient
            .functions("get-delegation-candidates")
            .invoke()

        return result.candidates
    }

    // MARK: - Preferences

    /// Fetch user's wellness preferences
    func fetchPreferences() async throws {
        let userId = try getUserId()

        let prefs: [WellnessPreferences] = try await supabaseClient
            .from("wellness_preferences")
            .select()
            .eq("user_id", userId)
            .limit(1)
            .execute()

        if let existing = prefs.first {
            preferences = existing
        } else {
            // Create default preferences
            let defaultPrefs = WellnessPreferences.defaultPreferences(for: userId)
            preferences = try await savePreferences(defaultPrefs)
        }
    }

    /// Update wellness preferences
    func updatePreferences(_ prefs: WellnessPreferences) async throws {
        var updated = prefs
        updated.updatedAt = Date()

        try await supabaseClient
            .from("wellness_preferences")
            .upsert(updated)
            .execute()

        preferences = updated
    }

    /// Toggle weekly reminders
    func toggleReminders(enabled: Bool) async throws {
        guard var prefs = preferences else {
            throw WellnessError.notAuthenticated
        }
        prefs.enableWeeklyReminders = enabled
        try await updatePreferences(prefs)
    }

    /// Toggle burnout alerts
    func toggleBurnoutAlerts(enabled: Bool) async throws {
        guard var prefs = preferences else {
            throw WellnessError.notAuthenticated
        }
        prefs.enableBurnoutAlerts = enabled
        try await updatePreferences(prefs)
    }

    private func savePreferences(_ prefs: WellnessPreferences) async throws -> WellnessPreferences {
        try await supabaseClient
            .from("wellness_preferences")
            .insert(prefs)
            .execute()

        return prefs
    }

    // MARK: - Notes Decryption

    /// Decrypt notes from a check-in
    func decryptNotes(from checkIn: WellnessCheckIn) throws -> String? {
        guard let ciphertext = checkIn.notesEncrypted,
              let nonce = checkIn.notesNonce,
              let tag = checkIn.notesTag else {
            return nil
        }

        return try encryptionService.decrypt(ciphertext: ciphertext, nonce: nonce, tag: tag)
    }

    // MARK: - Local Storage

    private func fetchLocalCheckIn(userId: String, weekStart: Date) throws -> WellnessCheckIn? {
        try databaseManager.read { db in
            try WellnessCheckIn
                .filter(WellnessCheckIn.Columns.userId == userId)
                .filter(WellnessCheckIn.Columns.weekStart == weekStart)
                .fetchOne(db)
        }
    }

    private func saveLocalCheckIn(_ checkIn: WellnessCheckIn) throws {
        try databaseManager.write { db in
            try checkIn.save(db)
        }
    }

    private func saveLocalAlert(_ alert: WellnessAlert) throws {
        try databaseManager.write { db in
            try alert.save(db)
        }
    }
}
