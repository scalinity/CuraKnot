import XCTest
@testable import CuraKnot

final class RespiteFinderTests: XCTestCase {

    // MARK: - Model Tests

    func testRespiteProviderDecoding() throws {
        let json = """
        {
            "id": "test-provider-1",
            "name": "Sunrise Adult Day Center",
            "providerType": "ADULT_DAY",
            "description": "Quality adult day care",
            "address": "123 Main St",
            "city": "San Francisco",
            "state": "CA",
            "zipCode": "94102",
            "latitude": 37.78,
            "longitude": -122.42,
            "phone": "415-555-0100",
            "email": "info@sunrise.example.com",
            "website": "https://sunrise.example.com",
            "pricingModel": "DAILY",
            "priceMin": 80,
            "priceMax": 120,
            "acceptsMedicaid": true,
            "acceptsMedicare": false,
            "scholarshipsAvailable": true,
            "services": ["Personal Care", "Meals", "Activities"],
            "verificationStatus": "VERIFIED",
            "avgRating": 4.5,
            "reviewCount": 12,
            "distanceMiles": 3.2
        }
        """.data(using: .utf8)!

        let provider = try JSONDecoder().decode(RespiteProvider.self, from: json)
        XCTAssertEqual(provider.id, "test-provider-1")
        XCTAssertEqual(provider.name, "Sunrise Adult Day Center")
        XCTAssertEqual(provider.providerType, .adultDay)
        XCTAssertEqual(provider.city, "San Francisco")
        XCTAssertEqual(provider.state, "CA")
        XCTAssertTrue(provider.acceptsMedicaid)
        XCTAssertFalse(provider.acceptsMedicare)
        XCTAssertTrue(provider.scholarshipsAvailable)
        XCTAssertEqual(provider.services.count, 3)
        XCTAssertEqual(provider.verificationStatus, .verified)
        XCTAssertEqual(provider.avgRating, 4.5)
        XCTAssertEqual(provider.reviewCount, 12)
        XCTAssertEqual(provider.distanceMiles, 3.2)
    }

    func testRespiteProviderFormattedDistance() {
        var provider = makeProvider()
        provider.distanceMiles = 0.5
        XCTAssertEqual(provider.formattedDistance, "0.5 mi")

        provider.distanceMiles = 5.0
        XCTAssertEqual(provider.formattedDistance, "5 mi")

        provider.distanceMiles = nil
        XCTAssertNil(provider.formattedDistance)
    }

    func testRespiteProviderFormattedPriceRange() {
        var provider = makeProvider()
        provider.pricingModel = .free
        XCTAssertEqual(provider.formattedPriceRange, "Free")

        provider.pricingModel = .sliding
        XCTAssertEqual(provider.formattedPriceRange, "Sliding Scale")

        provider.pricingModel = .daily
        provider.priceMin = 80
        provider.priceMax = 120
        let price = provider.formattedPriceRange
        XCTAssertNotNil(price)
        XCTAssertTrue(price!.contains("daily"))
    }

    func testRespiteProviderHasFinancialAssistance() {
        var provider = makeProvider()
        provider.acceptsMedicaid = false
        provider.acceptsMedicare = false
        provider.scholarshipsAvailable = false
        XCTAssertFalse(provider.hasFinancialAssistance)

        provider.acceptsMedicaid = true
        XCTAssertTrue(provider.hasFinancialAssistance)
    }

    func testProviderTypeDisplayNames() {
        XCTAssertEqual(RespiteProvider.ProviderType.adultDay.displayName, "Adult Day Care")
        XCTAssertEqual(RespiteProvider.ProviderType.inHome.displayName, "In-Home Care")
        XCTAssertEqual(RespiteProvider.ProviderType.overnight.displayName, "Overnight Care")
        XCTAssertEqual(RespiteProvider.ProviderType.volunteer.displayName, "Volunteer")
        XCTAssertEqual(RespiteProvider.ProviderType.emergency.displayName, "Emergency")
    }

    func testProviderTypeIcons() {
        XCTAssertEqual(RespiteProvider.ProviderType.adultDay.icon, "sun.max.fill")
        XCTAssertEqual(RespiteProvider.ProviderType.inHome.icon, "house.fill")
        XCTAssertEqual(RespiteProvider.ProviderType.overnight.icon, "moon.fill")
    }

    // MARK: - Review Model Tests

