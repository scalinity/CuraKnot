import SwiftUI

// MARK: - Provider Detail View

struct ProviderDetailView: View {
    let provider: RespiteProvider
    @ObservedObject var service: RespiteFinderService
    let circleId: String?
    let patientId: String?

    @State private var showRequestSheet = false
    @State private var showReviewSheet = false
    @State private var isLoadingReviews = false
    @State private var reviewsError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    headerSection

                    Divider()

                    // Contact Info
                    contactSection

                    // Services
                    if !provider.services.isEmpty {
                        servicesSection
                    }

                    // Pricing
                    pricingSection

                    Divider()

                    // Reviews
                    reviewsSection

                    // Request Button
                    if service.canSubmitRequests {
                        requestButton
                    } else {
                        upgradePrompt
                    }
                }
                .padding()
            }
            .navigationTitle(provider.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .sheet(isPresented: $showRequestSheet) {
                if let circleId = circleId, let patientId = patientId {
                    RespiteRequestSheet(
                        service: service,
                        provider: provider,
                        circleId: circleId,
                        patientId: patientId
                    )
                }
            }
            .sheet(isPresented: $showReviewSheet) {
                WriteReviewSheet(
                    service: service,
                    provider: provider,
                    circleId: circleId
                )
            }
            .task {
                await loadReviews()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(provider.providerType.displayName, systemImage: provider.providerType.icon)
                    .font(.subheadline)
                    .foregroundStyle(.blue)

                Spacer()

                if let icon = provider.verificationStatus.icon {
                    Label(provider.verificationStatus.displayName, systemImage: icon)
                        .font(.caption)
                        .foregroundStyle(provider.verificationStatus == .featured ? .yellow : .blue)
                }
            }

            if let desc = provider.description {
                Text(desc)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                if provider.reviewCount > 0 {
                    HStack(spacing: 4) {
                        RatingStars(rating: Int(provider.avgRating.rounded()), maxRating: 5, size: 14)
                        Text(String(format: "%.1f", provider.avgRating))
                            .font(.subheadline)
                            .bold()
                        Text(provider.reviewCount == 1 ? String(localized: "(1 review)") : String(localized: "(\(provider.reviewCount) reviews)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(String(localized: "No reviews yet"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let distance = provider.formattedDistance {
                    HStack(spacing: 2) {
                        Image(systemName: "location")
                            .font(.caption)
                        Text(distance)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Contact

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Contact"))
                .font(.headline)

            if let address = provider.address {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text(address)
                        if let city = provider.city, let state = provider.state, let zip = provider.zipCode {
                            Text("\(city), \(state) \(zip)")
                        }
                    }
                    .font(.subheadline)
                }
            }

            if service.canSubmitRequests {
                // PLUS and FAMILY tiers see full contact details
                if let phone = provider.phone,
                   let phoneURL = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                    HStack(spacing: 8) {
                        Image(systemName: "phone")
                            .foregroundStyle(.secondary)
                        Link(phone, destination: phoneURL)
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Call \(provider.name) at \(phone)"))
                }

                if let email = provider.email,
                   let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let emailURL = URL(string: "mailto:\(encodedEmail)") {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope")
                            .foregroundStyle(.secondary)
                        Link(email, destination: emailURL)
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Email \(provider.name) at \(email)"))
                }

                if let website = provider.website,
                   let url = URL(string: website),
                   let scheme = url.scheme?.lowercased(),
                   scheme == "https" || scheme == "http" {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                            .foregroundStyle(.secondary)
                        Link(String(localized: "Visit Website"), destination: url)
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Visit \(provider.name) website"))
                }
            } else if provider.phone != nil || provider.email != nil || provider.website != nil {
                // FREE tier sees upgrade prompt for contact info
                Text(String(localized: "Upgrade to Plus to see contact details"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }

    // MARK: - Services

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Services"))
                .font(.headline)

            FlowLayout(spacing: 6) {
                ForEach(provider.services, id: \.self) { svc in
                    Text(svc)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Pricing

    private var pricingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Pricing"))
                .font(.headline)

            if let price = provider.formattedPriceRange {
                Text(price)
                    .font(.subheadline)
            } else {
                Text(String(localized: "Contact for pricing"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if provider.hasFinancialAssistance {
                VStack(alignment: .leading, spacing: 4) {
                    if provider.acceptsMedicaid {
                        Label(String(localized: "Accepts Medicaid"), systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    if provider.acceptsMedicare {
                        Label(String(localized: "Accepts Medicare"), systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    if provider.scholarshipsAvailable {
                        Label(String(localized: "Scholarships Available"), systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    // MARK: - Reviews

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "Reviews"))
                    .font(.headline)
                Spacer()
                if service.canWriteReviews {
                    Button(String(localized: "Write Review")) {
                        showReviewSheet = true
                    }
                    .font(.subheadline)
                }
            }

            if isLoadingReviews {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if let error = reviewsError {
                Button {
                    Task { await loadReviews() }
                } label: {
                    Label(error, systemImage: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(.vertical, 8)
            } else if service.selectedProviderReviews.isEmpty {
                Text(String(localized: "No reviews yet. Be the first!"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(service.selectedProviderReviews) { review in
                    ReviewRow(review: review)
                }
            }
        }
    }

    // MARK: - Request Button

    private var requestButton: some View {
        Button {
            showRequestSheet = true
        } label: {
            HStack {
                Image(systemName: "calendar.badge.plus")
                Text(String(localized: "Check Availability"))
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(circleId == nil || patientId == nil)
    }

    // MARK: - Upgrade Prompt

    private var upgradePrompt: some View {
        VStack(spacing: 8) {
            Text(String(localized: "Upgrade to request availability"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(String(localized: "Plus and Family plans can contact providers directly."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Load Reviews

    private func loadReviews() async {
        isLoadingReviews = true
        reviewsError = nil
        defer { isLoadingReviews = false }
        do {
            try await service.fetchReviews(providerId: provider.id)
        } catch {
            reviewsError = String(localized: "Failed to load reviews. Tap to retry.")
        }
    }
}

// MARK: - Review Row

private struct ReviewRow: View {
    let review: RespiteReview

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                RatingStars(rating: review.rating, maxRating: 5, size: 12)
                Spacer()
                Text(review.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let title = review.title {
                Text(title)
                    .font(.subheadline)
                    .bold()
            }

            if let body = review.body {
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let name = review.reviewerName {
                Text("— \(name)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Write Review Sheet

private struct WriteReviewSheet: View {
    let service: RespiteFinderService
    let provider: RespiteProvider
    let circleId: String?

    @State private var rating = 0
    @State private var title = ""
    @State private var reviewBody = ""
    @State private var serviceDate = Date()
    @State private var includeDate = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Rating")) {
                    RatingStars(rating: rating, maxRating: 5, size: 28) { newRating in
                        rating = newRating
                    }
                }

                Section {
                    Text(String(localized: "Do not include patient names, diagnoses, or medical details in your review."))
                        .font(.caption)
                        .foregroundStyle(.orange)
                    TextField(String(localized: "Title (optional)"), text: $title)
                    TextEditor(text: $reviewBody)
                        .frame(minHeight: 100)
                } header: {
                    Text(String(localized: "Review"))
                }

                Section(String(localized: "Service Date")) {
                    Toggle(String(localized: "Include service date"), isOn: $includeDate)
                    if includeDate {
                        DatePicker(String(localized: "Date"), selection: $serviceDate, displayedComponents: .date)
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(String(localized: "Write Review"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Submit")) {
                        Task { await submitReview() }
                    }
                    .bold()
                    .disabled(rating == 0 || isSubmitting)
                }
            }
            .interactiveDismissDisabled(isSubmitting)
        }
    }

    private func submitReview() async {
        guard !isSubmitting else { return }
        guard let circleId = circleId else {
            errorMessage = String(localized: "No circle selected.")
            return
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await service.submitReview(
                providerId: provider.id,
                circleId: circleId,
                rating: rating,
                title: title.isEmpty ? nil : title,
                body: reviewBody.isEmpty ? nil : reviewBody,
                serviceDate: includeDate ? Self.dateFormatter.string(from: serviceDate) : nil
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = flowLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = flowLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func flowLayout(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxHeight = max(maxHeight, y + rowHeight)
        }

        return (positions, CGSize(width: maxWidth, height: maxHeight))
    }
}
