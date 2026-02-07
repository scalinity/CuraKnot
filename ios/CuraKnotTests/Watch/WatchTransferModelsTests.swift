import XCTest
@testable import CuraKnot

final class WatchTransferModelsTests: XCTestCase {

    // MARK: - WatchTask Tests

    func testWatchTaskEncodingDecoding() throws {
        let task = WatchTask(
            id: "task-123",
            patientId: "patient-1",
            title: "Give medication",
            description: "Administer pain medication",
            dueAt: Date(timeIntervalSince1970: 1700000000),
            priority: "HIGH",
            status: "OPEN"
        )

        let encoded = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(WatchTask.self, from: encoded)

        XCTAssertEqual(decoded.id, task.id)
        XCTAssertEqual(decoded.title, task.title)
        XCTAssertEqual(decoded.description, task.description)
        XCTAssertEqual(decoded.priority, task.priority)
        XCTAssertEqual(decoded.status, task.status)
    }

    func testWatchTaskIsOpen() {
        let openTask = WatchTask(
            id: "1",
            patientId: nil,
            title: "Test",
            description: nil,
            dueAt: nil,
            priority: "MED",
            status: "OPEN"
        )
        XCTAssertTrue(openTask.isOpen)

        let doneTask = WatchTask(
            id: "2",
            patientId: nil,
            title: "Test",
            description: nil,
            dueAt: nil,
            priority: "MED",
            status: "DONE"
        )
        XCTAssertFalse(doneTask.isOpen)
    }

    func testWatchTaskIsOverdue() {
        let pastDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let overdueTask = WatchTask(
            id: "1",
            patientId: nil,
            title: "Test",
            description: nil,
            dueAt: pastDate,
            priority: "HIGH",
            status: "OPEN"
        )
        XCTAssertTrue(overdueTask.isOverdue)

        let futureDate = Date().addingTimeInterval(3600) // 1 hour from now
        let notOverdueTask = WatchTask(
            id: "2",
            patientId: nil,
            title: "Test",
            description: nil,
            dueAt: futureDate,
            priority: "HIGH",
            status: "OPEN"
        )
        XCTAssertFalse(notOverdueTask.isOverdue)
    }

    func testWatchTaskIsDueSoon() {
        // Task due in 12 hours (within 24 hour threshold)
        let soonDate = Date().addingTimeInterval(12 * 60 * 60)
        let dueSoonTask = WatchTask(
            id: "1",
            patientId: nil,
            title: "Test",
            description: nil,
            dueAt: soonDate,
            priority: "HIGH",
            status: "OPEN"
        )
        XCTAssertTrue(dueSoonTask.isDueSoon)

        // Task due in 25 hours (outside 24 hour threshold)
        let laterDate = Date().addingTimeInterval(25 * 60 * 60)
        let notDueSoonTask = WatchTask(
            id: "2",
            patientId: nil,
            title: "Test",
            description: nil,
            dueAt: laterDate,
            priority: "HIGH",
            status: "OPEN"
        )
        XCTAssertFalse(notDueSoonTask.isDueSoon)
    }

    func testWatchTaskPriorityIcon() {
        let highTask = WatchTask(id: "1", patientId: nil, title: "High", description: nil, dueAt: nil, priority: "HIGH", status: "OPEN")
        XCTAssertEqual(highTask.priorityIcon, "exclamationmark.circle.fill")

        let medTask = WatchTask(id: "2", patientId: nil, title: "Med", description: nil, dueAt: nil, priority: "MED", status: "OPEN")
        XCTAssertEqual(medTask.priorityIcon, "minus.circle.fill")

        let lowTask = WatchTask(id: "3", patientId: nil, title: "Low", description: nil, dueAt: nil, priority: "LOW", status: "OPEN")
        XCTAssertEqual(lowTask.priorityIcon, "arrow.down.circle.fill")
    }

    // MARK: - WatchHandoff Tests

    func testWatchHandoffEncodingDecoding() throws {
        let handoff = WatchHandoff(
            id: "handoff-123",
            patientId: "patient-1",
            title: "Morning visit update",
            summary: "Patient feeling better today",
            type: "VISIT",
            publishedAt: Date(timeIntervalSince1970: 1700000000),
            createdByName: "Alice",
            createdAt: Date(timeIntervalSince1970: 1700000000)
        )

        let encoded = try JSONEncoder().encode(handoff)
        let decoded = try JSONDecoder().decode(WatchHandoff.self, from: encoded)

        XCTAssertEqual(decoded.id, handoff.id)
        XCTAssertEqual(decoded.title, handoff.title)
        XCTAssertEqual(decoded.summary, handoff.summary)
        XCTAssertEqual(decoded.createdByName, handoff.createdByName)
    }