    func testRespiteReviewDecoding() throws {
        let json = """
        {
            "id": "review-1",
            "provider_id": "provider-1",
            "circle_id": "circle-1",
            "reviewer_id": "user-1",
            "rating": 4,
            "title": "Great service",
            "body": "Very helpful staff",
            "service_date": "2026-01-15",
            "created_at": "2026-01-20T10:00:00Z",
            "updated_at": "2026-01-20T10:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let review = try decoder.decode(RespiteReview.self, from: json)
        XCTAssertEqual(review.id, "review-1")
        XCTAssertEqual(review.rating, 4)
        XCTAssertEqual(review.title, "Great service")
        XCTAssertEqual(review.ratingStars, "★★★★☆")
    }

    func testRatingStarsString() {
        let review1 = RespiteReview(
            id: "1", providerId: "p1", circleId: "c1", reviewerId: "u1",
            rating: 5, title: nil, body: nil, serviceDate: nil,
            createdAt: Date(), updatedAt: Date()
        )
        XCTAssertEqual(review1.ratingStars, "★★★★★")

        let review2 = RespiteReview(
            id: "2", providerId: "p1", circleId: "c1", reviewerId: "u1",
            rating: 1, title: nil, body: nil, serviceDate: nil,
            createdAt: Date(), updatedAt: Date()
        )
        XCTAssertEqual(review2.ratingStars, "★☆☆☆☆")
    }

    // MARK: - Request Model Tests

    func testRequestStatusProperties() {
        XCTAssertEqual(RespiteRequest.RequestStatus.pending.displayName, "Pending")
        XCTAssertEqual(RespiteRequest.RequestStatus.confirmed.displayName, "Confirmed")
        XCTAssertEqual(RespiteRequest.RequestStatus.declined.displayName, "Declined")
        XCTAssertEqual(RespiteRequest.RequestStatus.cancelled.displayName, "Cancelled")
        XCTAssertEqual(RespiteRequest.RequestStatus.completed.displayName, "Completed")

        XCTAssertEqual(RespiteRequest.RequestStatus.pending.icon, "clock.fill")
        XCTAssertEqual(RespiteRequest.RequestStatus.confirmed.icon, "checkmark.circle.fill")
    }

    func testContactMethodProperties() {
        XCTAssertEqual(RespiteRequest.ContactMethod.phone.displayName, "Phone")
        XCTAssertEqual(RespiteRequest.ContactMethod.email.displayName, "Email")
    }

    // MARK: - Log Entry Tests

    func testRespiteLogEntryDateRange() {
        let entry = RespiteLogEntry(
            id: "log-1", circleId: "c1", patientId: "p1", createdBy: "u1",
            providerType: "IN_HOME", providerName: "Home Care Co",
            startDate: "2026-01-01", endDate: "2026-01-03", totalDays: 3,
            notes: "Good experience", createdAt: Date()
        )
        XCTAssertEqual(entry.dateRange, "2026-01-01 – 2026-01-03")
        XCTAssertEqual(entry.totalDays, 3)
    }

    // MARK: - Search Request Tests

    func testProviderSearchRequestEncoding() throws {
        let request = ProviderSearchRequest(
            latitude: 37.7749,
            longitude: -122.4194,
            radiusMiles: 50,
            providerType: "ADULT_DAY",
            minRating: 3.0,
            verifiedOnly: true
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(ProviderSearchRequest.self, from: data)
        XCTAssertEqual(decoded.latitude, 37.7749)
        XCTAssertEqual(decoded.longitude, -122.4194)
        XCTAssertEqual(decoded.radiusMiles, 50)
        XCTAssertEqual(decoded.providerType, "ADULT_DAY")
        XCTAssertEqual(decoded.minRating, 3.0)
        XCTAssertEqual(decoded.verifiedOnly, true)
    }

    // MARK: - Error Tests

    func testRespiteFinderErrorDescriptions() {
        XCTAssertEqual(RespiteFinderError.notAuthenticated.errorDescription, "You must be signed in.")
        XCTAssertEqual(RespiteFinderError.featureNotAvailable.errorDescription, "Upgrade your plan to access this feature.")
        XCTAssertEqual(RespiteFinderError.upgradeRequired.errorDescription, "This feature requires a Plus or Family subscription.")
        XCTAssertEqual(RespiteFinderError.notAuthorized.errorDescription, "You are not authorized to perform this action.")
        XCTAssertEqual(RespiteFinderError.notFound.errorDescription, "The requested resource was not found.")

        let validationError = RespiteFinderError.validationError("Test error")
        XCTAssertEqual(validationError.errorDescription, "Test error")
    }

    // MARK: - Verification Status Tests

    func testVerificationStatusIcon() {
        XCTAssertNil(RespiteProvider.VerificationStatus.unverified.icon)
        XCTAssertEqual(RespiteProvider.VerificationStatus.verified.icon, "checkmark.seal.fill")
        XCTAssertEqual(RespiteProvider.VerificationStatus.featured.icon, "star.fill")
    }

    // MARK: - Pricing Model Tests

    func testPricingModelDisplayNames() {
        XCTAssertEqual(RespiteProvider.PricingModel.hourly.displayName, "Hourly")
        XCTAssertEqual(RespiteProvider.PricingModel.daily.displayName, "Daily")
        XCTAssertEqual(RespiteProvider.PricingModel.weekly.displayName, "Weekly")
        XCTAssertEqual(RespiteProvider.PricingModel.sliding.displayName, "Sliding Scale")
        XCTAssertEqual(RespiteProvider.PricingModel.free.displayName, "Free")
    }

    // MARK: - Helpers

    private func makeProvider() -> RespiteProvider {
        RespiteProvider(
            id: "test-1",
            name: "Test Provider",
            providerType: .adultDay,
            description: nil,
            address: nil,
            city: nil,
            state: nil,
            zipCode: nil,
            latitude: nil,
            longitude: nil,
            phone: nil,
            email: nil,
            website: nil,
            hoursJson: nil,
            pricingModel: nil,
            priceMin: nil,
            priceMax: nil,
            acceptsMedicaid: false,
            acceptsMedicare: false,
            scholarshipsAvailable: false,
            services: [],
            verificationStatus: .unverified,
            avgRating: 0,
            reviewCount: 0,
            distanceMiles: nil
        )
    }
}
