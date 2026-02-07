import Foundation
import OSLog

// MARK: - Transportation Errors

enum TransportationError: LocalizedError {
    case notAuthenticated
    case featureNotAvailable
    case optimisticLockConflict
    case validationError(String)
    case networkError(Error)
    case rideAlreadyConfirmed
    case rideNotFound
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in."
        case .featureNotAvailable:
            return "Upgrade to Plus to access Transportation."
        case .optimisticLockConflict:
            return "This ride was just updated by someone else. Please refresh and try again."
        case .validationError(let message):
            return message
        case .networkError:
            return "A network error occurred. Please try again."
        case .rideAlreadyConfirmed:
            return "This ride has already been confirmed by another driver."
        case .rideNotFound:
            return "Ride not found."
        case .notAuthorized:
            return "You are not authorized to perform this action."
        }
    }
}

// MARK: - Helper Types

private struct MemberRow: Codable {
    let userId: String
    let role: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case role
    }
}

private struct UserRow: Codable {
    let id: String
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

// MARK: - Input Limits

private enum InputLimits {
    static let purposeMax = 500
    static let addressMax = 1000
    static let nameMax = 500
    static let otherNeedsMax = 2000
    static let serviceNameMax = 500
    static let phoneMax = 50
    static let websiteMax = 2048
    static let serviceAreaMax = 1000
    static let notesMax = 5000
}

// MARK: - Transportation Service

@MainActor
final class TransportationService: ObservableObject {
    private let supabaseClient: SupabaseClient
    private let subscriptionManager: SubscriptionManager
    private let authManager: AuthManager

    private let logger = Logger(subsystem: "com.curaknot", category: "TransportationService")

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    @Published var rides: [ScheduledRide] = [] {
        didSet { recomputeDerivedRides() }
    }
    @Published var unconfirmedRides: [ScheduledRide] = []
    @Published private(set) var upcomingRidesGrouped: [RideDateGroup] = []
    @Published private(set) var pastRides: [ScheduledRide] = []
    @Published var transportServices: [TransportServiceEntry] = []
    @Published var statistics: [RideStatistic] = []
    @Published var isLoading = false

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

    var hasAccess: Bool {
        subscriptionManager.hasFeature(.transportation)
    }

    var hasAnalyticsAccess: Bool {
        subscriptionManager.hasFeature(.transportationAnalytics)
    }

    // MARK: - Derived Ride Computation (cached)

    private func recomputeDerivedRides() {
        let now = Date()
        let upcoming = rides.filter { $0.isUpcoming }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: upcoming) { ride in
            calendar.startOfDay(for: ride.pickupTime)
        }
        upcomingRidesGrouped = grouped.map { RideDateGroup(date: $0.key, rides: $0.value) }
            .sorted { $0.date < $1.date }

        pastRides = rides.filter { !$0.isUpcoming }
            .sorted { $0.pickupTime > $1.pickupTime }

        unconfirmedRides = rides.filter { $0.needsDriver && $0.pickupTime > now }
    }

    // MARK: - Fetch Rides

    func fetchRides(circleId: String) async throws {
        guard hasAccess else { throw TransportationError.featureNotAvailable }
        guard let userId = getCurrentUserId() else {
            throw TransportationError.notAuthenticated
        }
        let isMember = try await checkUserIsAnyMember(userId: userId, circleId: circleId)
        guard isMember else {
            throw TransportationError.notAuthorized
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let response: [ScheduledRide] = try await supabaseClient.from("scheduled_rides")
                .select()
                .eq("circle_id", circleId)
                .neq("status", ScheduledRide.RideStatus.cancelled.rawValue)
                .order("pickup_time", ascending: true)
                .execute()

            self.rides = response
        } catch {
            logger.error("Failed to fetch rides")
            throw TransportationError.networkError(error)
        }
    }

    // MARK: - Create Ride

