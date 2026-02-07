import SwiftUI
import StoreKit

// MARK: - Paywall View

struct PaywallView: View {
    @EnvironmentObject var dependencyContainer: DependencyContainer
    @Environment(\.dismiss) var dismiss

    @State private var selectedPlan: CuraKnotPlan = .plus
    @State private var selectedBillingPeriod: BillingPeriod = .yearly
    @State private var isPurchasing = false
    @State private var error: Error?
    @State private var showError = false
    @State private var products: [Product] = []
    @State private var isLoadingProducts = true

    private var subscriptionManager: SubscriptionManager {
        dependencyContainer.subscriptionManager
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Header with gradient
                    headerSection

                    // Plan selection
                    planSelectionSection

                    // Billing toggle
                    billingPeriodSection

                    // Features list
                    featuresSection

                    // Subscribe button
                    subscribeButton

                    // Restore purchases
                    restoreButton

                    // Terms
                    termsSection

                    Spacer(minLength: 32)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .alert("Purchase Error", isPresented: $showError, presenting: error) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.localizedDescription)
            }
            .task {
                await loadProducts()
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Icon with gradient background
            ZStack {
                SwiftUI.Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.teal, Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)

                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.white)
            }

            Text("CuraKnot Premium")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Care coordination made simple")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    // MARK: - Plan Selection

    private var planSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Your Plan")
                .font(.headline)
                .padding(.leading, 4)

            // Plus Plan
            PaywallPlanCard(
                plan: .plus,
                isSelected: selectedPlan == .plus,
                price: priceForPlan(.plus),
                billingPeriod: selectedBillingPeriod,
                onSelect: { selectedPlan = .plus }
            )

            // Family Plan (Best Value)
            PaywallPlanCard(
                plan: .family,
                isSelected: selectedPlan == .family,
                price: priceForPlan(.family),
                billingPeriod: selectedBillingPeriod,
                showBestValue: true,
                onSelect: { selectedPlan = .family }
            )
        }
    }

    // MARK: - Billing Period

    private var billingPeriodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Billing Period")
                .font(.headline)
                .padding(.leading, 4)

            HStack(spacing: 12) {
                PaywallBillingButton(
                    period: .monthly,
                    isSelected: selectedBillingPeriod == .monthly,
                    onSelect: { selectedBillingPeriod = .monthly }
                )

                PaywallBillingButton(
                    period: .yearly,
                    isSelected: selectedBillingPeriod == .yearly,
                    savings: "Save 40%",
                    onSelect: { selectedBillingPeriod = .yearly }
                )
            }
        }
    }

    // MARK: - Features Section

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What You Get")
                .font(.headline)
                .padding(.leading, 4)

            VStack(spacing: 12) {
                // Core features (both plans)
                PaywallFeatureRow(
                    icon: "waveform.badge.mic",
                    iconColor: .blue,
                    title: "Unlimited Voice Handoffs",
                    description: "Capture and share care updates effortlessly"
                )

                PaywallFeatureRow(
                    icon: "bubble.left.and.bubble.right.fill",
                    iconColor: .teal,
                    title: "AI Care Coach",
                    description: selectedPlan == .plus ? "50 messages/month" : "Unlimited messages"
                )

                PaywallFeatureRow(
                    icon: "doc.text.viewfinder",
                    iconColor: .purple,
                    title: "Document Scanner",
                    description: "Scan medications, insurance cards & more"
                )

                PaywallFeatureRow(
                    icon: "calendar.badge.clock",
                    iconColor: .orange,
                    title: "Calendar Sync",
                    description: "Two-way calendar integration"
                )

                PaywallFeatureRow(
                    icon: "applewatch",
                    iconColor: .pink,
                    title: "Apple Watch App",
                    description: "Quick updates from your wrist"
                )

                // Family-only features
                if selectedPlan == .family {
                    Divider()
                        .padding(.vertical, 4)

                    PaywallFeatureRow(
                        icon: "person.3.fill",
                        iconColor: .green,
                        title: "Up to 20 Circle Members",
                        description: "Coordinate with your entire care team"
                    )

                    PaywallFeatureRow(
                        icon: "clock.badge.checkmark.fill",
                        iconColor: .indigo,
                        title: "Shift Handoff Mode",
                        description: "Perfect for professional caregivers"
                    )

                    PaywallFeatureRow(
                        icon: "chart.line.uptrend.xyaxis",
                        iconColor: .mint,
                        title: "Operational Insights",
                        description: "Track patterns and trends"
                    )
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(16)
        }
    }

    // MARK: - Subscribe Button

    private var subscribeButton: some View {
        Button {
            purchase()
        } label: {
            HStack(spacing: 8) {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Start \(selectedPlan.displayName)")
                        .fontWeight(.semibold)

                    if let price = priceForPlan(selectedPlan) {
                        Text("— \(price)/\(selectedBillingPeriod.shortLabel)")
                            .fontWeight(.medium)
                            .opacity(0.9)
                    }
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color.teal, Color.blue],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundStyle(.white)
            .cornerRadius(14)
            .shadow(color: .teal.opacity(0.3), radius: 8, y: 4)
        }
        .disabled(isPurchasing || isLoadingProducts)
        .accessibilityLabel("Subscribe to \(selectedPlan.displayName) for \(priceForPlan(selectedPlan) ?? "loading")")
        .accessibilityHint("Double tap to start subscription")
    }

    // MARK: - Restore Button

    private var restoreButton: some View {
        Button("Restore Purchases") {
            restorePurchases()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Restore previous purchases")
    }

    // MARK: - Terms Section

    private var termsSection: some View {
        VStack(spacing: 8) {
            Text("Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. You can manage your subscription in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Terms of Service", destination: URL(string: "https://curaknot.com/terms")!)
                Link("Privacy Policy", destination: URL(string: "https://curaknot.com/privacy")!)
            }
            .font(.caption)
        }
    }

    // MARK: - Helpers

    private func priceForPlan(_ plan: CuraKnotPlan) -> String? {
        let productId = productId(for: plan)
        if let product = products.first(where: { $0.id == productId }) {
            return product.displayPrice
        }
        // Fallback prices for UI preview
        switch (plan, selectedBillingPeriod) {
        case (.plus, .monthly): return "$9.99"
        case (.plus, .yearly): return "$71.99"
        case (.family, .monthly): return "$19.99"
        case (.family, .yearly): return "$143.99"
        default: return nil
        }
    }

    private func productId(for plan: CuraKnotPlan) -> String {
        switch (plan, selectedBillingPeriod) {
        case (.plus, .monthly): return "com.curaknot.plus.monthly"
        case (.plus, .yearly): return "com.curaknot.plus.yearly"
        case (.family, .monthly): return "com.curaknot.family.monthly"
        case (.family, .yearly): return "com.curaknot.family.yearly"
        default: return ""
        }
    }

    private func loadProducts() async {
        isLoadingProducts = true
        do {
            let productIds = [
                "com.curaknot.plus.monthly",
                "com.curaknot.plus.yearly",
                "com.curaknot.family.monthly",
                "com.curaknot.family.yearly"
            ]
            products = try await Product.products(for: productIds)
        } catch {
            #if DEBUG
            print("Failed to load products: \(error)")
            #endif
        }
        isLoadingProducts = false
    }

    private func purchase() {
        let productId = productId(for: selectedPlan)
        guard let product = products.first(where: { $0.id == productId }) else {
            self.error = PaywallError.productNotFound
            showError = true
            return
        }

        isPurchasing = true
        Task {
            do {
                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    switch verification {
                    case .verified:
                        await subscriptionManager.refreshSubscription()
                        await MainActor.run {
                            dismiss()
                        }
                    case .unverified:
                        throw PaywallError.verificationFailed
                    }
                case .userCancelled:
                    break // User cancelled, don't show error
                case .pending:
                    // Transaction pending approval
                    break
                @unknown default:
                    break
                }
            } catch let error as PaywallError {
                self.error = error
                showError = true
            } catch {
                self.error = error
                showError = true
            }
            isPurchasing = false
        }
    }

    private func restorePurchases() {
        isPurchasing = true
        Task {
            do {
                try await AppStore.sync()
                await subscriptionManager.refreshSubscription()
                if subscriptionManager.currentPlan != .free {
                    await MainActor.run {
                        dismiss()
                    }
                }
            } catch {
                self.error = error
                showError = true
            }
            isPurchasing = false
        }
    }
}

