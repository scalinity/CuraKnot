import Foundation
import CryptoKit
import GRDB
import os

// MARK: - Translation Service

actor TranslationService {
    // MARK: - Dependencies

    private let supabaseClient: SupabaseClient
    private let subscriptionManager: SubscriptionManager
    private let databaseManager: DatabaseManager

    // MARK: - Cache

    private var memoryCache: [String: CachedTranslation] = [:]
    private let maxCacheEntries = 200

    private struct CachedTranslation {
        let content: TranslatedContent
        let cachedAt: Date

        var isExpired: Bool {
            Date().timeIntervalSince(cachedAt) > 3600 // 1 hour
        }
    }

    // MARK: - Logger

    private static let logger = Logger(subsystem: "com.curaknot.app", category: "TranslationService")

    // MARK: - Init

    init(supabaseClient: SupabaseClient, subscriptionManager: SubscriptionManager, databaseManager: DatabaseManager) {
        self.supabaseClient = supabaseClient
        self.subscriptionManager = subscriptionManager
        self.databaseManager = databaseManager
    }

    // MARK: - Stable Cache Key

    /// Generate a stable cache key using SHA256 (hashValue is not stable across launches)
    private func stableCacheKey(text: String, source: String, target: String) -> String {
        let input = "\(source)\0\(target)\0\(text)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Translate Text

    /// Translate text from source to target language
    func translate(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String,
        circleId: String? = nil,
        contentType: ContentType = .handoff
    ) async throws -> TranslatedContent {
        // Same language - no translation needed
        if sourceLanguage == targetLanguage {
            return TranslatedContent(
                translatedText: text,
                confidenceScore: 1.0,
                medicalTermsFound: [],
                disclaimer: false
            )
        }

        // Check memory cache with stable key
        let cacheKey = stableCacheKey(text: text, source: sourceLanguage, target: targetLanguage)
        if let cached = memoryCache[cacheKey], !cached.isExpired {
            return cached.content
        }

        // Check local GRDB cache before hitting the network
        if let localCached = try? await fetchLocalCacheEntry(hash: cacheKey, source: sourceLanguage, target: targetLanguage) {
            let content = TranslatedContent(
                translatedText: localCached.translatedText,
                confidenceScore: localCached.confidenceScore ?? 0.9,
                medicalTermsFound: [],
                disclaimer: localCached.containsMedicalTerms
            )
            memoryCache[cacheKey] = CachedTranslation(content: content, cachedAt: Date())
            return content
        }

        // Call Edge Function
        let request = TranslateRequest(
            text: text,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            circleId: circleId,
            contentType: contentType.rawValue
        )
        let response: TranslatedContent = try await supabaseClient
            .functions("translate-content")
            .invoke(body: request)

        // Cache in memory
        evictCacheIfNeeded()
        memoryCache[cacheKey] = CachedTranslation(content: response, cachedAt: Date())

        // Persist to local GRDB cache (non-fatal, log errors)
        do {
            try await persistLocalCacheEntry(
                hash: cacheKey,
                source: sourceLanguage,
                target: targetLanguage,
                content: response
            )
        } catch {
            Self.logger.warning("Failed to persist translation cache: \(error.localizedDescription)")
        }

        return response
    }

    // MARK: - Translate Handoff

    /// Translate a full handoff to the target language
    func translateHandoff(
        _ handoff: Handoff,
        to targetLanguage: SupportedLanguage,
        circleId: String
    ) async throws -> TranslatedHandoff {
        let sourceLanguage = handoff.sourceLanguage ?? "en"

        // Translate title and summary in parallel
        async let titleResult = translate(
            text: handoff.title,
            from: sourceLanguage,
            to: targetLanguage.rawValue,
            circleId: circleId,
            contentType: .handoff
        )

        let summaryText = handoff.summary
        async let summaryResultOpt: TranslatedContent? = {
            guard let summary = summaryText, !summary.isEmpty else { return nil }
            return try await self.translate(
                text: summary,
                from: sourceLanguage,
                to: targetLanguage.rawValue,
                circleId: circleId,
                contentType: .handoff
            )
        }()

        let titleTranslation = try await titleResult
        let summaryTranslation = try await summaryResultOpt

        let now = Date()
        // Hash title + summary for staleness detection (not just title)
        let hashInput = handoff.title + "\0" + (handoff.summary ?? "")
        let sourceHash = stableCacheKey(text: hashInput, source: sourceLanguage, target: targetLanguage.rawValue)
        return TranslatedHandoff(
            id: UUID().uuidString,
            handoffId: handoff.id,
            targetLanguage: targetLanguage.rawValue,
            translatedTitle: titleTranslation.translatedText,
            translatedSummary: summaryTranslation?.translatedText,
            translatedContent: nil,
            translationEngine: "OPENAI",
            confidenceScore: titleTranslation.confidenceScore,
            sourceHash: sourceHash,
            isStale: false,
            createdAt: now,
            hasMedicalTerms: titleTranslation.disclaimer || (summaryTranslation?.disclaimer ?? false)
        )
    }

    // MARK: - Detect Language

    /// Detect the language of the given text
    func detectLanguage(text: String) async throws -> DetectedLanguage {
        let response: DetectedLanguage = try await supabaseClient
            .functions("detect-language")
            .invoke(body: DetectLanguageRequest(text: text))
        return response
    }

    // MARK: - Glossary

    /// Fetch glossary entries for a circle
    func fetchGlossary(circleId: String, sourceLanguage: String, targetLanguage: String) async throws -> [GlossaryEntry] {
        // Validate circleId as UUID to prevent PostgREST filter injection
        guard UUID(uuidString: circleId) != nil else {
            throw TranslationError.invalidInput("Invalid circle ID format")
        }
        let entries: [GlossaryEntry] = try await supabaseClient.from("translation_glossary")
            .select()
            .or("circle_id.eq.\(circleId),circle_id.is.null")
            .eq("source_language", sourceLanguage)
            .eq("target_language", targetLanguage)
            .order("created_at", ascending: false)
            .execute()
        return entries
    }

    /// Add a glossary entry
    func addGlossaryEntry(
        circleId: String,
        sourceLanguage: String,
        targetLanguage: String,
        sourceTerm: String,
        translatedTerm: String,
        context: String?,
        category: String?,
        userId: String
    ) async throws {
        let entry = NewGlossaryEntry(
            circleId: circleId,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            sourceTerm: sourceTerm,
            translatedTerm: translatedTerm,
            context: context,
            category: category,
            createdBy: userId
        )

        try await supabaseClient.from("translation_glossary")
            .insert(entry)
            .execute()
    }

    /// Delete a glossary entry
    func deleteGlossaryEntry(id: String) async throws {
        try await supabaseClient.from("translation_glossary")
            .eq("id", id)
            .delete()
    }

    // MARK: - Circle Member Languages

    /// Fetch circle members with their language preferences
    func fetchCircleMemberLanguages(circleId: String) async throws -> [CircleMemberLanguageRow] {
        guard UUID(uuidString: circleId) != nil else {
            throw TranslationError.invalidInput("Invalid circle ID format")
        }
        // Join circle_members with users to get display names and language prefs
        let rows: [CircleMemberLanguageRow] = try await supabaseClient.from("circle_members")
            .select("user_id, users(display_name, language_preferences_json)")
            .eq("circle_id", circleId)
            .eq("status", "ACTIVE")
            .execute()

        return rows
    }

    /// Parse a member row into a display name and preferred language code
    static func parseMemberLanguage(_ row: CircleMemberLanguageRow) -> (name: String, languageCode: String) {
        let name = row.users?.displayName ?? "Unknown"
        let langCode = row.users?.languagePreferencesJson?.preferredLanguage ?? "en"
        return (name, langCode)
    }

    // MARK: - User Preferences

    /// Get the current user's language preferences
    func getUserLanguagePreferences(userId: String) async throws -> LanguagePreferences {
        let results: [UserLanguageRow] = try await supabaseClient.from("users")
            .select("language_preferences_json")
            .eq("id", userId)
            .execute()

        guard let row = results.first,
              let prefs = row.languagePreferencesJson else {
            return LanguagePreferences()
        }

        return prefs
    }

    /// Update the current user's language preferences
    func updateUserLanguagePreferences(userId: String, preferences: LanguagePreferences) async throws {
        let encoded = try JSONEncoder.supabase.encode(preferences)
        let jsonString = String(data: encoded, encoding: .utf8) ?? "{}"
        try await supabaseClient.from("users")
            .update(["language_preferences_json": jsonString])
            .eq("id", userId)
            .execute()
    }

    // MARK: - Cache Management

    /// Clear the in-memory translation cache
    func clearCache() {
        memoryCache.removeAll()
    }

    /// Evict stale/oldest entries when cache is full
    private func evictCacheIfNeeded() {
        guard memoryCache.count >= maxCacheEntries else { return }
        // Evict expired entries first
        memoryCache = memoryCache.filter { !$0.value.isExpired }
        // If still too many, batch evict oldest 10% to avoid repeated single evictions
        if memoryCache.count >= maxCacheEntries {
            let evictCount = max(memoryCache.count / 10, 1)
            let sortedKeys = memoryCache.sorted { $0.value.cachedAt < $1.value.cachedAt }
                .prefix(evictCount)
                .map(\.key)
            for key in sortedKeys {
                memoryCache.removeValue(forKey: key)
            }
        }
    }

    /// Remove expired entries from the local GRDB cache. Call on app launch or periodically.
    func cleanExpiredLocalCache() async {
        do {
            try await databaseManager.write { db in
                try TranslationCacheEntry
                    .filter(Column("expiresAt") <= Date())
                    .deleteAll(db)
            }
        } catch {
            Self.logger.warning("Failed to clean expired local cache: \(error.localizedDescription)")
        }
    }

    // MARK: - Local GRDB Cache

    private func fetchLocalCacheEntry(hash: String, source: String, target: String) async throws -> TranslationCacheEntry? {
        try await databaseManager.read { db in
            try TranslationCacheEntry
                .filter(Column("sourceTextHash") == hash)
                .filter(Column("sourceLanguage") == source)
                .filter(Column("targetLanguage") == target)
                .filter(Column("expiresAt") > Date())
                .fetchOne(db)
        }
    }

    private func persistLocalCacheEntry(hash: String, source: String, target: String, content: TranslatedContent) async throws {
        let entry = TranslationCacheEntry(
            id: UUID().uuidString,
            sourceTextHash: hash,
            sourceLanguage: source,
            targetLanguage: target,
            translatedText: content.translatedText,
            confidenceScore: content.confidenceScore,
            containsMedicalTerms: content.disclaimer,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(30 * 24 * 3600)
        )
        try await databaseManager.write { db in
            try entry.save(db)
        }
    }

    // MARK: - Types

    enum ContentType: String {
        case handoff = "HANDOFF"
        case binder = "BINDER"
        case task = "TASK"
        case notification = "NOTIFICATION"
    }

    enum TranslationError: LocalizedError {
        case invalidInput(String)

        var errorDescription: String? {
            switch self {
            case .invalidInput(let message):
                return message
            }
        }
    }
}

// MARK: - Request Types

private struct TranslateRequest: Codable {
    let text: String
    let sourceLanguage: String
    let targetLanguage: String
    let circleId: String?
    let contentType: String
}

private struct DetectLanguageRequest: Codable {
    let text: String
}

private struct NewGlossaryEntry: Codable {
    let circleId: String
    let sourceLanguage: String
    let targetLanguage: String
    let sourceTerm: String
    let translatedTerm: String
    let context: String?
    let category: String?
    let createdBy: String
}

private struct UserLanguageRow: Codable {
    let languagePreferencesJson: LanguagePreferences?
}

// MARK: - Circle Member Language Row (public for view consumption)

struct CircleMemberLanguageRow: Codable {
    let userId: String
    let users: UserInfo?

    struct UserInfo: Codable {
        let displayName: String?
        let languagePreferencesJson: LanguagePreferences?
    }
}
