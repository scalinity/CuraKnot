import XCTest
@testable import CuraKnot

@MainActor
final class PatientEntityQueryTests: XCTestCase {

    var service: SiriShortcutsService!
    var databaseManager: DatabaseManager!

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory database for testing (isolated per test)
        databaseManager = DatabaseManager()
        try databaseManager.setupInMemory()

        service = SiriShortcutsService.shared
        service.configure(
            databaseManager: databaseManager,
            notificationManager: NotificationManager()
        )

        // Set up test context
        service.updateContext(
            userId: "test-user-id",
            circleId: "test-circle-id",
            plan: .free
        )

        // Insert test data
        try await insertTestData()
    }

    override func tearDown() async throws {
        service.updateContext(userId: nil, circleId: nil, plan: nil)
        service = nil
        databaseManager = nil
        try await super.tearDown()
    }

    // MARK: - Test Data Setup

    private func insertTestData() async throws {
        try databaseManager.write { db in
            // Insert test circle
            try db.execute(sql: """
                INSERT INTO circles (id, name, ownerUserId, plan, createdAt, updatedAt)
                VALUES ('test-circle-id', 'Test Circle', 'test-user-id', 'FREE', datetime('now'), datetime('now'))
            """)

            // Insert test patients
            try db.execute(sql: """
                INSERT INTO patients (id, circleId, displayName, initials, createdAt, updatedAt)
                VALUES
                    ('patient-1', 'test-circle-id', 'Margaret Johnson', 'MJ', datetime('now'), datetime('now')),
                    ('patient-2', 'test-circle-id', 'Robert Smith', 'RS', datetime('now'), datetime('now')),
                    ('patient-3', 'test-circle-id', 'Mary Johnson', 'MJ2', datetime('now'), datetime('now'))
            """)

            // Insert test aliases
            try db.execute(sql: """
                INSERT INTO patientAliases (id, patientId, circleId, alias, createdBy, createdAt)
                VALUES
                    ('alias-1', 'patient-1', 'test-circle-id', 'Mom', 'test-user-id', datetime('now')),
                    ('alias-2', 'patient-1', 'test-circle-id', 'Mother', 'test-user-id', datetime('now')),
                    ('alias-3', 'patient-2', 'test-circle-id', 'Dad', 'test-user-id', datetime('now')),
                    ('alias-4', 'patient-1', 'test-circle-id', 'Grandma', 'test-user-id', datetime('now'))
            """)
        }
    }

    // MARK: - Alias Resolution Tests

    func testResolveByExactAlias() throws {
        let matches = try service.resolvePatient(name: "Mom")

        XCTAssertFalse(matches.isEmpty, "Should find at least one match")
        XCTAssertEqual(matches.first?.patient.id, "patient-1")
        XCTAssertEqual(matches.first?.matchType, .aliasExact)
        XCTAssertEqual(matches.first?.confidence, 1.0)
    }

    func testResolveByExactAliasCaseInsensitive() throws {
        let matches = try service.resolvePatient(name: "mom")

        XCTAssertFalse(matches.isEmpty, "Should find match with lowercase query")
        XCTAssertEqual(matches.first?.patient.id, "patient-1")
        XCTAssertEqual(matches.first?.matchType, .aliasExact)
    }

    func testResolveByExactName() throws {
        let matches = try service.resolvePatient(name: "Robert Smith")

        XCTAssertFalse(matches.isEmpty, "Should find match by exact name")
        XCTAssertEqual(matches.first?.patient.id, "patient-2")
        XCTAssertEqual(matches.first?.matchType, .nameExact)
        XCTAssertEqual(matches.first?.confidence, 0.95)
    }

    func testResolveByFirstName() throws {
        let matches = try service.resolvePatient(name: "Robert")

        XCTAssertFalse(matches.isEmpty, "Should find match by first name")
        XCTAssertEqual(matches.first?.patient.id, "patient-2")
        XCTAssertEqual(matches.first?.matchType, .firstName)
        XCTAssertEqual(matches.first?.confidence, 0.8)
    }

    func testResolveByAliasPrefix() throws {
        let matches = try service.resolvePatient(name: "Grand")

        XCTAssertFalse(matches.isEmpty, "Should find match by alias prefix")
        XCTAssertEqual(matches.first?.patient.id, "patient-1")
        XCTAssertEqual(matches.first?.matchType, .aliasPrefix)
        XCTAssertEqual(matches.first?.confidence, 0.7)
    }

    func testResolveByNameContains() throws {
        let matches = try service.resolvePatient(name: "Johnson")

        // Should find both Margaret Johnson and Mary Johnson
        XCTAssertEqual(matches.count, 2, "Should find two patients with 'Johnson' in name")
        XCTAssertTrue(matches.allSatisfy { $0.matchType == .contains })
    }

    func testResolveNoMatch() throws {
        let matches = try service.resolvePatient(name: "NonexistentPerson")

        XCTAssertTrue(matches.isEmpty, "Should not find any matches for unknown name")
    }

    func testResolveMultipleAliasesForSamePatient() throws {
        // Both "Mom" and "Mother" should resolve to patient-1
        let momMatches = try service.resolvePatient(name: "Mom")
        let motherMatches = try service.resolvePatient(name: "Mother")

        XCTAssertEqual(momMatches.first?.patient.id, motherMatches.first?.patient.id)
        XCTAssertEqual(momMatches.first?.patient.id, "patient-1")
    }

    // MARK: - Edge Cases

    func testResolveEmptyString() throws {
        let matches = try service.resolvePatient(name: "")

        XCTAssertTrue(matches.isEmpty, "Empty string should return no matches")
    }

    func testResolveWhitespaceOnly() throws {
        let matches = try service.resolvePatient(name: "   ")

        XCTAssertTrue(matches.isEmpty, "Whitespace-only string should return no matches")
    }

    func testResolveSpecialCharacters() throws {
        let matches = try service.resolvePatient(name: "M@m!")

        XCTAssertTrue(matches.isEmpty, "Special characters shouldn't match anything")
    }

    // MARK: - Confidence Ranking Tests

    func testMatchesAreSortedByConfidence() throws {
        // Insert a patient with name starting with "Grand" to test sorting
        try databaseManager.write { db in
            try db.execute(sql: """
                INSERT INTO patients (id, circleId, displayName, initials, createdAt, updatedAt)
                VALUES ('patient-4', 'test-circle-id', 'Grand Master', 'GM', datetime('now'), datetime('now'))
            """)
        }

        let matches = try service.resolvePatient(name: "Grand")

        // Alias prefix match (Grandma -> patient-1) should come before firstName match (Grand -> patient-4)
        XCTAssertGreaterThanOrEqual(matches.count, 2)

        // Verify matches are sorted by confidence (highest first)
        for i in 0..<(matches.count - 1) {
            XCTAssertGreaterThanOrEqual(
                matches[i].confidence,
                matches[i + 1].confidence,
                "Matches should be sorted by confidence descending"
            )
        }
    }

    // MARK: - Get All Patients Tests

    func testGetAllPatients() throws {
        let patients = try service.getAllPatients()

        XCTAssertEqual(patients.count, 3, "Should return all 3 test patients")
    }

    func testGetDefaultPatient() throws {
        let defaultPatient = try service.getDefaultPatient()

        XCTAssertNotNil(defaultPatient, "Should return a default patient")
        // First patient by creation date
        XCTAssertEqual(defaultPatient?.id, "patient-1")
    }
}
