import Foundation
import GRDB

// MARK: - Care Network Service

@MainActor
final class CareNetworkService: ObservableObject {
    // MARK: - Dependencies

    private let databaseManager: DatabaseManager
    private let supabaseClient: SupabaseClient
    private let syncCoordinator: SyncCoordinator
    private let subscriptionManager: SubscriptionManager

    // MARK: - Initialization

    init(
        databaseManager: DatabaseManager,
        supabaseClient: SupabaseClient,
        syncCoordinator: SyncCoordinator,
        subscriptionManager: SubscriptionManager
    ) {
        self.databaseManager = databaseManager
        self.supabaseClient = supabaseClient
        self.syncCoordinator = syncCoordinator
        self.subscriptionManager = subscriptionManager
    }

    // MARK: - Provider Aggregation

    /// Fetches all providers (contacts and facilities) for a patient, grouped by category
    func fetchProviders(circleId: String, patientId: String) async throws -> [ProviderGroup] {
        let items = try databaseManager.read { db in
            try BinderItem
                .filter(Column("circleId") == circleId)
                .filter(Column("patientId") == patientId || Column("patientId") == nil)
                .filter(Column("type") == "CONTACT" || Column("type") == "FACILITY" || Column("type") == "INSURANCE")
                .filter(Column("isActive") == true)
                .order(Column("title"))
                .fetchAll(db)
        }

        return groupProviders(items)
    }

    /// Groups binder items into provider categories
    private func groupProviders(_ items: [BinderItem]) -> [ProviderGroup] {
        var groups: [ProviderCategory: [Provider]] = [:]

        for item in items {
            let category = categorize(item)
            let provider = Provider(from: item)

            if groups[category] == nil {
                groups[category] = []
            }
            groups[category]?.append(provider)
        }

        // Sort by category priority and return as array
        return ProviderCategory.allCases.compactMap { category in
            guard let providers = groups[category], !providers.isEmpty else { return nil }
            return ProviderGroup(category: category, providers: providers)
        }
    }

    /// Determines the provider category for a binder item
    private func categorize(_ item: BinderItem) -> ProviderCategory {
        switch item.type {
        case .contact:
            guard let content = try? JSONDecoder().decode(ContactContent.self, from: Data(item.contentJson.utf8)) else {
                return .other
            }
            switch content.role {
            case .doctor, .nurse:
                return .medical
            case .socialWorker:
                return .homeCare
            case .family:
                return .emergency
            case .other:
                if content.organization?.lowercased().contains("pharmacy") == true {
                    return .pharmacy
                }
                return .medical
            }
        case .facility:
            return .facility
        case .insurance:
            return .insurance
        default:
            return .other
        }
    }

    // MARK: - Export & Sharing

    /// Checks if user has access to export feature (Plus+ tier)
    func canExport() async -> Bool {
        let plan = subscriptionManager.currentPlan
        return plan == .plus || plan == .family
    }

    /// Checks if user has access to share feature (Plus+ tier)
    func canShare() async -> Bool {
        let plan = subscriptionManager.currentPlan
        return plan == .plus || plan == .family
    }

    /// Checks if user can add notes/ratings (Family tier)
    func canAddNotes() async -> Bool {
        return subscriptionManager.currentPlan == .family
    }

