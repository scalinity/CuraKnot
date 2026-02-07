import Foundation
import OSLog

// MARK: - Respite Finder Errors

enum RespiteFinderError: LocalizedError {
    case notAuthenticated
    case featureNotAvailable
    case validationError(String)
    case networkError(Error)
    case notAuthorized
    case notFound
    case upgradeRequired

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in."
        case .featureNotAvailable:
            return "Upgrade your plan to access this feature."
        case .validationError(let message):
            return message
        case .networkError:
            return "A network error occurred. Please try again."
        case .notAuthorized:
            return "You are not authorized to perform this action."
        case .notFound:
            return "The requested resource was not found."
        case .upgradeRequired:
            return "This feature requires a Plus or Family subscription."
        }
    }
}

// MARK: - Input Limits

private enum InputLimits {
    static let specialConsiderationsMax = 2000
    static let contactValueMax = 200
    static let reviewTitleMax = 200
    static let reviewBodyMax = 5000
    static let notesMax = 2000
    static let providerNameMax = 200
}

// MARK: - Edge Function Request Bodies

private struct SearchProvidersBody: Encodable {
    let latitude: Double
    let longitude: Double
    let radiusMiles: Double
    let limit: Int
    let offset: Int
    var providerType: String?
    var services: [String]?
    var minRating: Double?
    var maxPrice: Double?
    var verifiedOnly: Bool?
}

private struct SubmitRequestBody: Encodable {
    let circleId: String
    let patientId: String
    let providerId: String
    let startDate: String
    let endDate: String
    let specialConsiderations: String?
    let shareMedications: Bool
    let shareContacts: Bool
    let shareDietary: Bool
    let shareFullSummary: Bool
    let contactMethod: String
    let contactValue: String
}

// MARK: - Respite Finder Service

@MainActor
final class RespiteFinderService: ObservableObject {
    private let supabaseClient: SupabaseClient
    private let subscriptionManager: SubscriptionManager
    private let authManager: AuthManager

    private let logger = Logger(subsystem: "com.curaknot", category: "RespiteFinderService")

    @Published var providers: [RespiteProvider] = []
    @Published var selectedProviderReviews: [RespiteReview] = []
    @Published var requests: [RespiteRequest] = []
    @Published var respiteLog: [RespiteLogEntry] = []
    @Published var respiteDaysThisYear: Int = 0
    @Published var isLoading = false
    @Published var hasMore = false

    init(
        supabaseClient: SupabaseClient,
        subscriptionManager: SubscriptionManager,
        authManager: AuthManager
    ) {
        self.supabaseClient = supabaseClient
        self.subscriptionManager = subscriptionManager
        self.authManager = authManager
    }

    // MARK: - Feature Access

    /// All tiers can browse the provider directory
    var canBrowseDirectory: Bool {
        subscriptionManager.hasFeature(.respiteFinder)
    }

    /// PLUS and FAMILY can submit availability requests
    var canSubmitRequests: Bool {
        subscriptionManager.hasFeature(.respiteRequests)
    }

    /// PLUS and FAMILY can write reviews
    var canWriteReviews: Bool {
        subscriptionManager.hasFeature(.respiteReviews)
    }

    /// FAMILY only: respite day tracking
    var canTrackRespite: Bool {
        subscriptionManager.hasFeature(.respiteTracking)
    }

    /// FAMILY only: break reminders
    var hasReminderAccess: Bool {
        subscriptionManager.hasFeature(.respiteReminders)
    }

    // MARK: - Search Providers