    func createRide(_ request: CreateRideRequest) async throws {
        guard hasAccess else { throw TransportationError.featureNotAvailable }
        guard let userId = getCurrentUserId() else {
            throw TransportationError.notAuthenticated
        }
        let isMember = try await checkUserIsWriteMember(userId: userId, circleId: request.circleId)
        guard isMember else {
            throw TransportationError.notAuthorized
        }

        // Validation with length limits
        let trimmedPurpose = request.purpose.trimmedAndLimited(to: InputLimits.purposeMax)
        guard !trimmedPurpose.isEmpty else {
            throw TransportationError.validationError("Purpose is required.")
        }
        let trimmedPickup = request.pickupAddress.trimmedAndLimited(to: InputLimits.addressMax)
        guard !trimmedPickup.isEmpty else {
            throw TransportationError.validationError("Pickup address is required.")
        }
        let trimmedDest = request.destinationAddress.trimmedAndLimited(to: InputLimits.addressMax)
        guard !trimmedDest.isEmpty else {
            throw TransportationError.validationError("Destination is required.")
        }
        guard request.pickupTime > Date() else {
            throw TransportationError.validationError("Pickup time must be in the future.")
        }
        if request.needsReturn {
            guard let returnTime = request.returnTime else {
                throw TransportationError.validationError("Return time is required when return ride is needed.")
            }
            guard returnTime > request.pickupTime else {
                throw TransportationError.validationError("Return time must be after pickup time.")
            }
        }

        // Validate driver is circle member if specified
        if let driverUserId = request.driverUserId {
            let isDriverMember = try await checkUserIsAnyMember(userId: driverUserId, circleId: request.circleId)
            guard isDriverMember else {
                throw TransportationError.validationError("Selected driver is not a circle member.")
            }
        }

        var params: [String: Any?] = [
            "circle_id": request.circleId,
            "patient_id": request.patientId,
            "created_by": userId,
            "purpose": trimmedPurpose,
            "pickup_address": trimmedPickup,
            "pickup_time": Self.isoFormatter.string(from: request.pickupTime),
            "destination_address": trimmedDest,
            "needs_return": request.needsReturn,
            "wheelchair_accessible": request.wheelchairAccessible,
            "stretcher_required": request.stretcherRequired,
            "oxygen_required": request.oxygenRequired,
            "driver_type": request.driverType.rawValue,
            "confirmation_status": ScheduledRide.ConfirmationStatus.unconfirmed.rawValue,
            "status": ScheduledRide.RideStatus.scheduled.rawValue
        ]

        if let appointmentId = request.appointmentId {
            params["appointment_id"] = appointmentId
        }
        if let destName = request.destinationName?.trimmedLimitedOrNil(to: InputLimits.nameMax) {
            params["destination_name"] = destName
        }
        if request.needsReturn, let returnTime = request.returnTime {
            params["return_time"] = Self.isoFormatter.string(from: returnTime)
        }
        if let otherNeeds = request.otherNeeds?.trimmedLimitedOrNil(to: InputLimits.otherNeedsMax) {
            params["other_needs"] = otherNeeds
        }
        if let driverUserId = request.driverUserId {
            params["driver_user_id"] = driverUserId
        }
        if let serviceName = request.externalServiceName?.trimmedLimitedOrNil(to: InputLimits.serviceNameMax) {
            params["external_service_name"] = serviceName
        }

        // Perform the insert
        do {
            try await supabaseClient.from("scheduled_rides")
                .insert(params)
                .execute()
        } catch {
            logger.error("Failed to create ride")
            throw TransportationError.networkError(error)
        }

        // Refresh is best-effort - mutation already succeeded
        do {
            try await fetchRides(circleId: request.circleId)
        } catch {
            logger.error("Ride created but refresh failed")
        }
    }

    // MARK: - Volunteer as Driver