    /// Generates a PDF export and optionally creates a share link
    func generateExport(
        patientId: String,
        includedTypes: [ProviderCategory] = ProviderCategory.exportableCategories,
        createShareLink: Bool = false,
        shareLinkDays: Int = 7
    ) async throws -> CareNetworkExport {
        // Validate shareLinkDays range (1-90 days)
        let validatedDays = max(1, min(90, shareLinkDays))

        struct Request: Encodable {
            let patientId: String
            let includedTypes: [String]
            let createShareLink: Bool
            let shareLinkTtlDays: Int
        }

        struct Response: Decodable {
            let success: Bool
            let exportId: String?
            let pdfUrl: String?
            let shareLink: ShareLinkData?
            let providerCount: Int?
            let error: ErrorData?

            struct ShareLinkData: Decodable {
                let token: String
                let url: String
                let expiresAt: String
            }

            struct ErrorData: Decodable {
                let code: String
                let message: String
            }
        }

        let request = Request(
            patientId: patientId,
            includedTypes: includedTypes.map { $0.rawValue },
            createShareLink: createShareLink,
            shareLinkTtlDays: validatedDays
        )

        let response: Response = try await supabaseClient
            .functions("generate-care-network-pdf")
            .invoke(body: request)

        if let error = response.error {
            throw CareNetworkError.exportFailed(error.message)
        }

        guard response.success,
              let exportId = response.exportId,
              let pdfUrl = response.pdfUrl else {
            throw CareNetworkError.exportFailed("Missing export data")
        }

        var shareLink: ShareLink?
        if let linkData = response.shareLink {
            // Use safe date parsing with fallback
            let expiresAt = ISO8601DateFormatter().date(from: linkData.expiresAt)
                ?? Date().addingTimeInterval(7 * 24 * 60 * 60) // Default 7 days if parsing fails
            shareLink = ShareLink(
                token: linkData.token,
                url: linkData.url,
                expiresAt: expiresAt
            )
        }

        // Safe URL construction with validation
        guard let pdfURL = URL(string: pdfUrl) else {
            throw CareNetworkError.invalidResponse
        }

        return CareNetworkExport(
            id: exportId,
            pdfURL: pdfURL,
            providerCount: response.providerCount ?? 0,
            shareLink: shareLink,
            createdAt: Date()
        )
    }

    /// Creates a share link for an existing export
    func createShareLink(exportId: String, ttlDays: Int = 7) async throws -> ShareLink {
        struct CreateLinkResponse: Decodable {
            let linkId: String
            let token: String
            let expiresAt: String
        }

        let result: CreateLinkResponse = try await supabaseClient.rpc(
            "create_share_link",
            params: [
                "p_circle_id": "", // Filled by function
                "p_user_id": "", // Filled by function
                "p_object_type": "care_network",
                "p_object_id": exportId,
                "p_ttl_hours": ttlDays * 24
            ]
        )

        guard let expiresAt = ISO8601DateFormatter().date(from: result.expiresAt) else {
            throw CareNetworkError.invalidResponse
        }

        let baseURL = await supabaseClient.url.absoluteString
        
        // URL-encode the token to handle any special characters
        guard let encodedToken = result.token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw CareNetworkError.invalidResponse
        }
        
        return ShareLink(
            token: result.token,
            url: "\(baseURL)/functions/v1/resolve-share-link?token=\(encodedToken)",
            expiresAt: expiresAt
        )
    }

    // MARK: - Provider Notes (Family Tier)

    /// Fetches notes for a specific provider
    func fetchProviderNotes(binderItemId: String) async throws -> [ProviderNote] {
        struct NoteRecord: Decodable {
            let id: String
            let binderItemId: String
            let createdBy: String
            let note: String
            let rating: Int?
            let createdAt: Date
            let updatedAt: Date
        }

        let records: [NoteRecord] = try await supabaseClient
            .from("provider_notes")
            .select()
            .eq("binder_item_id", binderItemId)
            .order("created_at", ascending: false)
            .execute()

        return records.map { record in
            ProviderNote(
                id: record.id,
                binderItemId: record.binderItemId,
                authorId: record.createdBy,
                note: record.note,
                rating: record.rating,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            )
        }
    }

    /// Saves or updates a provider note
    func saveProviderNote(
        circleId: String,
        binderItemId: String,
        note: String,
        rating: Int?
    ) async throws {
        // Validate note length (max 5000 characters)
        guard note.count <= 5000 else {
            throw CareNetworkError.exportFailed("Note exceeds maximum length of 5000 characters")
        }
        
        // Validate rating range (1-5) if provided
        if let rating = rating {
            guard (1...5).contains(rating) else {
                throw CareNetworkError.exportFailed("Rating must be between 1 and 5")
            }
        }
        
        try await supabaseClient
            .from("provider_notes")
            .upsert([
                "circle_id": circleId,
                "binder_item_id": binderItemId,
                "note": note,
                "rating": rating as Any
            ])
            .execute()
    }
}

// MARK: - Provider Category

