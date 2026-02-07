import Foundation

// MARK: - Scheduled Ride Model

struct ScheduledRide: Identifiable, Codable, Equatable {
    let id: String
    let circleId: String
    let patientId: String
    let createdBy: String

    // Ride details
    var purpose: String
    var appointmentId: String?
    var pickupAddress: String
    var pickupTime: Date
    var destinationAddress: String
    var destinationName: String?

    // Return ride
    var needsReturn: Bool
    var returnTime: Date?

    // Special needs
    var wheelchairAccessible: Bool
    var stretcherRequired: Bool
    var oxygenRequired: Bool
    var otherNeeds: String?

    // Driver
    var driverType: DriverType
    var driverUserId: String?
    var externalServiceName: String?
    var confirmationStatus: ConfirmationStatus

    // Status
    var status: RideStatus

    // Recurrence
    var recurrenceRule: String?
    var parentRideId: String?

    let createdAt: Date
    var updatedAt: Date

    // MARK: - Driver name (populated from join)
    var driverName: String?

    // MARK: - Enums

    enum DriverType: String, Codable {
        case family = "FAMILY"
        case externalService = "EXTERNAL_SERVICE"

        var displayName: String {
            switch self {
            case .family: return "Family Member"
            case .externalService: return "External Service"
            }
        }
    }

    enum ConfirmationStatus: String, Codable {
        case unconfirmed = "UNCONFIRMED"
        case confirmed = "CONFIRMED"
        case declined = "DECLINED"

        var displayName: String {
            switch self {
            case .unconfirmed: return "Not Confirmed"
            case .confirmed: return "Confirmed"
            case .declined: return "Declined"
            }
        }

        var icon: String {
            switch self {
            case .unconfirmed: return "questionmark.circle"
            case .confirmed: return "checkmark.circle.fill"
            case .declined: return "xmark.circle.fill"
            }
        }
    }

    enum RideStatus: String, Codable {
        case scheduled = "SCHEDULED"
        case completed = "COMPLETED"
        case cancelled = "CANCELLED"
        case missed = "MISSED"

        var displayName: String {
            switch self {
            case .scheduled: return "Scheduled"
            case .completed: return "Completed"
            case .cancelled: return "Cancelled"
            case .missed: return "Missed"
            }
        }
    }

    // MARK: - Computed

    var hasSpecialNeeds: Bool {
        wheelchairAccessible || stretcherRequired || oxygenRequired || (otherNeeds?.isEmpty == false)
    }

    var isUpcoming: Bool {
        status == .scheduled && pickupTime > Date()
    }

    var needsDriver: Bool {
        status == .scheduled && driverType == .family &&
        (confirmationStatus == .unconfirmed || driverUserId == nil)
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case patientId = "patient_id"
        case createdBy = "created_by"
        case purpose
        case appointmentId = "appointment_id"
        case pickupAddress = "pickup_address"
        case pickupTime = "pickup_time"
        case destinationAddress = "destination_address"
        case destinationName = "destination_name"
        case needsReturn = "needs_return"
        case returnTime = "return_time"
        case wheelchairAccessible = "wheelchair_accessible"
        case stretcherRequired = "stretcher_required"
        case oxygenRequired = "oxygen_required"
        case otherNeeds = "other_needs"
        case driverType = "driver_type"
        case driverUserId = "driver_user_id"
        case externalServiceName = "external_service_name"
        case confirmationStatus = "confirmation_status"
        case status
        case recurrenceRule = "recurrence_rule"
        case parentRideId = "parent_ride_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case driverName = "driver_name"
    }
}

// MARK: - Transport Service Model

struct TransportServiceEntry: Identifiable, Codable, Equatable {
    let id: String
    let circleId: String?

    var name: String
    var serviceType: ServiceType
    var phone: String?
    var website: String?
    var hours: String?
    var serviceArea: String?

    var wheelchairAccessible: Bool
    var stretcherAvailable: Bool
    var oxygenAllowed: Bool

    var notes: String?
    var isActive: Bool

    let createdAt: Date

    enum ServiceType: String, Codable, CaseIterable {
        case paratransit = "PARATRANSIT"
        case medicalTransport = "MEDICAL_TRANSPORT"
        case rideshare = "RIDESHARE"
        case volunteer = "VOLUNTEER"

        var displayName: String {
            switch self {
            case .paratransit: return "Paratransit"
            case .medicalTransport: return "Medical Transport"
            case .rideshare: return "Rideshare"
            case .volunteer: return "Volunteer"
            }
        }

        var icon: String {
            switch self {
            case .paratransit: return "bus.fill"
            case .medicalTransport: return "cross.circle.fill"
            case .rideshare: return "car.fill"
            case .volunteer: return "heart.fill"
            }
        }
    }

    var isSystemService: Bool {
        circleId == nil
    }

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case name
        case serviceType = "service_type"
        case phone, website, hours
        case serviceArea = "service_area"
        case wheelchairAccessible = "wheelchair_accessible"
        case stretcherAvailable = "stretcher_available"
        case oxygenAllowed = "oxygen_allowed"
        case notes
        case isActive = "is_active"
        case createdAt = "created_at"
    }
}

// MARK: - Ride Statistics Model

struct RideStatistic: Identifiable, Codable, Equatable {
    let id: String
    let circleId: String
    let userId: String
    let month: String

    var ridesGiven: Int
    var ridesScheduled: Int
    var ridesCancelled: Int

    // Populated from user join
    var userName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case userId = "user_id"
        case month
        case ridesGiven = "rides_given"
        case ridesScheduled = "rides_scheduled"
        case ridesCancelled = "rides_cancelled"
        case userName = "user_name"
    }
}

// MARK: - Ride Date Group (for UI)

struct RideDateGroup: Identifiable {
    let date: Date
    let rides: [ScheduledRide]

    var id: Date { date }

    private static let headerFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }()

    var dateHeader: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            return Self.headerFormatter.string(from: date)
        }
    }
}

// MARK: - Circle Member Info (for Driver Assignment)

struct CircleMemberInfo: Identifiable {
    let id: String
    let displayName: String
    let role: String
    var ridesThisMonth: Int
}

// MARK: - Request Objects

struct CreateRideRequest {
    let circleId: String
    let patientId: String
    let purpose: String
    var appointmentId: String?
    let pickupAddress: String
    let pickupTime: Date
    let destinationAddress: String
    var destinationName: String?
    var needsReturn: Bool = false
    var returnTime: Date?
    var wheelchairAccessible: Bool = false
    var stretcherRequired: Bool = false
    var oxygenRequired: Bool = false
    var otherNeeds: String?
    var driverType: ScheduledRide.DriverType = .family
    var driverUserId: String?
    var externalServiceName: String?
}

struct AddTransportServiceRequest {
    let circleId: String
    let name: String
    let serviceType: TransportServiceEntry.ServiceType
    var phone: String?
    var website: String?
    var hours: String?
    var serviceArea: String?
    var wheelchairAccessible: Bool = false
    var stretcherAvailable: Bool = false
    var oxygenAllowed: Bool = false
    var notes: String?
}

