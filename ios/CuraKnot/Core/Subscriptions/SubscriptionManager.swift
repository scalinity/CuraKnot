import Foundation
import StoreKit
import os

// MARK: - Notifications

extension Notification.Name {
    static let subscriptionDidChange = Notification.Name("com.curaknot.subscriptionDidChange")
}

// MARK: - Subscription Plan

enum SubscriptionPlan: String, Codable {
    case free = "FREE"
    case plus = "PLUS"
    case family = "FAMILY"

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .plus: return "Plus"
        case .family: return "Family"
        }
    }
}

// MARK: - Feature Access

enum PremiumFeature: String {
    case appointmentQuestions = "appointment_questions"
    case aiQuestionGeneration = "ai_question_generation"
    case coachChat = "coach_chat"
    case documentScanner = "document_scanner"
    case medReconciliation = "med_reconciliation"
    case shiftMode = "shift_mode"
    case operationalInsights = "operational_insights"
    case dischargeWizard = "discharge_wizard"
    case facilityCommunicationLog = "facility_communication_log"
    case facilityLogAISuggestions = "facility_log_ai_suggestions"
    case conditionPhotoTracking = "condition_photo_tracking"
    case conditionPhotoCompare = "condition_photo_compare"
    case conditionPhotoShare = "condition_photo_share"
    case familyMeetings = "family_meetings"
    case transportation = "transportation"
    case transportationAnalytics = "transportation_analytics"
    case familyVideoBoard = "family_video_board"
    case handoffTranslation = "handoff_translation"
    case customGlossary = "custom_glossary"
    case legalVault = "legal_vault"
    case legalVaultUnlimited = "legal_vault_unlimited"
    case careCostTracking = "care_cost_tracking"
    case careCostProjections = "care_cost_projections"
    case careCostExport = "care_cost_export"
    case respiteFinder = "respite_finder"
    case respiteRequests = "respite_requests"
    case respiteReviews = "respite_reviews"
    case respiteTracking = "respite_tracking"
    case respiteReminders = "respite_reminders"
}

// MARK: - Subscription Manager

@MainActor
final class SubscriptionManager: ObservableObject {
    // MARK: - Published State

    @Published private(set) var currentPlan: SubscriptionPlan = .free
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var subscriptionStatus: Product.SubscriptionInfo.Status?
    @Published private(set) var expirationDate: Date?

    // MARK: - Product IDs

    static let productIDs: Set<String> = [
        "com.curaknot.plus.monthly",
        "com.curaknot.plus.yearly",
        "com.curaknot.family.monthly",
        "com.curaknot.family.yearly"
    ]

    // MARK: - Dependencies

    private let supabaseClient: SupabaseClient
    private var transactionListener: Task<Void, Error>?

    // MARK: - Initialization