    func searchProviders(
        latitude: Double,
        longitude: Double,
        radiusMiles: Double = 25,
        providerType: RespiteProvider.ProviderType? = nil,
        services: [String]? = nil,
        minRating: Double? = nil,
        maxPrice: Double? = nil,
        verifiedOnly: Bool = false,
        limit: Int = 20,
        offset: Int = 0
    ) async throws {
        guard canBrowseDirectory else { throw RespiteFinderError.featureNotAvailable }
        guard getCurrentUserId() != nil else { throw RespiteFinderError.notAuthenticated }

        isLoading = true
        defer { isLoading = false }

        var requestBody = SearchProvidersBody(
            latitude: latitude,
            longitude: longitude,
            radiusMiles: radiusMiles,
            limit: limit,
            offset: offset
        )

        if let type = providerType {
            requestBody.providerType = type.rawValue
        }
        if let services = services, !services.isEmpty {
            requestBody.services = services
        }
        if let rating = minRating, rating > 0 {
            requestBody.minRating = rating
        }
        if let price = maxPrice, price > 0 {
            requestBody.maxPrice = price
        }
        if verifiedOnly {
            requestBody.verifiedOnly = true
        }

        do {
            let response: ProviderSearchResponse = try await supabaseClient
                .functions("search-respite-providers")
                .invoke(body: requestBody)

            if offset == 0 {
                self.providers = response.providers
            } else {
                self.providers.append(contentsOf: response.providers)
            }
            self.hasMore = response.hasMore
        } catch {
            logger.error("Failed to search providers")
            throw RespiteFinderError.networkError(error)
        }
    }

    // MARK: - Fetch Provider Reviews

    /// Raw review response with nested reviewer join from PostgREST
    private struct ReviewWithReviewer: Decodable {
        let id: String
        let provider_id: String
        let circle_id: String
        let reviewer_id: String
        let rating: Int
        let title: String?
        let body: String?
        let service_date: String?
        let created_at: Date
        let updated_at: Date

        struct ReviewerInfo: Decodable {
            let display_name: String?
        }
        let reviewer: ReviewerInfo?
    }

    func fetchReviews(providerId: String, limit: Int = 50) async throws {
        guard getCurrentUserId() != nil else { throw RespiteFinderError.notAuthenticated }

        do {
            let rawReviews: [ReviewWithReviewer] = try await supabaseClient
                .from("respite_reviews")
                .select("*, reviewer:users!reviewer_id(display_name)")
                .eq("provider_id", providerId)
                .eq("status", "PUBLISHED")
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()

            self.selectedProviderReviews = rawReviews.map { raw in
                RespiteReview(
                    id: raw.id,
                    providerId: raw.provider_id,
                    circleId: raw.circle_id,
                    reviewerId: raw.reviewer_id,
                    rating: raw.rating,
                    title: raw.title,
                    body: raw.body,
                    serviceDate: raw.service_date,
                    createdAt: raw.created_at,
                    updatedAt: raw.updated_at,
                    reviewerName: raw.reviewer?.display_name
                )
            }
        } catch {
            // Clear stale reviews so the UI doesn't show outdated data
            self.selectedProviderReviews = []
            logger.error("Failed to fetch reviews")
            throw RespiteFinderError.networkError(error)
        }
    }

    // MARK: - Submit Review

    func submitReview(
        providerId: String,
        circleId: String,
        rating: Int,
        title: String?,
        body: String?,
        serviceDate: String?
    ) async throws {
        guard canWriteReviews else { throw RespiteFinderError.upgradeRequired }
        guard let userId = getCurrentUserId() else { throw RespiteFinderError.notAuthenticated }

        guard rating >= 1 && rating <= 5 else {
            throw RespiteFinderError.validationError("Rating must be between 1 and 5.")
        }

        // Verify circle membership before submitting
        let isMember = try await checkMembership(userId: userId, circleId: circleId)
        guard isMember else { throw RespiteFinderError.notAuthorized }

        var params: [String: Any?] = [
            "provider_id": providerId,
            "circle_id": circleId,
            "reviewer_id": userId,
            "rating": rating
        ]

        if let title = title?.trimmedLimitedOrNil(to: InputLimits.reviewTitleMax) {
            params["title"] = title
        }
        if let body = body?.trimmedLimitedOrNil(to: InputLimits.reviewBodyMax) {
            params["body"] = body
        }
        if let date = serviceDate {
            params["service_date"] = date
        }

        do {
            try await supabaseClient
                .from("respite_reviews")
                .insert(params)
                .execute()

            // Refresh reviews
            try await fetchReviews(providerId: providerId)
        } catch {
            logger.error("Failed to submit review")
            throw RespiteFinderError.networkError(error)
        }
    }

    // MARK: - Submit Availability Request