// MARK: - Plan Card

struct PaywallPlanCard: View {
    let plan: CuraKnotPlan
    let isSelected: Bool
    var price: String?
    var billingPeriod: BillingPeriod = .monthly
    var showBestValue: Bool = false
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    SwiftUI.Circle()
                        .fill(isSelected ? plan.color.opacity(0.15) : Color(.tertiarySystemFill))
                        .frame(width: 44, height: 44)

                    Image(systemName: plan.iconName)
                        .font(.title3)
                        .foregroundStyle(isSelected ? plan.color : .secondary)
                }

                // Plan info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(plan.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if showBestValue {
                            Text("Best Value")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .foregroundStyle(.white)
                                .cornerRadius(4)
                        }
                    }

                    Text(plan.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Price
                if let price = price {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(price)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("/\(billingPeriod.shortLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? plan.color : Color(.tertiaryLabel))
            }
            .padding()
            .background(
                isSelected
                    ? plan.color.opacity(0.08)
                    : Color(.secondarySystemGroupedBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? plan.color : Color.clear, lineWidth: 2)
            )
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(plan.displayName) plan, \(plan.subtitle)\(showBestValue ? ", Best Value" : "")")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Double tap to select")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Billing Period Button

struct PaywallBillingButton: View {
    let period: BillingPeriod
    let isSelected: Bool
    var savings: String?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                Text(period.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if let savings = savings {
                    Text(savings)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isSelected
                    ? Color.teal.opacity(0.1)
                    : Color(.secondarySystemGroupedBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.teal : Color.clear, lineWidth: 2)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(period.displayName) billing\(savings != nil ? ", \(savings!)" : "")")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Double tap to select")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Feature Row

struct PaywallFeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(description)")
    }
}

// MARK: - Supporting Types

enum CuraKnotPlan: String, CaseIterable {
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

    var subtitle: String {
        switch self {
        case .free: return "Basic care coordination"
        case .plus: return "For individual caregivers"
        case .family: return "For care teams up to 20"
        }
    }

    var iconName: String {
        switch self {
        case .free: return "heart"
        case .plus: return "heart.fill"
        case .family: return "person.3.fill"
        }
    }

    var color: Color {
        switch self {
        case .free: return .secondary
        case .plus: return .teal
        case .family: return .blue
        }
    }
}

enum BillingPeriod: String, CaseIterable {
    case monthly
    case yearly

    var displayName: String {
        switch self {
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    var shortLabel: String {
        switch self {
        case .monthly: return "mo"
        case .yearly: return "yr"
        }
    }
}

enum PaywallError: LocalizedError {
    case productNotFound
    case verificationFailed
    case purchaseFailed

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "Unable to load subscription options. Please try again."
        case .verificationFailed:
            return "Purchase verification failed. Please contact support."
        case .purchaseFailed:
            return "Purchase could not be completed. Please try again."
        }
    }
}

// MARK: - Preview

#Preview {
    PaywallView()
        .environmentObject(DependencyContainer())
}
