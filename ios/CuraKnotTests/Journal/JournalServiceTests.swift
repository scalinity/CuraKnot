import XCTest
@testable import CuraKnot

// MARK: - Journal Service Tests

@MainActor
final class JournalServiceTests: XCTestCase {

    // MARK: - Entry Type Tests

    func testJournalEntryTypeProperties() {
        // Test displayName
        XCTAssertEqual(JournalEntryType.goodMoment.displayName, "Good Moment")
        XCTAssertEqual(JournalEntryType.milestone.displayName, "Milestone")

        // Test icons
        XCTAssertEqual(JournalEntryType.goodMoment.icon, "face.smiling")
        XCTAssertEqual(JournalEntryType.milestone.icon, "flag.fill")

        // Test rawValue
        XCTAssertEqual(JournalEntryType.goodMoment.rawValue, "GOOD_MOMENT")
        XCTAssertEqual(JournalEntryType.milestone.rawValue, "MILESTONE")

        // Test promptPlaceholder
        XCTAssertEqual(JournalEntryType.goodMoment.promptPlaceholder, "What made you smile today?")
        XCTAssertEqual(JournalEntryType.milestone.promptPlaceholder, "What does this milestone mean to you?")

        // Test CaseIterable
        XCTAssertEqual(JournalEntryType.allCases.count, 2)
    }

    // MARK: - Milestone Type Tests

    func testMilestoneTypeProperties() {
        // Test displayName
        XCTAssertEqual(MilestoneType.anniversary.displayName, "Anniversary")
        XCTAssertEqual(MilestoneType.progress.displayName, "Progress")
        XCTAssertEqual(MilestoneType.first.displayName, "First Time")
        XCTAssertEqual(MilestoneType.achievement.displayName, "Achievement")
        XCTAssertEqual(MilestoneType.memory.displayName, "Memory")

        // Test icons
        XCTAssertEqual(MilestoneType.anniversary.icon, "calendar.badge.clock")
        XCTAssertEqual(MilestoneType.progress.icon, "chart.line.uptrend.xyaxis")
        XCTAssertEqual(MilestoneType.first.icon, "star.fill")
        XCTAssertEqual(MilestoneType.achievement.icon, "trophy.fill")
        XCTAssertEqual(MilestoneType.memory.icon, "heart.fill")

        // Test rawValues
        XCTAssertEqual(MilestoneType.anniversary.rawValue, "ANNIVERSARY")
        XCTAssertEqual(MilestoneType.progress.rawValue, "PROGRESS")
        XCTAssertEqual(MilestoneType.first.rawValue, "FIRST")
        XCTAssertEqual(MilestoneType.achievement.rawValue, "ACHIEVEMENT")
        XCTAssertEqual(MilestoneType.memory.rawValue, "MEMORY")

        // Test CaseIterable
        XCTAssertEqual(MilestoneType.allCases.count, 5)
    }

    // MARK: - Entry Visibility Tests

    func testEntryVisibilityProperties() {
        // Test displayName
        XCTAssertEqual(EntryVisibility.private.displayName, "Just me")
        XCTAssertEqual(EntryVisibility.circle.displayName, "Share with circle")

        // Test icons
        XCTAssertEqual(EntryVisibility.private.icon, "lock.fill")
        XCTAssertEqual(EntryVisibility.circle.icon, "person.2.fill")

        // Test rawValues
        XCTAssertEqual(EntryVisibility.private.rawValue, "PRIVATE")
        XCTAssertEqual(EntryVisibility.circle.rawValue, "CIRCLE")

        // Test description
        XCTAssertEqual(EntryVisibility.private.description, "Only you can see this entry")
        XCTAssertEqual(EntryVisibility.circle.description, "Everyone in your care circle can see this")

        // Test CaseIterable
        XCTAssertEqual(EntryVisibility.allCases.count, 2)
    }

    // MARK: - Journal Filter Tests

    func testJournalFilterDefaults() {
        let filter = JournalFilter()

        XCTAssertNil(filter.entryType)
        XCTAssertNil(filter.patientId)
        XCTAssertNil(filter.startDate)
        XCTAssertNil(filter.endDate)
        XCTAssertFalse(filter.privateOnly)
        XCTAssertFalse(filter.myEntriesOnly)
        XCTAssertFalse(filter.isActive)
    }