    func submitRequest(
        circleId: String,
        patientId: String,
        providerId: String,
        startDate: String,
        endDate: String,
        specialConsiderations: String?,
        shareMedications: Bool,
        shareContacts: Bool,
        shareDietary: Bool,
        shareFullSummary: Bool,
        contactMethod: RespiteRequest.ContactMethod,
        contactValue: String
    ) async throws -> String {
        guard canSubmitRequests else { throw RespiteFinderError.upgradeRequired }
        guard getCurrentUserId() != nil else { throw RespiteFinderError.notAuthenticated }

        let trimmedContact = contactValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContact.isEmpty else {
            throw RespiteFinderError.validationError("Contact information is required.")
        }
        guard endDate >= startDate else {
            throw RespiteFinderError.validationError("End date must be on or after start date.")
        }

        let requestBody = SubmitRequestBody(
            circleId: circleId,
            patientId: patientId,
            providerId: providerId,
            startDate: startDate,
            endDate: endDate,
            specialConsiderations: specialConsiderations?.trimmedLimitedOrNil(to: InputLimits.specialConsiderationsMax),
            shareMedications: shareMedications,
            shareContacts: shareContacts,
            shareDietary: shareDietary,
            shareFullSummary: shareFullSummary,
            contactMethod: contactMethod.rawValue,
            contactValue: String(trimmedContact.prefix(InputLimits.contactValueMax))
        )

        do {
            let response: SubmitRequestResponse = try await supabaseClient
                .functions("submit-respite-request")
                .invoke(body: requestBody)

            guard let request = response.request else {
                throw RespiteFinderError.validationError("No request ID returned from server.")
            }

            return request.id
        } catch let error as RespiteFinderError {
            throw error
        } catch {
            logger.error("Failed to submit request")
            throw RespiteFinderError.networkError(error)
        }
    }

    // MARK: - Fetch Requests