enum ProviderCategory: String, CaseIterable, Identifiable {
    case medical = "MEDICAL"
    case facility = "FACILITY"
    case pharmacy = "PHARMACY"
    case homeCare = "HOME_CARE"
    case emergency = "EMERGENCY"
    case insurance = "INSURANCE"
    case other = "OTHER"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .medical: return "Medical Providers"
        case .facility: return "Facilities"
        case .pharmacy: return "Pharmacy"
        case .homeCare: return "Home Care"
        case .emergency: return "Emergency Contacts"
        case .insurance: return "Insurance"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .medical: return "stethoscope"
        case .facility: return "building.2.fill"
        case .pharmacy: return "pills.fill"
        case .homeCare: return "house.fill"
        case .emergency: return "exclamationmark.triangle.fill"
        case .insurance: return "creditcard.fill"
        case .other: return "person.crop.circle"
        }
    }

    static var exportableCategories: [ProviderCategory] {
        [.medical, .facility, .pharmacy, .homeCare, .emergency]
    }
}

// MARK: - Provider Models

struct ProviderGroup: Identifiable {
    let id = UUID()
    let category: ProviderCategory
    let providers: [Provider]
}

struct Provider: Identifiable {
    let id: String
    let name: String
    let subtitle: String?
    let phone: String?
    let email: String?
    let address: String?
    let organization: String?
    let binderItemId: String
    let category: ProviderCategory
    let updatedAt: Date

    init(from item: BinderItem) {
        self.id = item.id
        self.binderItemId = item.id
        self.name = item.title
        self.updatedAt = item.updatedAt

        // Parse content based on type
        switch item.type {
        case .contact:
            if let content = try? JSONDecoder().decode(ContactContent.self, from: Data(item.contentJson.utf8)) {
                self.subtitle = content.role.displayName
                self.phone = content.phone
                self.email = content.email
                self.address = content.address
                self.organization = content.organization
                self.category = Self.categorizeContact(content)
            } else {
                self.subtitle = nil
                self.phone = nil
                self.email = nil
                self.address = nil
                self.organization = nil
                self.category = .other
            }

        case .facility:
            if let content = try? JSONDecoder().decode(FacilityContent.self, from: Data(item.contentJson.utf8)) {
                self.subtitle = content.type.displayName
                self.phone = content.phone
                self.email = nil
                self.address = content.address
                self.organization = nil
                self.category = .facility
            } else {
                self.subtitle = nil
                self.phone = nil
                self.email = nil
                self.address = nil
                self.organization = nil
                self.category = .facility
            }

        case .insurance:
            if let content = try? JSONDecoder().decode(InsuranceContent.self, from: Data(item.contentJson.utf8)) {
                self.subtitle = content.planName
                self.phone = content.phone
                self.email = nil
                self.address = nil
                self.organization = content.provider
                self.category = .insurance
            } else {
                self.subtitle = nil
                self.phone = nil
                self.email = nil
                self.address = nil
                self.organization = nil
                self.category = .insurance
            }

        default:
            self.subtitle = nil
            self.phone = nil
            self.email = nil
            self.address = nil
            self.organization = nil
            self.category = .other
        }
    }

    private static func categorizeContact(_ content: ContactContent) -> ProviderCategory {
        switch content.role {
        case .doctor, .nurse:
            return .medical
        case .socialWorker:
            return .homeCare
        case .family:
            return .emergency
        case .other:
            if content.organization?.lowercased().contains("pharmacy") == true {
                return .pharmacy
            }
            return .medical
        }
    }
}

// MARK: - Export Models

struct CareNetworkExport: Identifiable {
    let id: String
    let pdfURL: URL
    let providerCount: Int
    let shareLink: ShareLink?
    let createdAt: Date
}

struct ShareLink {
    let token: String
    let url: String
    let expiresAt: Date

    var isExpired: Bool {
        expiresAt < Date()
    }

    var formattedExpiry: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: expiresAt)
    }
}

struct ProviderNote: Identifiable {
    let id: String
    let binderItemId: String
    let authorId: String
    let note: String
    let rating: Int?
    let createdAt: Date
    let updatedAt: Date
}

// MARK: - Errors

enum CareNetworkError: Error, LocalizedError {
    case exportFailed(String)
    case shareCreationFailed
    case invalidResponse
    case featureGated

    var errorDescription: String? {
        switch self {
        case .exportFailed(let message):
            return "Export failed: \(message)"
        case .shareCreationFailed:
            return "Failed to create share link"
        case .invalidResponse:
            return "Invalid response from server"
        case .featureGated:
            return "This feature requires a Plus or Family subscription"
        }
    }
}