    func testJournalFilterAll() {
        let allFilter = JournalFilter.all

        XCTAssertNil(allFilter.entryType)
        XCTAssertFalse(allFilter.isActive)
    }

    func testJournalFilterWithType() {
        var filter = JournalFilter()
        filter.entryType = .goodMoment

        XCTAssertEqual(filter.entryType, .goodMoment)
        XCTAssertTrue(filter.isActive)
    }

    func testJournalFilterReset() {
        var filter = JournalFilter()
        filter.entryType = .milestone
        filter.privateOnly = true

        XCTAssertTrue(filter.isActive)

        filter.reset()

        XCTAssertNil(filter.entryType)
        XCTAssertFalse(filter.privateOnly)
        XCTAssertFalse(filter.isActive)
    }

    func testJournalFilterEquality() {
        var filter1 = JournalFilter()
        filter1.entryType = .goodMoment

        var filter2 = JournalFilter()
        filter2.entryType = .goodMoment

        var filter3 = JournalFilter()
        filter3.entryType = .milestone

        XCTAssertEqual(filter1, filter2)
        XCTAssertNotEqual(filter1, filter3)
    }

    // MARK: - Filter Preset Tests

    func testJournalFilterPresetAll() {
        let preset = JournalFilterPreset.all
        let filter = preset.toFilter()

        XCTAssertNil(filter.entryType)
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(preset.displayName, "All Entries")
        XCTAssertEqual(preset.icon, "list.bullet")
    }

    func testJournalFilterPresetGoodMoments() {
        let preset = JournalFilterPreset.goodMoments
        let filter = preset.toFilter()

        XCTAssertEqual(filter.entryType, .goodMoment)
        XCTAssertTrue(filter.isActive)
        XCTAssertEqual(preset.displayName, "Good Moments")
        XCTAssertEqual(preset.icon, "face.smiling")
    }

    func testJournalFilterPresetMilestones() {
        let preset = JournalFilterPreset.milestones
        let filter = preset.toFilter()

        XCTAssertEqual(filter.entryType, .milestone)
        XCTAssertTrue(filter.isActive)
        XCTAssertEqual(preset.displayName, "Milestones")
        XCTAssertEqual(preset.icon, "flag.fill")
    }

    func testJournalFilterPresetMyEntries() {
        let preset = JournalFilterPreset.myEntries
        let filter = preset.toFilter()

        XCTAssertTrue(filter.myEntriesOnly)
        XCTAssertTrue(filter.isActive)
        XCTAssertEqual(preset.displayName, "My Entries")
    }

    func testJournalFilterPresetPrivateOnly() {
        let preset = JournalFilterPreset.privateOnly
        let filter = preset.toFilter()

        XCTAssertTrue(filter.privateOnly)
        XCTAssertTrue(filter.isActive)
        XCTAssertEqual(preset.displayName, "Private Only")
    }

    func testJournalFilterPresetThisWeek() {
        let preset = JournalFilterPreset.thisWeek
        let filter = preset.toFilter()

        XCTAssertNotNil(filter.startDate)
        XCTAssertTrue(filter.isActive)

        // Start date should be 7 days ago
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let tolerance: TimeInterval = 60 // 1 minute tolerance
        XCTAssertLessThan(abs(filter.startDate!.timeIntervalSince(sevenDaysAgo)), tolerance)
    }

    func testJournalFilterPresetThisMonth() {
        let preset = JournalFilterPreset.thisMonth
        let filter = preset.toFilter()

        XCTAssertNotNil(filter.startDate)
        XCTAssertTrue(filter.isActive)

        // Start date should be 1 month ago
        let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        let tolerance: TimeInterval = 60 // 1 minute tolerance
        XCTAssertLessThan(abs(filter.startDate!.timeIntervalSince(oneMonthAgo)), tolerance)
    }

    // MARK: - Journal Entry Tests