    func fetchRequests(circleId: String) async throws {
        guard canSubmitRequests else { throw RespiteFinderError.upgradeRequired }
        guard let userId = getCurrentUserId() else { throw RespiteFinderError.notAuthenticated }

        let isMember = try await checkMembership(userId: userId, circleId: circleId)
        guard isMember else { throw RespiteFinderError.notAuthorized }

        do {
            var requests: [RespiteRequest] = try await supabaseClient
                .from("respite_requests")
                .select()
                .eq("circle_id", circleId)
                .order("created_at", ascending: false)
                .limit(100)
                .execute()

            // Batch fetch provider names to avoid N+1 queries
            let providerIds = Array(Set(requests.map(\.providerId)))
            if !providerIds.isEmpty {
                struct ProviderName: Decodable {
                    let id: String
                    let name: String
                }
                let providers: [ProviderName] = try await supabaseClient
                    .from("respite_providers")
                    .select("id, name")
                    .in("id", values: providerIds)
                    .execute()
                let nameMap = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0.name) })
                for i in requests.indices {
                    requests[i].providerName = nameMap[requests[i].providerId] ?? String(localized: "Unknown Provider")
                }
            }

            self.requests = requests
        } catch {
            logger.error("Failed to fetch requests")
            throw RespiteFinderError.networkError(error)
        }
    }

    // MARK: - Update Request Status

    /// Updates a request's status. RLS enforces that only the creator or circle
    /// ADMIN/OWNER can perform the update. The client pre-check accepts
    /// CONTRIBUTOR (request creators are at least CONTRIBUTOR) as well as
    /// ADMIN/OWNER so creators can cancel their own requests.
    func updateRequestStatus(requestId: String, circleId: String, status: RespiteRequest.RequestStatus) async throws {
        guard let userId = getCurrentUserId() else { throw RespiteFinderError.notAuthenticated }
        let isMember = try await checkMembership(userId: userId, circleId: circleId, requiredRoles: ["CONTRIBUTOR", "ADMIN", "OWNER"])
        guard isMember else { throw RespiteFinderError.notAuthorized }

        do {
            try await supabaseClient
                .from("respite_requests")
                .update(["status": status.rawValue] as [String: Any?])
                .eq("id", requestId)
                .eq("circle_id", circleId)
                .execute()

            try await fetchRequests(circleId: circleId)
        } catch {
            logger.error("Failed to update request status")
            throw RespiteFinderError.networkError(error)
        }
    }

    // MARK: - Respite Log (FAMILY only)

    func fetchRespiteLog(circleId: String) async throws {
        guard canTrackRespite else { throw RespiteFinderError.upgradeRequired }
        guard let userId = getCurrentUserId() else { throw RespiteFinderError.notAuthenticated }
        let isMember = try await checkMembership(userId: userId, circleId: circleId)
        guard isMember else { throw RespiteFinderError.notAuthorized }

        do {
            let response: [RespiteLogEntry] = try await supabaseClient
                .from("respite_log")
                .select()
                .eq("circle_id", circleId)
                .order("start_date", ascending: false)
                .limit(200)
                .execute()

            self.respiteLog = response
        } catch {
            logger.error("Failed to fetch respite log")
            throw RespiteFinderError.networkError(error)
        }
    }

    func addRespiteLogEntry(
        circleId: String,
        patientId: String,
        providerType: String,
        providerName: String,
        startDate: String,
        endDate: String,
        notes: String?
    ) async throws {
        guard canTrackRespite else { throw RespiteFinderError.upgradeRequired }
        guard let userId = getCurrentUserId() else { throw RespiteFinderError.notAuthenticated }
        let isMember = try await checkMembership(userId: userId, circleId: circleId, requiredRoles: ["CONTRIBUTOR", "ADMIN", "OWNER"])
        guard isMember else { throw RespiteFinderError.notAuthorized }

        guard endDate >= startDate else {
            throw RespiteFinderError.validationError("End date must be on or after start date.")
        }

        let trimmedName = String(providerName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(InputLimits.providerNameMax))
        guard !trimmedName.isEmpty else {
            throw RespiteFinderError.validationError("Provider name is required.")
        }

        var params: [String: Any?] = [
            "circle_id": circleId,
            "patient_id": patientId,
            "created_by": userId,
            "provider_type": providerType,
            "provider_name": trimmedName,
            "start_date": startDate,
            "end_date": endDate
        ]

        if let notes = notes?.trimmedLimitedOrNil(to: InputLimits.notesMax) {
            params["notes"] = notes
        }

        do {
            try await supabaseClient
                .from("respite_log")
                .insert(params)
                .execute()

            // Refresh log and year count independently so one failure doesn't block both
            async let logRefresh: () = fetchRespiteLog(circleId: circleId)
            async let yearRefresh: () = fetchRespiteDaysThisYear(circleId: circleId, patientId: patientId)
            try? await logRefresh
            try? await yearRefresh
        } catch {
            logger.error("Failed to add respite log entry")
            throw RespiteFinderError.networkError(error)
        }
    }

    func fetchRespiteDaysThisYear(circleId: String, patientId: String? = nil) async throws {
        guard canTrackRespite else { return }

        // If no patientId provided, reset to 0 (RPC requires it)
        guard let patientId = patientId else {
            self.respiteDaysThisYear = 0
            return
        }

        do {
            let response: Int = try await supabaseClient
                .rpc("get_respite_days_this_year", params: [
                    "p_circle_id": circleId,
                    "p_patient_id": patientId
                ] as [String: Any])

            self.respiteDaysThisYear = response
        } catch {
            logger.error("Failed to fetch respite days")
            throw RespiteFinderError.networkError(error)
        }
    }

    // MARK: - Helpers

    private func getCurrentUserId() -> String? {
        authManager.currentUser?.id
    }

    /// Checks whether the user holds one of the specified roles in the circle.
    /// Pass `nil` for `requiredRoles` to accept any active membership.
    private func checkMembership(
        userId: String,
        circleId: String,
        requiredRoles: [String]? = nil
    ) async throws -> Bool {
        struct MemberRow: Decodable { let user_id: String }
        let rows: [MemberRow]
        if let roles = requiredRoles {
            rows = try await supabaseClient
                .from("circle_members")
                .select("user_id")
                .eq("circle_id", circleId)
                .eq("user_id", userId)
                .eq("status", "ACTIVE")
                .in("role", values: roles)
                .execute()
        } else {
            rows = try await supabaseClient
                .from("circle_members")
                .select("user_id")
                .eq("circle_id", circleId)
                .eq("user_id", userId)
                .eq("status", "ACTIVE")
                .execute()
        }
        return !rows.isEmpty
    }
}