    // MARK: - WatchPatient Tests

    func testWatchPatientDisplayInitials() {
        let patient = WatchPatient(
            id: "patient-123",
            displayName: "John Smith",
            initials: nil
        )
        XCTAssertEqual(patient.displayInitials, "JS")

        let patientWithInitials = WatchPatient(
            id: "patient-456",
            displayName: "Madonna",
            initials: "MD"
        )
        XCTAssertEqual(patientWithInitials.displayInitials, "MD")

        let emptyPatient = WatchPatient(
            id: "patient-789",
            displayName: "",
            initials: nil
        )
        XCTAssertEqual(emptyPatient.displayInitials, "??")
    }

    // MARK: - WatchContact Tests

    func testWatchContactPhoneURL() {
        let contactWithPhone = WatchContact(
            name: "Dr. Smith",
            role: "Primary Care",
            phone: "555-123-4567"
        )
        XCTAssertTrue(contactWithPhone.canCall)
        XCTAssertNotNil(contactWithPhone.phoneURL)

        let contactWithoutPhone = WatchContact(
            name: "Helper",
            role: "Volunteer",
            phone: nil
        )
        XCTAssertFalse(contactWithoutPhone.canCall)
        XCTAssertNil(contactWithoutPhone.phoneURL)
    }

    // MARK: - WatchMedication Tests

    func testWatchMedicationDisplayText() {
        let med = WatchMedication(
            name: "Ibuprofen",
            dose: "400mg",
            schedule: "Every 6 hours"
        )
        XCTAssertEqual(med.displayText, "Ibuprofen 400mg - Every 6 hours")

        let medNoDose = WatchMedication(
            name: "Aspirin",
            dose: nil,
            schedule: "Daily"
        )
        XCTAssertEqual(medNoDose.displayText, "Aspirin - Daily")
    }

    // MARK: - WatchDraftMetadata Tests

    func testWatchDraftMetadataDictionary() {
        let metadata = WatchDraftMetadata(
            patientId: "patient-123",
            circleId: "circle-456",
            createdAt: Date(timeIntervalSince1970: 1700000000),
            duration: 45.5
        )

        let dict = metadata.dictionary
        // dictionary uses snake_case keys for WatchConnectivity transfer
        XCTAssertEqual(dict["patient_id"] as? String, "patient-123")
        XCTAssertEqual(dict["circle_id"] as? String, "circle-456")
        XCTAssertEqual(dict["duration"] as? TimeInterval, 45.5)
    }

    func testWatchDraftMetadataFromDictionary() {
        // dictionary uses snake_case keys for WatchConnectivity transfer
        let dict: [String: Any] = [
            "patient_id": "patient-123",
            "circle_id": "circle-456",
            "created_at": Date(timeIntervalSince1970: 1700000000).timeIntervalSince1970,
            "duration": 45.5
        ]

        let metadata = WatchDraftMetadata(from: dict)
        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?.patientId, "patient-123")
        XCTAssertEqual(metadata?.circleId, "circle-456")
        XCTAssertEqual(metadata?.duration, 45.5)
    }

    // MARK: - WatchTaskCompletion Tests

    func testWatchTaskCompletionEncodingDecoding() throws {
        let completion = WatchTaskCompletion(
            taskId: "task-123",
            completedAt: Date(timeIntervalSince1970: 1700000000),
            completionNote: "Completed successfully"
        )

        let encoded = try JSONEncoder().encode(completion)
        let decoded = try JSONDecoder().decode(WatchTaskCompletion.self, from: encoded)

        XCTAssertEqual(decoded.taskId, completion.taskId)
        XCTAssertEqual(decoded.completionNote, completion.completionNote)
    }

    // MARK: - WatchCacheData Tests

    func testWatchCacheDataEncodingDecoding() throws {
        let cacheData = WatchCacheData(
            subscriptionPlan: "PLUS",
            currentPatientId: "patient-123",
            patients: [],
            emergencyCard: nil,
            todayTasks: [
                WatchTask(id: "1", patientId: nil, title: "Task 1", description: nil, dueAt: nil, priority: "MED", status: "OPEN")
            ],
            recentHandoffs: [],
            timestamp: Date()
        )

        let encoded = try JSONEncoder().encode(cacheData)
        let decoded = try JSONDecoder().decode(WatchCacheData.self, from: encoded)

        XCTAssertEqual(decoded.subscriptionPlan, "PLUS")
        XCTAssertEqual(decoded.todayTasks.count, 1)
        XCTAssertEqual(decoded.currentPatientId, "patient-123")
    }
}