    func testJournalEntryGoodMoment() {
        let entry = JournalEntry(
            id: "test-1",
            circleId: "circle-1",
            patientId: "patient-1",
            createdBy: "user-1",
            entryType: .goodMoment,
            title: nil,
            content: "A good moment today",
            milestoneType: nil,
            photoStorageKeys: [],
            visibility: .circle,
            entryDate: Date(),
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertFalse(entry.isMilestone)
        XCTAssertFalse(entry.isPrivate)
        XCTAssertFalse(entry.hasPhotos)
        XCTAssertEqual(entry.photoCount, 0)
    }

    func testJournalEntryMilestone() {
        let entry = JournalEntry(
            id: "test-2",
            circleId: "circle-1",
            patientId: "patient-1",
            createdBy: "user-1",
            entryType: .milestone,
            title: "First Walk",
            content: "Took first walk around the block!",
            milestoneType: .first,
            photoStorageKeys: [],
            visibility: .circle,
            entryDate: Date(),
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertTrue(entry.isMilestone)
        XCTAssertEqual(entry.milestoneType, .first)
        XCTAssertEqual(entry.title, "First Walk")
    }

    func testJournalEntryPrivate() {
        let entry = JournalEntry(
            id: "test-3",
            circleId: "circle-1",
            patientId: "patient-1",
            createdBy: "user-1",
            entryType: .goodMoment,
            title: nil,
            content: "Private thought",
            milestoneType: nil,
            photoStorageKeys: [],
            visibility: .private,
            entryDate: Date(),
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertTrue(entry.isPrivate)
    }

    func testJournalEntryWithPhotos() {
        let entry = JournalEntry(
            id: "test-4",
            circleId: "circle-1",
            patientId: "patient-1",
            createdBy: "user-1",
            entryType: .goodMoment,
            title: nil,
            content: "Look at these photos!",
            milestoneType: nil,
            photoStorageKeys: ["photo-1.jpg", "photo-2.jpg"],
            visibility: .circle,
            entryDate: Date(),
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertTrue(entry.hasPhotos)
        XCTAssertEqual(entry.photoCount, 2)
    }

    func testJournalEntryDisplaySummary() {
        // Short content stays as is
        let shortEntry = JournalEntry(
            id: "test-5",
            circleId: "circle-1",
            patientId: "patient-1",
            createdBy: "user-1",
            entryType: .goodMoment,
            title: nil,
            content: "Short content",
            milestoneType: nil,
            photoStorageKeys: [],
            visibility: .circle
        )
        XCTAssertEqual(shortEntry.displaySummary, "Short content")

        // Long content gets truncated
        let longContent = String(repeating: "a", count: 200)
        let longEntry = JournalEntry(
            id: "test-6",
            circleId: "circle-1",
            patientId: "patient-1",
            createdBy: "user-1",
            entryType: .goodMoment,
            title: nil,
            content: longContent,
            milestoneType: nil,
            photoStorageKeys: [],
            visibility: .circle
        )
        XCTAssertEqual(longEntry.displaySummary.count, 150) // 147 + "..."
        XCTAssertTrue(longEntry.displaySummary.hasSuffix("..."))
    }

    // MARK: - Validation Tests

    func testJournalEntryValidationSuccess() throws {
        let validEntry = JournalEntry(
            id: "test-valid",
            circleId: "circle-1",
            patientId: "patient-1",
            createdBy: "user-1",
            entryType: .goodMoment,
            title: nil,
            content: "Valid content",
            milestoneType: nil,
            photoStorageKeys: [],
            visibility: .circle
        )

        XCTAssertNoThrow(try validEntry.validate())
    }

    func testJournalEntryValidationEmptyContent() {
        let invalidEntry = JournalEntry(
            id: "test-empty",
            circleId: "circle-1",
            patientId: "patient-1",
            createdBy: "user-1",
            entryType: .goodMoment,
            title: nil,
            content: "",
            milestoneType: nil,
            photoStorageKeys: [],
            visibility: .circle
        )

        XCTAssertThrowsError(try invalidEntry.validate()) { error in
            XCTAssertEqual(error as? JournalValidationError, .invalidContentLength)
        }
    }

    func testJournalEntryValidationContentTooLong() {
        let longContent = String(repeating: "a", count: 2001)
        let invalidEntry = JournalEntry(
            id: "test-long",
            circleId: "circle-1",
            patientId: "patient-1",
            createdBy: "user-1",
            entryType: .goodMoment,
            title: nil,
            content: longContent,
            milestoneType: nil,
            photoStorageKeys: [],
            visibility: .circle
        )

        XCTAssertThrowsError(try invalidEntry.validate()) { error in
            XCTAssertEqual(error as? JournalValidationError, .invalidContentLength)
        }
    }

    func testJournalEntryValidationMilestoneWithoutTitle() {
        let invalidEntry = JournalEntry(
            id: "test-notitle",
            circleId: "circle-1",
            patientId: "patient-1",
            createdBy: "user-1",
            entryType: .milestone,
            title: nil, // Missing title
            content: "A milestone",
            milestoneType: .achievement,
            photoStorageKeys: [],
            visibility: .circle
        )

        XCTAssertThrowsError(try invalidEntry.validate()) { error in
            XCTAssertEqual(error as? JournalValidationError, .milestoneRequiresTitle)
        }
    }

    func testJournalEntryValidationMilestoneWithEmptyTitle() {
        let invalidEntry = JournalEntry(
            id: "test-emptytitle",
            circleId: "circle-1",
            patientId: "patient-1",
            createdBy: "user-1",
            entryType: .milestone,
            title: "", // Empty title
            content: "A milestone",
            milestoneType: .achievement,
            photoStorageKeys: [],
            visibility: .circle
        )

        XCTAssertThrowsError(try invalidEntry.validate()) { error in
            XCTAssertEqual(error as? JournalValidationError, .milestoneRequiresTitle)
        }
    }

    func testJournalEntryValidationMilestoneWithoutType() {
        let invalidEntry = JournalEntry(
            id: "test-notype",
            circleId: "circle-1",
            patientId: "patient-1",
            createdBy: "user-1",
            entryType: .milestone,
            title: "Great Milestone",
            content: "A milestone",
            milestoneType: nil, // Missing type
            photoStorageKeys: [],
            visibility: .circle
        )

        XCTAssertThrowsError(try invalidEntry.validate()) { error in
            XCTAssertEqual(error as? JournalValidationError, .milestoneRequiresType)
        }
    }

    func testJournalEntryValidationTooManyPhotos() {
        let invalidEntry = JournalEntry(
            id: "test-manyphotos",
            circleId: "circle-1",
            patientId: "patient-1",
            createdBy: "user-1",
            entryType: .goodMoment,
            title: nil,
            content: "Too many photos",
            milestoneType: nil,
            photoStorageKeys: ["1.jpg", "2.jpg", "3.jpg", "4.jpg"], // 4 photos
            visibility: .circle
        )

        XCTAssertThrowsError(try invalidEntry.validate()) { error in
            XCTAssertEqual(error as? JournalValidationError, .tooManyPhotos)
        }
    }

    func testJournalEntryValidationMaxPhotosAllowed() throws {
        let validEntry = JournalEntry(
            id: "test-3photos",
            circleId: "circle-1",
            patientId: "patient-1",
            createdBy: "user-1",
            entryType: .goodMoment,
            title: nil,
            content: "Three photos",
            milestoneType: nil,
            photoStorageKeys: ["1.jpg", "2.jpg", "3.jpg"], // 3 photos is ok
            visibility: .circle
        )

        XCTAssertNoThrow(try validEntry.validate())
    }

    // MARK: - Usage Check Tests

    func testJournalUsageCheckAllowed() {
        let check = JournalUsageCheck(
            allowed: true,
            current: 3,
            limit: 5,
            unlimited: false,
            plan: "FREE"
        )

        XCTAssertTrue(check.allowed)
        XCTAssertEqual(check.remaining, 2)
        XCTAssertFalse(check.isNearLimit)
        XCTAssertFalse(check.isAtLimit)
    }

    func testJournalUsageCheckNearLimit() {
        let check = JournalUsageCheck(
            allowed: true,
            current: 4,
            limit: 5,
            unlimited: false,
            plan: "FREE"
        )

        XCTAssertTrue(check.isNearLimit)
        XCTAssertFalse(check.isAtLimit)
        XCTAssertEqual(check.remaining, 1)
    }

    func testJournalUsageCheckAtLimit() {
        let check = JournalUsageCheck(
            allowed: false,
            current: 5,
            limit: 5,
            unlimited: false,
            plan: "FREE"
        )

        XCTAssertFalse(check.allowed)
        XCTAssertTrue(check.isAtLimit)
        XCTAssertEqual(check.remaining, 0)
    }

    func testJournalUsageCheckUnlimited() {
        let check = JournalUsageCheck(
            allowed: true,
            current: 100,
            limit: nil,
            unlimited: true,
            plan: "PLUS"
        )

        XCTAssertTrue(check.unlimited)
        XCTAssertNil(check.remaining)
        XCTAssertFalse(check.isNearLimit)
        XCTAssertFalse(check.isAtLimit)
    }

    // MARK: - Error Description Tests

    func testJournalServiceErrorDescriptions() {
        XCTAssertEqual(
            JournalServiceError.notAuthenticated.errorDescription,
            "Please sign in to use the journal."
        )
        XCTAssertEqual(
            JournalServiceError.notAuthor.errorDescription,
            "You can only edit your own entries."
        )
        XCTAssertEqual(
            JournalServiceError.entryNotFound.errorDescription,
            "Entry not found."
        )
        XCTAssertEqual(
            JournalServiceError.usageLimitReached(current: 5, limit: 5).errorDescription,
            "You've used 5/5 journal entries this month. Upgrade for unlimited entries."
        )
        XCTAssertEqual(
            JournalServiceError.featureNotAvailable("Photo attachments").errorDescription,
            "Photo attachments requires a Plus or Family subscription."
        )
        XCTAssertEqual(
            JournalServiceError.memoryBookGenerationFailed.errorDescription,
            "Failed to generate Memory Book. Please try again."
        )
    }

    func testJournalValidationErrorDescriptions() {
        XCTAssertEqual(
            JournalValidationError.invalidContentLength.errorDescription,
            "Entry must be between 1 and 2000 characters."
        )
        XCTAssertEqual(
            JournalValidationError.milestoneRequiresTitle.errorDescription,
            "Milestones require a title."
        )
        XCTAssertEqual(
            JournalValidationError.milestoneRequiresType.errorDescription,
            "Please select a milestone type."
        )
        XCTAssertEqual(
            JournalValidationError.tooManyPhotos.errorDescription,
            "Maximum 3 photos per entry."
        )
        XCTAssertEqual(
            JournalValidationError.photoTooLarge.errorDescription,
            "Photo must be under 5MB."
        )
        XCTAssertEqual(
            JournalValidationError.featureNotAvailable("Memory Book").errorDescription,
            "Memory Book requires a Plus or Family subscription."
        )
        XCTAssertEqual(
            JournalValidationError.usageLimitReached(current: 5, limit: 5).errorDescription,
            "You've used 5/5 journal entries this month."
        )
    }

    // MARK: - Coding Tests

    func testJournalEntryCoding() throws {
        let entry = JournalEntry(
            id: "test-coding",
            circleId: "circle-1",
            patientId: "patient-1",
            createdBy: "user-1",
            entryType: .milestone,
            title: "Test Title",
            content: "Test content",
            milestoneType: .achievement,
            photoStorageKeys: ["photo.jpg"],
            visibility: .circle,
            entryDate: Date(timeIntervalSince1970: 1704067200), // 2024-01-01
            createdAt: Date(timeIntervalSince1970: 1704067200),
            updatedAt: Date(timeIntervalSince1970: 1704067200)
        )

        // Encode - JournalEntry has explicit CodingKeys, so don't use .convertToSnakeCase
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)

        // Verify JSON keys (using explicit CodingKeys values)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["id"] as? String, "test-coding")
        XCTAssertEqual(json?["circle_id"] as? String, "circle-1")
        XCTAssertEqual(json?["patient_id"] as? String, "patient-1")
        XCTAssertEqual(json?["created_by"] as? String, "user-1")
        XCTAssertEqual(json?["entry_type"] as? String, "MILESTONE")
        XCTAssertEqual(json?["title"] as? String, "Test Title")
        XCTAssertEqual(json?["content"] as? String, "Test content")
        XCTAssertEqual(json?["milestone_type"] as? String, "ACHIEVEMENT")
        XCTAssertEqual(json?["visibility"] as? String, "CIRCLE")
        XCTAssertEqual((json?["photo_storage_keys"] as? [String])?.first, "photo.jpg")

        // Decode - JournalEntry has explicit CodingKeys, so don't use .convertFromSnakeCase
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(JournalEntry.self, from: data)

        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.circleId, entry.circleId)
        XCTAssertEqual(decoded.patientId, entry.patientId)
        XCTAssertEqual(decoded.createdBy, entry.createdBy)
        XCTAssertEqual(decoded.entryType, entry.entryType)
        XCTAssertEqual(decoded.title, entry.title)
        XCTAssertEqual(decoded.content, entry.content)
        XCTAssertEqual(decoded.milestoneType, entry.milestoneType)
        XCTAssertEqual(decoded.photoStorageKeys, entry.photoStorageKeys)
        XCTAssertEqual(decoded.visibility, entry.visibility)
    }
}
