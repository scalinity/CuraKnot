import Foundation
import GRDB

/// Service for managing symptom pattern detection and tracking
@MainActor
final class SymptomPatternsService {
    private let supabaseClient: SupabaseClient
    private let databaseManager: DatabaseManager
    private let subscriptionManager: SubscriptionManager
    private let authManager: AuthManager

    /// Cache TTL in seconds (4 hours)
    private let cacheTTL: TimeInterval = 4 * 60 * 60

    init(
        supabaseClient: SupabaseClient,
        databaseManager: DatabaseManager,
        subscriptionManager: SubscriptionManager,
        authManager: AuthManager
    ) {
        self.supabaseClient = supabaseClient
        self.databaseManager = databaseManager
        self.subscriptionManager = subscriptionManager
        self.authManager = authManager
    }

    // MARK: - Feature Access

    /// Check if the current user has access to symptom patterns feature
    func hasAccess(circleId: UUID) async -> Bool {
        await subscriptionManager.hasFeature("symptom_patterns", circleId: circleId)
    }

    // MARK: - Patterns

    /// Fetch detected patterns for a patient
    func fetchPatterns(
        patientId: UUID,
        forceRefresh: Bool = false
    ) async throws -> [DetectedPattern] {
        // Check cache first
        if !forceRefresh {
            let cached = try await fetchCachedPatterns(patientId: patientId)
            if !cached.isEmpty && isCacheValid(cached) {
                return cached
            }
        }

        // Fetch from Supabase
        let patterns: [DetectedPattern] = try await supabaseClient
            .from("detected_patterns")
            .select()
            .eq("patient_id", patientId.uuidString)
            .in("status", values: ["ACTIVE", "TRACKING"])
            .order("last_mention_at", ascending: false)
            .execute()

        // Update cache
        try await cachePatterns(patterns)

        return patterns
    }

    /// Dismiss a pattern (user acknowledges it)
    func dismissPattern(_ patternId: UUID) async throws {
        guard let userId = authManager.currentUserId else {
            throw SymptomPatternsError.notAuthenticated
        }

        try await supabaseClient
            .from("detected_patterns")
            .update([
                "status": "DISMISSED",
                "dismissed_by": userId.uuidString,
                "dismissed_at": ISO8601DateFormatter().string(from: Date())
            ])
            .eq("id", patternId.uuidString)
            .execute()

        // Update local cache (with error logging, don't block dismiss on cache failure)
        do {
            try await databaseManager.write { db in
                try db.execute(
                    sql: "UPDATE detected_patterns_cache SET status = 'DISMISSED' WHERE id = ?",
                    arguments: [patternId.uuidString]
                )
            }
        } catch {
            // Log but don't throw - cache will refresh naturally on next fetch
            #if DEBUG
            print("Failed to update local cache after dismissing pattern \(patternId): \(error)")
            #endif
        }
    }

    /// Start tracking a pattern
    func trackPattern(
        _ patternId: UUID,
        circleId: UUID,
        patientId: UUID
    ) async throws -> TrackedConcern {
        guard let userId = authManager.currentUserId else {
            throw SymptomPatternsError.notAuthenticated
        }

        // CORRECTNESS: Check if tracked concern already exists for this pattern
        let existingConcerns: [TrackedConcern] = try await supabaseClient
            .from("tracked_concerns")
            .select()
            .eq("pattern_id", patternId.uuidString)
            .eq("status", "ACTIVE")
            .limit(1)
            .execute()

        if let existing = existingConcerns.first {
            // Already tracking this pattern - return existing concern
            return existing
        }

        // Get pattern details FIRST (before any mutations)
        let patterns: [DetectedPattern] = try await supabaseClient
            .from("detected_patterns")
            .select()
            .eq("id", patternId.uuidString)
            .limit(1)
            .execute()

        guard let pattern = patterns.first else {
            throw SymptomPatternsError.networkError("Pattern not found")
        }

        // Create tracked concern BEFORE updating pattern status
        // This ensures we don't leave pattern in TRACKING state without a concern
        let concernInput: [String: Any] = [
            "circle_id": circleId.uuidString,
            "patient_id": patientId.uuidString,
            "pattern_id": patternId.uuidString,
            "created_by": userId.uuidString,
            "concern_name": pattern.displayName,
            "concern_category": pattern.concernCategory.rawValue,
            "tracking_prompt": "How was \(pattern.displayName.lowercased()) today?",
            "status": "ACTIVE"
        ]

        try await supabaseClient
            .from("tracked_concerns")
            .insert(concernInput)
            .execute()

        // Fetch the created concern to verify success
        let concerns: [TrackedConcern] = try await supabaseClient
            .from("tracked_concerns")
            .select()
            .eq("pattern_id", patternId.uuidString)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()

        guard let created = concerns.first else {
            throw SymptomPatternsError.networkError("Failed to create tracked concern")
        }

        // CORRECTNESS: Only update pattern status AFTER concern is successfully created
        // This prevents inconsistent state where pattern is TRACKING but no concern exists
        try await supabaseClient
            .from("detected_patterns")
            .update(["status": "TRACKING"])
            .eq("id", patternId.uuidString)
            .execute()

        return created
    }

