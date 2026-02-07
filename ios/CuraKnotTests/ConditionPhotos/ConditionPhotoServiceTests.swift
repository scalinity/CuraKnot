import XCTest
@testable import CuraKnot

@MainActor
final class ConditionPhotoServiceTests: XCTestCase {

    // MARK: - Model Tests

    func testTrackedCondition_decodesFromJSON() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "circle_id": "550e8400-e29b-41d4-a716-446655440001",
            "patient_id": "550e8400-e29b-41d4-a716-446655440002",
            "created_by": "550e8400-e29b-41d4-a716-446655440003",
            "condition_type": "WOUND",
            "body_location": "Left ankle",
            "description": "Surgical incision",
            "status": "ACTIVE",
            "start_date": "2026-01-15T00:00:00Z",
            "require_biometric": true,
            "blur_thumbnails": true,
            "created_at": "2026-01-15T10:30:00Z",
            "updated_at": "2026-01-15T10:30:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let condition = try decoder.decode(TrackedCondition.self, from: json)

        XCTAssertEqual(condition.conditionType, .wound)
        XCTAssertEqual(condition.bodyLocation, "Left ankle")
        XCTAssertEqual(condition.description, "Surgical incision")
        XCTAssertEqual(condition.status, .active)
        XCTAssertTrue(condition.requireBiometric)
        XCTAssertTrue(condition.blurThumbnails)
        XCTAssertTrue(condition.isActive)
    }

    func testConditionPhoto_decodesFromJSON() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440010",
            "condition_id": "550e8400-e29b-41d4-a716-446655440000",
            "circle_id": "550e8400-e29b-41d4-a716-446655440001",
            "patient_id": "550e8400-e29b-41d4-a716-446655440002",
            "created_by": "550e8400-e29b-41d4-a716-446655440003",
            "storage_key": "circle/condition/photo.jpg",
            "thumbnail_key": "circle/condition/photo_thumb.jpg",
            "captured_at": "2026-01-20T14:00:00Z",
            "notes": "Looking better today",
            "lighting_quality": "GOOD",
            "created_at": "2026-01-20T14:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let photo = try decoder.decode(ConditionPhoto.self, from: json)

        XCTAssertEqual(photo.storageKey, "circle/condition/photo.jpg")
        XCTAssertEqual(photo.thumbnailKey, "circle/condition/photo_thumb.jpg")
        XCTAssertEqual(photo.notes, "Looking better today")
        XCTAssertEqual(photo.lightingQuality, .good)
    }

    // MARK: - Condition Type Tests

    func testConditionType_allCasesExist() {
        let types = ConditionType.allCases
        XCTAssertEqual(types.count, 6)
        XCTAssertTrue(types.contains(.wound))
        XCTAssertTrue(types.contains(.rash))
        XCTAssertTrue(types.contains(.swelling))
        XCTAssertTrue(types.contains(.bruise))
        XCTAssertTrue(types.contains(.surgical))
        XCTAssertTrue(types.contains(.other))
    }

    func testConditionType_hasDisplayNameAndIcon() {
        for type in ConditionType.allCases {
            XCTAssertFalse(type.displayName.isEmpty, "Missing displayName for \(type)")
            XCTAssertFalse(type.icon.isEmpty, "Missing icon for \(type)")
        }
    }

    // MARK: - Condition Status Tests

    func testConditionStatus_allCasesExist() {
        let statuses = ConditionStatus.allCases
        XCTAssertEqual(statuses.count, 3)
        XCTAssertTrue(statuses.contains(.active))
        XCTAssertTrue(statuses.contains(.resolved))
        XCTAssertTrue(statuses.contains(.archived))
    }

    func testConditionStatus_hasDisplayName() {
        for status in ConditionStatus.allCases {
            XCTAssertFalse(status.displayName.isEmpty, "Missing displayName for \(status)")
        }
    }

    // MARK: - Lighting Quality Tests

    func testLightingQuality_allCases() {
        let qualities = LightingQuality.allCases
        XCTAssertEqual(qualities.count, 3)

        for quality in qualities {
            XCTAssertFalse(quality.displayName.isEmpty)
            XCTAssertFalse(quality.icon.isEmpty)
        }
    }

    // MARK: - Photo Annotation Tests

    func testPhotoAnnotation_encodesAndDecodes() throws {
        let annotation = PhotoAnnotation(
            type: .circle,
            points: [100, 200, 50],
            color: "red"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(annotation)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PhotoAnnotation.self, from: data)

        XCTAssertEqual(decoded.type, .circle)
        XCTAssertEqual(decoded.points, [100, 200, 50])
        XCTAssertEqual(decoded.color, "red")
    }

    // MARK: - Share Link Response Tests

    func testShareLinkResponse_decodesFromJSON() throws {
        let json = """
        {
            "success": true,
            "share_link_id": "abc123",
            "share_url": "https://example.com/share/abc123",
            "token": "abc123",
            "expires_at": "2026-02-10T00:00:00Z"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ConditionShareLinkResponse.self, from: json)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.shareLinkId, "abc123")
        XCTAssertNotNil(response.shareUrl)
        XCTAssertNotNil(response.token)
    }

    // MARK: - Days Since Start

    func testTrackedCondition_daysSinceStart() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "circle_id": "550e8400-e29b-41d4-a716-446655440001",
            "patient_id": "550e8400-e29b-41d4-a716-446655440002",
            "created_by": "550e8400-e29b-41d4-a716-446655440003",
            "condition_type": "RASH",
            "body_location": "Right arm",
            "status": "ACTIVE",
            "start_date": "\(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86400 * 5)))",
            "require_biometric": true,
            "blur_thumbnails": true,
            "created_at": "2026-01-15T10:30:00Z",
            "updated_at": "2026-01-15T10:30:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let condition = try decoder.decode(TrackedCondition.self, from: json)

        // Should be approximately 5 days (allow 1 day variance for timezone)
        XCTAssertGreaterThanOrEqual(condition.daysSinceStart, 4)
        XCTAssertLessThanOrEqual(condition.daysSinceStart, 6)
    }

    // MARK: - Error Descriptions

    func testConditionPhotoError_hasDescriptions() {
        let errors: [ConditionPhotoError] = [
            .featureNotAvailable,
            .conditionLimitReached(current: 5, limit: 5),
            .unauthorized,
            .uploadFailed,
            .downloadFailed,
            .conditionNotFound,
            .photoNotFound,
            .shareFailed("test error"),
            .networkError,
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Missing description for \(error)")
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    func testConditionLimitReached_includesNumbers() {
        let error = ConditionPhotoError.conditionLimitReached(current: 3, limit: 5)
        XCTAssertTrue(error.errorDescription!.contains("5"))
    }
}