    func volunteerAsDriver(rideId: String, circleId: String) async throws {
        guard let userId = getCurrentUserId() else {
            throw TransportationError.notAuthenticated
        }

        // Verify user is circle member (write access needed)
        let isMember = try await checkUserIsWriteMember(userId: userId, circleId: circleId)
        guard isMember else {
            throw TransportationError.notAuthorized
        }

        do {
            // Only update if still unconfirmed (optimistic lock) — verify via returned rows
            let updated: [ScheduledRide] = try await supabaseClient.from("scheduled_rides")
                .update([
                    "driver_user_id": userId,
                    "driver_type": ScheduledRide.DriverType.family.rawValue,
                    "confirmation_status": ScheduledRide.ConfirmationStatus.confirmed.rawValue
                ] as [String: Any?])
                .eq("id", rideId)
                .eq("circle_id", circleId)
                .eq("confirmation_status", ScheduledRide.ConfirmationStatus.unconfirmed.rawValue)
                .executeReturning()

            guard !updated.isEmpty else {
                throw TransportationError.rideAlreadyConfirmed
            }

            // Re-fetch from server to get authoritative state
            try await fetchRides(circleId: circleId)
        } catch let error as TransportationError {
            throw error
        } catch {
            logger.error("Failed to volunteer as driver")
            throw TransportationError.networkError(error)
        }
    }

    // MARK: - Request Driver

    func requestDriver(rideId: String, circleId: String, driverUserId: String) async throws {
        guard let userId = getCurrentUserId() else {
            throw TransportationError.notAuthenticated
        }

        // Verify caller is circle member (write access needed)
        let isMember = try await checkUserIsWriteMember(userId: userId, circleId: circleId)
        guard isMember else {
            throw TransportationError.notAuthorized
        }

        // Verify target driver is also a circle member (any role can be asked to drive)
        let isDriverMember = try await checkUserIsAnyMember(userId: driverUserId, circleId: circleId)
        guard isDriverMember else {
            throw TransportationError.validationError("Selected driver is not a circle member.")
        }

        do {
            // Pure optimistic lock — only update if still unconfirmed (no separate SELECT)
            let updated: [ScheduledRide] = try await supabaseClient.from("scheduled_rides")
                .update([
                    "driver_user_id": driverUserId,
                    "driver_type": ScheduledRide.DriverType.family.rawValue,
                    "confirmation_status": ScheduledRide.ConfirmationStatus.unconfirmed.rawValue
                ] as [String: Any?])
                .eq("id", rideId)
                .eq("circle_id", circleId)
                .neq("confirmation_status", ScheduledRide.ConfirmationStatus.confirmed.rawValue)
                .executeReturning()

            guard !updated.isEmpty else {
                throw TransportationError.rideAlreadyConfirmed
            }

            // Re-fetch from server to get authoritative state
            try await fetchRides(circleId: circleId)
        } catch let error as TransportationError {
            throw error
        } catch {
            logger.error("Failed to request driver")
            throw TransportationError.networkError(error)
        }
    }

    // MARK: - Confirm / Decline

    func confirmRide(rideId: String, circleId: String) async throws {
        guard let userId = getCurrentUserId() else {
            throw TransportationError.notAuthenticated
        }

        do {
            // Only the assigned driver can confirm
            let updated: [ScheduledRide] = try await supabaseClient.from("scheduled_rides")
                .update([
                    "confirmation_status": ScheduledRide.ConfirmationStatus.confirmed.rawValue
                ] as [String: Any?])
                .eq("id", rideId)
                .eq("driver_user_id", userId)
                .eq("confirmation_status", ScheduledRide.ConfirmationStatus.unconfirmed.rawValue)
                .executeReturning()

            guard !updated.isEmpty else {
                throw TransportationError.notAuthorized
            }

            try await fetchRides(circleId: circleId)
        } catch let error as TransportationError {
            throw error
        } catch {
            logger.error("Failed to confirm ride")
            throw TransportationError.networkError(error)
        }
    }