    // MARK: - Tracked Concerns

    /// Fetch tracked concerns for a patient
    func fetchTrackedConcerns(patientId: UUID) async throws -> [TrackedConcern] {
        let concerns: [TrackedConcern] = try await supabaseClient
            .from("tracked_concerns")
            .select()
            .eq("patient_id", patientId.uuidString)
            .eq("status", "ACTIVE")
            .order("created_at", ascending: false)
            .execute()

        return concerns
    }

    /// Resolve a tracked concern
    func resolveConcern(_ concernId: UUID) async throws {
        try await supabaseClient
            .from("tracked_concerns")
            .update(["status": "RESOLVED", "updated_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", concernId.uuidString)
            .execute()
    }

    // MARK: - Tracking Entries

    /// Add a daily tracking entry
    func addTrackingEntry(
        concernId: UUID,
        rating: Int?,
        notes: String?
    ) async throws -> TrackingEntry {
        guard let userId = authManager.currentUserId else {
            throw SymptomPatternsError.notAuthenticated
        }

        let entry: [String: Any?] = [
            "concern_id": concernId.uuidString,
            "recorded_by": userId.uuidString,
            "rating": rating,
            "notes": notes,
            "recorded_at": ISO8601DateFormatter().string(from: Date())
        ]

        try await supabaseClient
            .from("tracking_entries")
            .insert(entry.compactMapValues { $0 })
            .execute()

        // Fetch the created entry
        let entries: [TrackingEntry] = try await supabaseClient
            .from("tracking_entries")
            .select()
            .eq("concern_id", concernId.uuidString)
            .order("recorded_at", ascending: false)
            .limit(1)
            .execute()

        guard let created = entries.first else {
            throw SymptomPatternsError.networkError("Failed to create tracking entry")
        }

        return created
    }

    /// Fetch tracking entries for a concern
    func fetchTrackingEntries(concernId: UUID, limit: Int = 30) async throws -> [TrackingEntry] {
        let entries: [TrackingEntry] = try await supabaseClient
            .from("tracking_entries")
            .select()
            .eq("concern_id", concernId.uuidString)
            .order("recorded_at", ascending: false)
            .limit(limit)
            .execute()

        return entries
    }

    // MARK: - Pattern Mentions

    /// Fetch mentions for a pattern
    func fetchMentions(patternId: UUID) async throws -> [PatternMention] {
        let mentions: [PatternMention] = try await supabaseClient
            .from("pattern_mentions")
            .select()
            .eq("pattern_id", patternId.uuidString)
            .order("mentioned_at", ascending: false)
            .execute()

        return mentions
    }

    // MARK: - Appointment Questions Integration

    /// Add pattern to appointment questions
    func addToAppointmentQuestions(
        pattern: DetectedPattern,
        appointmentPackId: UUID?
    ) async throws {
        guard let userId = authManager.currentUserId else {
            throw SymptomPatternsError.notAuthenticated
        }

        let questionText = generateQuestionText(for: pattern)
        let reasoning = "Generated from pattern insight: \(pattern.summaryText)"

        var question: [String: Any] = [
            "circle_id": pattern.circleId.uuidString,
            "patient_id": pattern.patientId.uuidString,
            "question_text": questionText,
            "reasoning": reasoning,
            "category": questionCategory(for: pattern),
            "source": "AI_GENERATED",
            "source_handoff_ids": pattern.sourceHandoffIds.map { $0.uuidString },
            "source_pattern_id": pattern.id.uuidString,
            "created_by": userId.uuidString,
            "priority": priority(for: pattern),
            "status": "PENDING",
            "sort_order": 0
        ]

        if let packId = appointmentPackId {
            question["appointment_pack_id"] = packId.uuidString
        }

        try await supabaseClient
            .from("appointment_questions")
            .insert(question)
            .execute()
    }

    // MARK: - Pattern Feedback

    /// Submit feedback on pattern quality
    func submitFeedback(
        patternId: UUID,
        feedbackType: PatternFeedbackType,
        feedbackText: String?
    ) async throws {
        guard let userId = authManager.currentUserId else {
            throw SymptomPatternsError.notAuthenticated
        }

        var feedback: [String: Any] = [
            "pattern_id": patternId.uuidString,
            "user_id": userId.uuidString,
            "feedback_type": feedbackType.rawValue
        ]

        if let text = feedbackText {
            feedback["feedback_text"] = text
        }

        try await supabaseClient
            .from("pattern_feedback")
            .upsert(feedback)
            .execute()
    }

    // MARK: - Manual Analysis Trigger

    /// Trigger pattern analysis for a patient (manual refresh)
    func triggerAnalysis(patientId: UUID) async throws {
        struct TriggerRequest: Encodable {
            let patientId: String
        }

        try await supabaseClient
            .functions("analyze-handoff-patterns")
            .invoke(body: TriggerRequest(patientId: patientId.uuidString))
    }

    // MARK: - Private Helpers

    private func fetchCachedPatterns(patientId: UUID) async throws -> [DetectedPattern] {
        try await databaseManager.read { db in
            try DetectedPattern
                .filter(Column("patient_id") == patientId.uuidString)
                .filter(Column("status") != "DISMISSED")
                .order(Column("last_mention_at").desc)
                .fetchAll(db)
        }
    }

    private func isCacheValid(_ patterns: [DetectedPattern]) -> Bool {
        guard !patterns.isEmpty else { return false }

        // Cache is valid only if ALL patterns are within TTL
        let now = Date()
        return patterns.allSatisfy { pattern in
            now.timeIntervalSince(pattern.updatedAt) < cacheTTL
        }
    }

    private func cachePatterns(_ patterns: [DetectedPattern]) async throws {
        try await databaseManager.write { db in
            for pattern in patterns {
                try pattern.save(db)
            }
        }
    }

    private func generateQuestionText(for pattern: DetectedPattern) -> String {
        switch pattern.patternType {
        case .frequency:
            return "You mentioned \(pattern.concernCategory.displayName.lowercased()) \(pattern.mentionCount) times recently. Could this be related to medications or a new condition?"
        case .correlation:
            if let event = pattern.primaryCorrelation {
                return "Could \(pattern.concernCategory.displayName.lowercased()) be related to \(event.eventDescription.lowercased())?"
            }
            return "Could \(pattern.concernCategory.displayName.lowercased()) be related to recent changes?"
        case .trend:
            let direction = pattern.trend == .increasing ? "increasing" : "decreasing"
            return "\(pattern.concernCategory.displayName) mentions have been \(direction) recently. What might be causing this?"
        case .new:
            return "\(pattern.concernCategory.displayName) was mentioned for the first time recently. Is this something to monitor?"
        case .absence:
            return "\(pattern.concernCategory.displayName) hasn't been mentioned in a while. Has this resolved?"
        }
    }

    private func questionCategory(for pattern: DetectedPattern) -> String {
        if pattern.patternType == .correlation {
            return "MEDICATION"
        }
        return "SYMPTOM"
    }

    private func priority(for pattern: DetectedPattern) -> String {
        if pattern.patternType == .correlation || pattern.mentionCount >= 5 {
            return "HIGH"
        }
        if pattern.patternType == .new || pattern.trend == .increasing {
            return "MEDIUM"
        }
        return "LOW"
    }
}

// MARK: - Errors

enum SymptomPatternsError: LocalizedError {
    case notAuthenticated
    case networkError(String)
    case cacheError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to use this feature"
        case .networkError(let message):
            return "Network error: \(message)"
        case .cacheError(let message):
            return "Cache error: \(message)"
        }
    }
}