    init(supabaseClient: SupabaseClient) {
        self.supabaseClient = supabaseClient

        // Start listening for transactions
        transactionListener = listenForTransactions()

        // Load products on init
        Task {
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Feature Access

    /// Check if the current plan has access to a feature
    func hasFeature(_ feature: PremiumFeature) -> Bool {
        switch feature {
        case .appointmentQuestions:
            // All tiers can view questions, but AI generation requires Plus+
            return true
        case .aiQuestionGeneration:
            return currentPlan != .free
        case .coachChat:
            return currentPlan != .free
        case .documentScanner:
            return currentPlan != .free
        case .medReconciliation:
            return currentPlan != .free
        case .shiftMode:
            return currentPlan == .family
        case .operationalInsights:
            return currentPlan == .family
        case .dischargeWizard:
            return currentPlan != .free
        case .facilityCommunicationLog:
            return currentPlan != .free
        case .facilityLogAISuggestions:
            return currentPlan == .family
        case .conditionPhotoTracking:
            return currentPlan != .free // Plus and Family
        case .conditionPhotoCompare:
            return currentPlan == .family // Family only
        case .conditionPhotoShare:
            return currentPlan == .family // Family only
        case .familyMeetings:
            return currentPlan != .free // Plus (basic) and Family (full features)
        case .transportation:
            return currentPlan != .free // Plus and Family
        case .transportationAnalytics:
            return currentPlan == .family // Family only
        case .familyVideoBoard:
            return currentPlan != .free // Plus and Family (FREE is locked out)
        case .handoffTranslation:
            return currentPlan != .free // Plus and Family
        case .customGlossary:
            return currentPlan == .family // Family only
        case .legalVault:
            return currentPlan != .free // Plus (5 docs) and Family (unlimited)
        case .legalVaultUnlimited:
            return currentPlan == .family // Family only
        case .careCostTracking:
            return currentPlan != .free // Plus and Family
        case .careCostProjections:
            return currentPlan == .family // Family only
        case .careCostExport:
            return currentPlan == .family // Family only
        case .respiteFinder:
            return true // All tiers can browse directory
        case .respiteRequests:
            return currentPlan != .free // Plus and Family
        case .respiteReviews:
            return currentPlan != .free // Plus and Family
        case .respiteTracking:
            return currentPlan == .family // Family only
        case .respiteReminders:
            return currentPlan == .family // Family only
        }
    }

    /// Check if AI question generation is available
    var canGenerateAIQuestions: Bool {
        hasFeature(.aiQuestionGeneration)
    }

    /// Check if user should see preview-only content (FREE tier)
    var isPreviewOnly: Bool {
        currentPlan == .free
    }

    /// Check if user has premium (Plus or Family)
    var isPremium: Bool {
        currentPlan != .free
    }

    // MARK: - Product Loading

    func loadProducts() async {
        do {
            products = try await Product.products(for: Self.productIDs)
        } catch {
            Self.logger.error("Failed to load products: \(error.localizedDescription)")
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updateSubscriptionStatus()
            await syncSubscriptionToBackend(transaction: transaction)
            await transaction.finish()

        case .userCancelled:
            throw SubscriptionError.cancelled

        case .pending:
            throw SubscriptionError.pending

        @unknown default:
            throw SubscriptionError.unknown
        }
    }

    // MARK: - Restore

    func restorePurchases() async throws {
        try await AppStore.sync()
        await updateSubscriptionStatus()
    }

    // MARK: - Subscription Loading

    func loadSubscription() async {
        isLoading = true
        defer { isLoading = false }

        // First check StoreKit
        await updateSubscriptionStatus()

        // Then verify with backend
        do {
            let result: SubscriptionResponse = try await supabaseClient.rpc(
                "get_user_subscription",
                params: [:]
            )
            // Use backend as source of truth if StoreKit says free
            // but backend has active subscription (e.g., employer benefit)
            if currentPlan == .free && result.plan != .free {
                currentPlan = result.plan
            }
        } catch {
            // Keep StoreKit-derived plan on backend error
            Self.logger.error("Failed to load subscription from backend: \(error.localizedDescription)")
        }
    }

    func refreshSubscription() async {
        await loadSubscription()
    }

    // MARK: - Transaction Listener

    private static let logger = Logger(subsystem: "com.curaknot.app", category: "SubscriptionManager")

    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    await self.updateSubscriptionStatus()
                    await self.syncSubscriptionToBackend(transaction: transaction)
                    await transaction.finish()
                } catch {
                    // Always finish the transaction even if verification fails,
                    // to prevent StoreKit from re-delivering it indefinitely.
                    if case .verified(let tx) = result {
                        await tx.finish()
                    }
                    Self.logger.error("Transaction verification failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Subscription Status

    private func updateSubscriptionStatus() async {
        var highestPlan: SubscriptionPlan = .free
        var latestExpiration: Date?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }

            if transaction.revocationDate == nil {
                let plan = planForProductID(transaction.productID)
                if planPriority(plan) > planPriority(highestPlan) {
                    highestPlan = plan
                }

                if let expiration = transaction.expirationDate {
                    if latestExpiration == nil || expiration > latestExpiration! {
                        latestExpiration = expiration
                    }
                }

                purchasedProductIDs.insert(transaction.productID)
            }
        }

        // Post notification if plan changed
        let planChanged = currentPlan != highestPlan
        
        currentPlan = highestPlan
        expirationDate = latestExpiration

        if planChanged {
            NotificationCenter.default.post(name: .subscriptionDidChange, object: nil)
        }
    }

    private func planForProductID(_ productID: String) -> SubscriptionPlan {
        if productID.contains("family") {
            return .family
        } else if productID.contains("plus") {
            return .plus
        }
        return .free
    }

    private func planPriority(_ plan: SubscriptionPlan) -> Int {
        switch plan {
        case .free: return 0
        case .plus: return 1
        case .family: return 2
        }
    }

    // MARK: - Verification

    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Backend Sync

    private func syncSubscriptionToBackend(transaction: Transaction) async {
        do {
            let plan = planForProductID(transaction.productID)
            try await supabaseClient.rpc(
                "sync_apple_subscription",
                params: [
                    "p_plan": plan.rawValue,
                    "p_product_id": transaction.productID,
                    "p_transaction_id": String(transaction.id),
                    "p_expiration": transaction.expirationDate?.ISO8601Format() ?? ""
                ]
            )
        } catch {
            Self.logger.error("Failed to sync subscription to backend: \(error.localizedDescription)")
        }
    }
}

// MARK: - Response Types

private struct SubscriptionResponse: Decodable {
    let plan: SubscriptionPlan
    let validUntil: Date?

    enum CodingKeys: String, CodingKey {
        case plan
        case validUntil = "valid_until"
    }
}

// MARK: - Errors

enum SubscriptionError: LocalizedError {
    case cancelled
    case pending
    case verificationFailed
    case unknown

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Purchase was cancelled."
        case .pending:
            return "Purchase is pending approval."
        case .verificationFailed:
            return "Purchase verification failed."
        case .unknown:
            return "An unknown error occurred."
        }
    }
}