    func declineRide(rideId: String, circleId: String) async throws {
        guard let userId = getCurrentUserId() else {
            throw TransportationError.notAuthenticated
        }

        do {
            // Only the assigned driver can decline
            let updated: [ScheduledRide] = try await supabaseClient.from("scheduled_rides")
                .update([
                    "driver_user_id": nil,
                    "confirmation_status": ScheduledRide.ConfirmationStatus.unconfirmed.rawValue
                ] as [String: Any?])
                .eq("id", rideId)
                .eq("driver_user_id", userId)
                .eq("confirmation_status", ScheduledRide.ConfirmationStatus.unconfirmed.rawValue)
                .executeReturning()

            guard !updated.isEmpty else {
                throw TransportationError.notAuthorized
            }

            try await fetchRides(circleId: circleId)
        } catch let error as TransportationError {
            throw error
        } catch {
            logger.error("Failed to decline ride")
            throw TransportationError.networkError(error)
        }
    }

    // MARK: - Cancel Ride

    func cancelRide(rideId: String, circleId: String) async throws {
        guard let userId = getCurrentUserId() else {
            throw TransportationError.notAuthenticated
        }

        do {
            let isAdmin = try await checkUserIsAdminOrOwner(userId: userId, circleId: circleId)

            // Build query with authorization: admin/owner can cancel any ride,
            // others can only cancel rides they created or are driving
            var query = await supabaseClient.from("scheduled_rides")
                .update(["status": ScheduledRide.RideStatus.cancelled.rawValue] as [String: Any?])
                .eq("id", rideId)
                .eq("status", ScheduledRide.RideStatus.scheduled.rawValue)

            if !isAdmin {
                // Validate UUID format before string interpolation into PostgREST filter
                let safeUserId = try validateUUID(userId)
                query = query.or("created_by.eq.\(safeUserId),driver_user_id.eq.\(safeUserId)")
            }

            let updated: [ScheduledRide] = try await query.executeReturning()

            guard !updated.isEmpty else {
                throw TransportationError.notAuthorized
            }

            try await fetchRides(circleId: circleId)
        } catch let error as TransportationError {
            throw error
        } catch {
            logger.error("Failed to cancel ride")
            throw TransportationError.networkError(error)
        }
    }

    // MARK: - Complete Ride

    func completeRide(rideId: String, circleId: String) async throws {
        guard let userId = getCurrentUserId() else {
            throw TransportationError.notAuthenticated
        }

        do {
            let isAdmin = try await checkUserIsAdminOrOwner(userId: userId, circleId: circleId)

            // Build query with authorization: admin/owner can complete any ride,
            // others can only complete rides they created or are driving
            var query = await supabaseClient.from("scheduled_rides")
                .update(["status": ScheduledRide.RideStatus.completed.rawValue] as [String: Any?])
                .eq("id", rideId)
                .eq("status", ScheduledRide.RideStatus.scheduled.rawValue)

            if !isAdmin {
                // Validate UUID format before string interpolation into PostgREST filter
                let safeUserId = try validateUUID(userId)
                query = query.or("created_by.eq.\(safeUserId),driver_user_id.eq.\(safeUserId)")
            }

            let updated: [ScheduledRide] = try await query.executeReturning()

            guard !updated.isEmpty else {
                throw TransportationError.notAuthorized
            }

            try await fetchRides(circleId: circleId)
        } catch let error as TransportationError {
            throw error
        } catch {
            logger.error("Failed to complete ride")
            throw TransportationError.networkError(error)
        }
    }

    // MARK: - Transport Services

    func fetchTransportServices(circleId: String) async throws {
        guard hasAccess else { throw TransportationError.featureNotAvailable }
        guard let userId = getCurrentUserId() else {
            throw TransportationError.notAuthenticated
        }
        let isMember = try await checkUserIsAnyMember(userId: userId, circleId: circleId)
        guard isMember else {
            throw TransportationError.notAuthorized
        }

        do {
            // Fetch system + circle services in parallel
            async let systemFetch: [TransportServiceEntry] = supabaseClient.from("transport_services")
                .select()
                .is("circle_id", value: nil)
                .order("name", ascending: true)
                .execute()

            async let circleFetch: [TransportServiceEntry] = supabaseClient.from("transport_services")
                .select()
                .eq("circle_id", circleId)
                .order("name", ascending: true)
                .execute()

            let (systemServices, circleSpecific) = try await (systemFetch, circleFetch)
            self.transportServices = (systemServices + circleSpecific).sorted { $0.name < $1.name }
        } catch {
            logger.error("Failed to fetch transport services")
            throw TransportationError.networkError(error)
        }
    }

