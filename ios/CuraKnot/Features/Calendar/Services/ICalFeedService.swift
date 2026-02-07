import Foundation
import GRDB

// MARK: - iCal Feed Service

/// Manages iCal feed tokens for read-only calendar subscriptions
@MainActor
final class ICalFeedService: ObservableObject {
    // MARK: - Dependencies

    private let databaseManager: DatabaseManager
    private let supabaseClient: SupabaseClient

    // MARK: - Published State

    @Published var feedTokens: [ICalFeedToken] = []
    @Published var isLoading: Bool = false

    // MARK: - Initialization

    init(databaseManager: DatabaseManager, supabaseClient: SupabaseClient) {
        self.databaseManager = databaseManager
        self.supabaseClient = supabaseClient
    }

    // MARK: - Feed Token Management

    /// Load feed tokens for a circle
    func loadTokens(circleId: String) async throws {
        isLoading = true
        defer { isLoading = false }

        // Fetch from server
        let tokens: [ICalFeedToken] = try await supabaseClient
            .from("ical_feed_tokens")
            .select()
            .eq("circle_id", circleId)
            .`is`("revoked_at", value: nil)
            .execute()

        // Update local database
        try databaseManager.write { db in
            for token in tokens {
                try token.save(db)
            }
        }

        feedTokens = tokens.filter { $0.isActive }
    }

    /// Create a new iCal feed token
    /// SECURITY: Rate limited to prevent token exhaustion attacks
    func createFeedToken(
        circleId: String,
        userId: String,
        feedName: String? = nil,
        includeTasks: Bool = true,
        includeShifts: Bool = true,
        includeAppointments: Bool = true,
        patientIds: [String]? = nil,
        showMinimalDetails: Bool = false,
        lookaheadDays: Int = 90,
        expiresAt: Date? = nil
    ) async throws -> ICalFeedToken {
        // SECURITY: Rate limit - max 10 active tokens per circle
        let existingCount = try databaseManager.read { db in
            try ICalFeedToken
                .filter(ICalFeedToken.Columns.circleId == circleId)
                .filter(ICalFeedToken.Columns.revokedAt == nil)
                .fetchCount(db)
        }

        guard existingCount < 10 else {
            throw FeedError.tooManyTokens
        }

        // SECURITY: Validate and sanitize feedName
        var sanitizedFeedName: String? = nil
        if let name = feedName {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines).joined()
                .components(separatedBy: .controlCharacters).joined()
            if !trimmed.isEmpty && trimmed.count <= 100 {
                sanitizedFeedName = trimmed
            }
        }

        // Validate lookaheadDays bounds (1-730 days to match database constraint)
        let validatedLookaheadDays = max(1, min(730, lookaheadDays))

        let token = ICalFeedToken(
            circleId: circleId,
            createdBy: userId,
            feedName: sanitizedFeedName,
            includeTasks: includeTasks,
            includeShifts: includeShifts,
            includeAppointments: includeAppointments,
            patientIds: patientIds,
            showMinimalDetails: showMinimalDetails,
            lookaheadDays: validatedLookaheadDays,
            expiresAt: expiresAt
        )

        // Save to server
        try await supabaseClient
            .from("ical_feed_tokens")
            .insert(token.toSupabasePayload())

        // Save locally
        try databaseManager.write { db in
            try token.save(db)
        }

        feedTokens.append(token)

        return token
    }

    /// Revoke a feed token
    func revokeToken(tokenId: String) async throws {
        // Update on server - use Encodable struct
        struct RevokePayload: Encodable {
            let revoked_at: String
        }
        try await supabaseClient
            .from("ical_feed_tokens")
            .eq("id", tokenId)
            .update(RevokePayload(revoked_at: Date().ISO8601Format()))

        // Update locally
        _ = try databaseManager.write { db in
            try ICalFeedToken
                .filter(ICalFeedToken.Columns.id == tokenId)
                .updateAll(db, [ICalFeedToken.Columns.revokedAt.set(to: Date())])
        }

        feedTokens.removeAll { $0.id == tokenId }
    }

    /// Regenerate a feed token (creates new token, revokes old one)
    func regenerateToken(oldTokenId: String, circleId: String, userId: String) async throws -> ICalFeedToken {
        // Get old token settings
        guard let oldToken = feedTokens.first(where: { $0.id == oldTokenId }) else {
            throw FeedError.tokenNotFound
        }

        // Create new token with same settings
        let newToken = try await createFeedToken(
            circleId: circleId,
            userId: userId,
            feedName: oldToken.feedName,
            includeTasks: oldToken.includeTasks,
            includeShifts: oldToken.includeShifts,
            includeAppointments: oldToken.includeAppointments,
            patientIds: oldToken.patientIds,
            showMinimalDetails: oldToken.showMinimalDetails,
            lookaheadDays: oldToken.lookaheadDays,
            expiresAt: oldToken.expiresAt
        )

        // Revoke old token
        try await revokeToken(tokenId: oldTokenId)

        return newToken
    }

    /// Update feed token settings
    func updateToken(_ token: ICalFeedToken) async throws {
        var updatedToken = token
        updatedToken.updatedAt = Date()

        // Update on server - use Encodable struct for proper typing
        struct TokenUpdate: Encodable {
            let feed_name: String?
            let include_tasks: Bool
            let include_shifts: Bool
            let include_appointments: Bool
            let include_handoff_followups: Bool
            let show_minimal_details: Bool
            let lookahead_days: Int
            let updated_at: String
        }

        let updatePayload = TokenUpdate(
            feed_name: token.feedName,
            include_tasks: token.includeTasks,
            include_shifts: token.includeShifts,
            include_appointments: token.includeAppointments,
            include_handoff_followups: token.includeHandoffFollowups,
            show_minimal_details: token.showMinimalDetails,
            lookahead_days: token.lookaheadDays,
            updated_at: Date().ISO8601Format()
        )

        try await supabaseClient
            .from("ical_feed_tokens")
            .eq("id", token.id)
            .update(updatePayload)

        // Update locally
        try databaseManager.write { db in
            try updatedToken.update(db)
        }

        if let index = feedTokens.firstIndex(where: { $0.id == token.id }) {
            feedTokens[index] = updatedToken
        }
    }

    /// Get the feed URL for a token
    func getFeedURL(for token: ICalFeedToken) -> URL? {
        token.feedURL
    }

    /// Copy feed URL to clipboard with automatic clearing for security
    /// SECURITY: Feed URL contains secret token - auto-clear clipboard after 60 seconds
    func copyFeedURL(for token: ICalFeedToken) {
        guard let url = token.feedURL else { return }
        let urlString = url.absoluteString
        UIPasteboard.general.string = urlString

        // SECURITY: Clear clipboard after 60 seconds to prevent token leakage
        Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
            await MainActor.run {
                // Only clear if clipboard still contains our URL
                if UIPasteboard.general.string == urlString {
                    UIPasteboard.general.string = ""
                }
            }
        }
    }
}

// MARK: - Feed Errors

enum FeedError: LocalizedError {
    case tokenNotFound
    case tokenRevoked
    case tokenExpired
    case createFailed
    case tooManyTokens

    var errorDescription: String? {
        switch self {
        case .tokenNotFound:
            return "Feed token not found"
        case .tokenRevoked:
            return "This feed URL has been revoked"
        case .tokenExpired:
            return "This feed URL has expired"
        case .createFailed:
            return "Failed to create feed URL"
        case .tooManyTokens:
            return "Maximum number of feed URLs reached. Please revoke an existing feed first."
        }
    }
}

// MARK: - UIPasteboard Import

import UIKit
