import Foundation

// MARK: - Respite Provider

struct RespiteProvider: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var providerType: ProviderType
    var description: String?
    var address: String?
    var city: String?
    var state: String?
    var zipCode: String?
    var latitude: Double?
    var longitude: Double?
    var phone: String?
    var email: String?
    var website: String?
    var hoursJson: [String: String]?
    var pricingModel: PricingModel?
    var priceMin: Double?
    var priceMax: Double?
    var acceptsMedicaid: Bool
    var acceptsMedicare: Bool
    var scholarshipsAvailable: Bool
    var services: [String]
    var verificationStatus: VerificationStatus
    var avgRating: Double
    var reviewCount: Int
    var distanceMiles: Double?

    // Local cache metadata (not from API)
    var cachedAt: Date?

    enum ProviderType: String, Codable, CaseIterable {
        case adultDay = "ADULT_DAY"
        case inHome = "IN_HOME"
        case overnight = "OVERNIGHT"
        case volunteer = "VOLUNTEER"
        case emergency = "EMERGENCY"

        var displayName: String {
            switch self {
            case .adultDay: return "Adult Day Care"
            case .inHome: return "In-Home Care"
            case .overnight: return "Overnight Care"
            case .volunteer: return "Volunteer"
            case .emergency: return "Emergency"
            }
        }

        var icon: String {
            switch self {
            case .adultDay: return "sun.max.fill"
            case .inHome: return "house.fill"
            case .overnight: return "moon.fill"
            case .volunteer: return "heart.fill"
            case .emergency: return "exclamationmark.triangle.fill"
            }
        }
    }

    enum PricingModel: String, Codable {
        case hourly = "HOURLY"
        case daily = "DAILY"
        case weekly = "WEEKLY"
        case sliding = "SLIDING_SCALE"
        case free = "FREE"

        var displayName: String {
            switch self {
            case .hourly: return "Hourly"
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .sliding: return "Sliding Scale"
            case .free: return "Free"
            }
        }
    }

    enum VerificationStatus: String, Codable {
        case unverified = "UNVERIFIED"
        case verified = "VERIFIED"
        case featured = "FEATURED"

        var displayName: String {
            switch self {
            case .unverified: return "Unverified"
            case .verified: return "Verified"
            case .featured: return "Featured"
            }
        }

        var icon: String? {
            switch self {
            case .unverified: return nil
            case .verified: return "checkmark.seal.fill"
            case .featured: return "star.fill"
            }
        }
    }

    var formattedDistance: String? {
        guard let dist = distanceMiles else { return nil }
        if dist < 1 {
            return String(format: "%.1f mi", dist)
        }
        return String(format: "%.0f mi", dist)
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    var formattedPriceRange: String? {
        guard let model = pricingModel else { return nil }
        if model == .free { return "Free" }
        if model == .sliding { return "Sliding Scale" }
        guard let min = priceMin else { return nil }
        let minStr = Self.currencyFormatter.string(from: NSNumber(value: min)) ?? "$\(Int(min))"
        if let max = priceMax, max > min {
            let maxStr = Self.currencyFormatter.string(from: NSNumber(value: max)) ?? "$\(Int(max))"
            return "\(minStr)–\(maxStr)/\(model.displayName.lowercased())"
        }
        return "\(minStr)/\(model.displayName.lowercased())"
    }

    var hasFinancialAssistance: Bool {
        acceptsMedicaid || acceptsMedicare || scholarshipsAvailable
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, address, city, state, phone, email, website, services
        case providerType, zipCode, latitude, longitude
        case hoursJson, pricingModel, priceMin, priceMax
        case acceptsMedicaid, acceptsMedicare, scholarshipsAvailable
        case verificationStatus, avgRating, reviewCount, distanceMiles
        case cachedAt
    }
}

// MARK: - Respite Review

struct RespiteReview: Identifiable, Codable, Equatable {
    let id: String
    let providerId: String
    let circleId: String
    let reviewerId: String
    var rating: Int
    var title: String?
    var body: String?
    var serviceDate: String?
    let createdAt: Date
    var updatedAt: Date