    func addTransportService(_ request: AddTransportServiceRequest) async throws {
        guard hasAccess else { throw TransportationError.featureNotAvailable }
        guard let userId = getCurrentUserId() else {
            throw TransportationError.notAuthenticated
        }

        // Verify user is circle member (write access needed)
        let isMember = try await checkUserIsWriteMember(userId: userId, circleId: request.circleId)
        guard isMember else {
            throw TransportationError.notAuthorized
        }

        let trimmedName = request.name.trimmedAndLimited(to: InputLimits.serviceNameMax)
        guard !trimmedName.isEmpty else {
            throw TransportationError.validationError("Service name is required.")
        }

        var params: [String: Any?] = [
            "circle_id": request.circleId,
            "name": trimmedName,
            "service_type": request.serviceType.rawValue,
            "wheelchair_accessible": request.wheelchairAccessible,
            "stretcher_available": request.stretcherAvailable,
            "oxygen_allowed": request.oxygenAllowed,
            "is_active": true
        ]

        if let phone = request.phone?.trimmedLimitedOrNil(to: InputLimits.phoneMax) {
            params["phone"] = phone
        }
        if let website = request.website?.trimmedLimitedOrNil(to: InputLimits.websiteMax) {
            params["website"] = website
        }
        if let hours = request.hours?.trimmedLimitedOrNil(to: InputLimits.nameMax) {
            params["hours"] = hours
        }
        if let serviceArea = request.serviceArea?.trimmedLimitedOrNil(to: InputLimits.serviceAreaMax) {
            params["service_area"] = serviceArea
        }
        if let notes = request.notes?.trimmedLimitedOrNil(to: InputLimits.notesMax) {
            params["notes"] = notes
        }

        do {
            try await supabaseClient.from("transport_services")
                .insert(params)
                .execute()

            // Refresh to get the full object with server-generated fields
            try await fetchTransportServices(circleId: request.circleId)
        } catch {
            logger.error("Failed to add transport service")
            throw TransportationError.networkError(error)
        }
    }

    // MARK: - Ride Statistics (FAMILY only)

    func fetchStatistics(circleId: String) async throws {
        guard hasAnalyticsAccess else { throw TransportationError.featureNotAvailable }
        guard let userId = getCurrentUserId() else {
            throw TransportationError.notAuthenticated
        }
        let isMember = try await checkUserIsAnyMember(userId: userId, circleId: circleId)
        guard isMember else {
            throw TransportationError.notAuthorized
        }
        let monthStr = currentMonthString()

        do {
            let response: [RideStatistic] = try await supabaseClient.from("ride_statistics")
                .select()
                .eq("circle_id", circleId)
                .eq("month", monthStr)
                .execute()

            // Resolve user names from users table
            let userIds = response.map { $0.userId }
            if !userIds.isEmpty {
                let users: [UserRow] = try await supabaseClient.from("users")
                    .select("id, display_name")
                    .in("id", values: userIds)
                    .execute()
                let nameMap = Dictionary(users.compactMap { u in
                    u.displayName.map { (u.id, $0) }
                }, uniquingKeysWith: { _, last in last })
                self.statistics = response.map { stat in
                    var updated = stat
                    updated.userName = nameMap[stat.userId]
                    return updated
                }
            } else {
                self.statistics = response
            }
        } catch {
            logger.error("Failed to fetch statistics")
            throw TransportationError.networkError(error)
        }
    }

    // MARK: - Circle Members (for Driver Assignment)

    func fetchCircleMembers(circleId: String) async throws -> [CircleMemberInfo] {
        guard let userId = getCurrentUserId() else {
            throw TransportationError.notAuthenticated
        }

        // Verify caller has write access (driver coordination is a write operation)
        let isCallerMember = try await checkUserIsWriteMember(userId: userId, circleId: circleId)
        guard isCallerMember else {
            throw TransportationError.notAuthorized
        }

        let monthStr = currentMonthString()

        // Fetch members, users, and stats in parallel
        async let membersFetch: [MemberRow] = supabaseClient
            .from("circle_members")
            .select("user_id, role")
            .eq("circle_id", circleId)
            .eq("status", "ACTIVE")
            .in("role", values: ["CONTRIBUTOR", "ADMIN", "OWNER"])
            .execute()

        async let statsFetch: [RideStatistic] = supabaseClient
            .from("ride_statistics")
            .select()
            .eq("circle_id", circleId)
            .eq("month", monthStr)
            .execute()

        let (response, stats) = try await (membersFetch, statsFetch)

        // Fetch display names from users table
        let memberUserIds = response.map { $0.userId }
        var nameMap: [String: String] = [:]
        if !memberUserIds.isEmpty {
            let users: [UserRow] = try await supabaseClient.from("users")
                .select("id, display_name")
                .in("id", values: memberUserIds)
                .execute()
            for user in users {
                if let name = user.displayName {
                    nameMap[user.id] = name
                }
            }
        }

        var members = response.map { row in
            CircleMemberInfo(
                id: row.userId,
                displayName: nameMap[row.userId] ?? "Member",
                role: row.role,
                ridesThisMonth: 0
            )
        }

        for stat in stats {
            if let index = members.firstIndex(where: { $0.id == stat.userId }) {
                members[index].ridesThisMonth = stat.ridesGiven
            }
        }

        // Sort: fewer rides first (fair distribution)
        return members.sorted { $0.ridesThisMonth < $1.ridesThisMonth }
    }

    // MARK: - Helpers

    private func getCurrentUserId() -> String? {
        authManager.currentUser?.id
    }

    /// Validates that a string is a well-formed UUID to prevent PostgREST filter injection
    private func validateUUID(_ value: String) throws -> String {
        guard UUID(uuidString: value) != nil else {
            throw TransportationError.validationError("Invalid identifier format.")
        }
        return value
    }

    private func currentMonthString() -> String {
        guard let currentMonth = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: Date())
        ) else {
            // Fallback: manually construct first-of-month string
            let components = Calendar.current.dateComponents([.year, .month], from: Date())
            let year = components.year ?? Calendar.current.component(.year, from: Date())
            let month = components.month ?? Calendar.current.component(.month, from: Date())
            return String(format: "%04d-%02d-01", year, month)
        }
        return Self.dateFormatter.string(from: currentMonth)
    }

    private func checkUserIsAdminOrOwner(userId: String, circleId: String) async throws -> Bool {
        struct RoleRow: Decodable {
            let role: String
        }

        let rows: [RoleRow] = try await supabaseClient
            .from("circle_members")
            .select("role")
            .eq("circle_id", circleId)
            .eq("user_id", userId)
            .eq("status", "ACTIVE")
            .execute()

        guard let row = rows.first else { return false }
        return row.role == "ADMIN" || row.role == "OWNER"
    }

    /// Check if user is any active member of the circle (including VIEWER) — for read operations
    private func checkUserIsAnyMember(userId: String, circleId: String) async throws -> Bool {
        struct MemberRow: Decodable { let user_id: String }
        let rows: [MemberRow] = try await supabaseClient
            .from("circle_members")
            .select("user_id")
            .eq("circle_id", circleId)
            .eq("user_id", userId)
            .eq("status", "ACTIVE")
            .execute()
        return !rows.isEmpty
    }

    /// Check if user is an active write-capable member (CONTRIBUTOR/ADMIN/OWNER) — for write operations
    private func checkUserIsWriteMember(userId: String, circleId: String) async throws -> Bool {
        struct MemberRow: Decodable { let user_id: String }
        let rows: [MemberRow] = try await supabaseClient
            .from("circle_members")
            .select("user_id")
            .eq("circle_id", circleId)
            .eq("user_id", userId)
            .eq("status", "ACTIVE")
            .in("role", values: ["CONTRIBUTOR", "ADMIN", "OWNER"])
            .execute()
        return !rows.isEmpty
    }
}