    // Populated from join
    var reviewerName: String?

    var ratingStars: String {
        String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case providerId = "provider_id"
        case circleId = "circle_id"
        case reviewerId = "reviewer_id"
        case rating, title, body
        case serviceDate = "service_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case reviewerName = "reviewer_name"
    }
}

// MARK: - Respite Request

struct RespiteRequest: Identifiable, Codable, Equatable {
    let id: String
    let circleId: String
    let patientId: String
    let providerId: String
    let createdBy: String
    var startDate: String
    var endDate: String
    var specialConsiderations: String?
    var shareMedications: Bool
    var shareContacts: Bool
    var shareDietary: Bool
    var shareFullSummary: Bool
    var contactMethod: ContactMethod
    var contactValue: String
    var status: RequestStatus
    let createdAt: Date
    var updatedAt: Date

    // Populated from join
    var providerName: String?

    enum ContactMethod: String, Codable {
        case phone = "PHONE"
        case email = "EMAIL"

        var displayName: String {
            switch self {
            case .phone: return "Phone"
            case .email: return "Email"
            }
        }
    }

    enum RequestStatus: String, Codable {
        case pending = "PENDING"
        case confirmed = "CONFIRMED"
        case declined = "DECLINED"
        case cancelled = "CANCELLED"
        case completed = "COMPLETED"

        var displayName: String {
            switch self {
            case .pending: return "Pending"
            case .confirmed: return "Confirmed"
            case .declined: return "Declined"
            case .cancelled: return "Cancelled"
            case .completed: return "Completed"
            }
        }

        var icon: String {
            switch self {
            case .pending: return "clock.fill"
            case .confirmed: return "checkmark.circle.fill"
            case .declined: return "xmark.circle.fill"
            case .cancelled: return "minus.circle.fill"
            case .completed: return "checkmark.seal.fill"
            }
        }

    }

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case patientId = "patient_id"
        case providerId = "provider_id"
        case createdBy = "created_by"
        case startDate = "start_date"
        case endDate = "end_date"
        case specialConsiderations = "special_considerations"
        case shareMedications = "share_medications"
        case shareContacts = "share_contacts"
        case shareDietary = "share_dietary"
        case shareFullSummary = "share_full_summary"
        case contactMethod = "contact_method"
        case contactValue = "contact_value"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case providerName = "provider_name"
    }
}

// MARK: - Respite Log Entry

struct RespiteLogEntry: Identifiable, Codable, Equatable {
    let id: String
    let circleId: String
    let patientId: String
    let createdBy: String
    var providerType: String
    var providerName: String
    var startDate: String
    var endDate: String
    var totalDays: Int
    var notes: String?
    let createdAt: Date

    var dateRange: String {
        "\(startDate) – \(endDate)"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case patientId = "patient_id"
        case createdBy = "created_by"
        case providerType = "provider_type"
        case providerName = "provider_name"
        case startDate = "start_date"
        case endDate = "end_date"
        case totalDays = "total_days"
        case notes
        case createdAt = "created_at"
    }
}

// MARK: - Search Request

struct ProviderSearchRequest: Codable {
    let latitude: Double
    let longitude: Double
    var radiusMiles: Double = 25
    var providerType: String?
    var services: [String]?
    var minRating: Double?
    var maxPrice: Double?
    var verifiedOnly: Bool?
    var limit: Int?
    var offset: Int?
}

// MARK: - Search Response

struct ProviderSearchResponse: Codable {
    let success: Bool
    let providers: [RespiteProvider]
    let total: Int
    let hasMore: Bool
}

// MARK: - Submit Request Response

struct SubmitRequestResponse: Codable {
    let success: Bool
    let request: RequestInfo?

    struct RequestInfo: Codable {
        let id: String
        let status: String
        let createdAt: String
    }
}

// MARK: - Respite Days Response (RPC returns a single int)
