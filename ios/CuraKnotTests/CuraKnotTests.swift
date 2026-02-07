import XCTest
@testable import CuraKnot

final class CuraKnotTests: XCTestCase {
    
    // MARK: - Model Tests
    
    func testUserInitials() {
        let user = User(
            id: "test",
            email: nil,
            appleSub: nil,
            displayName: "Alice Johnson",
            avatarUrl: nil,
            settingsJson: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        XCTAssertEqual(user.initials, "AJ")
    }
    
    func testUserInitialsSingleName() {
        let user = User(
            id: "test",
            email: nil,
            appleSub: nil,
            displayName: "Alice",
            avatarUrl: nil,
            settingsJson: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        XCTAssertEqual(user.initials, "AL")
    }
    
    func testPatientAge() {
        let calendar = Calendar.current
        let dob = calendar.date(byAdding: .year, value: -75, to: Date())!
        
        let patient = Patient(
            id: "test",
            circleId: "circle",
            displayName: "Test Patient",
            initials: "TP",
            dob: dob,
            pronouns: nil,
            notes: nil,
            archivedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        XCTAssertEqual(patient.age, 75)
    }
    
    func testTaskOverdue() {
        let pastDue = Date().addingTimeInterval(-3600) // 1 hour ago
        
        let task = CareTask(
            id: "test",
            circleId: "circle",
            patientId: nil,
            handoffId: nil,
            createdBy: "user",
            ownerUserId: "user",
            title: "Test Task",
            description: nil,
            dueAt: pastDue,
            priority: .med,
            status: .open,
            completedAt: nil,
            completedBy: nil,
            completionNote: nil,
            reminderJson: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        XCTAssertTrue(task.isOverdue)
    }
    
    func testTaskNotOverdueWhenComplete() {
        let pastDue = Date().addingTimeInterval(-3600)
        
        let task = CareTask(
            id: "test",
            circleId: "circle",
            patientId: nil,
            handoffId: nil,
            createdBy: "user",
            ownerUserId: "user",
            title: "Test Task",
            description: nil,
            dueAt: pastDue,
            priority: .med,
            status: .done,
            completedAt: Date(),
            completedBy: "user",
            completionNote: nil,
            reminderJson: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        XCTAssertFalse(task.isOverdue)
    }
    
    // MARK: - Role Permission Tests
    
    func testOwnerCanInvite() {
        XCTAssertTrue(CircleMember.Role.owner.canInviteMembers)
    }
    
    func testAdminCanInvite() {
        XCTAssertTrue(CircleMember.Role.admin.canInviteMembers)
    }
    
    func testContributorCannotInvite() {
        XCTAssertFalse(CircleMember.Role.contributor.canInviteMembers)
    }
    
    func testViewerCannotInvite() {
        XCTAssertFalse(CircleMember.Role.viewer.canInviteMembers)
    }
    
    func testViewerCannotCreateHandoffs() {
        XCTAssertFalse(CircleMember.Role.viewer.canCreateHandoffs)
    }
    
    func testContributorCanCreateHandoffs() {
        XCTAssertTrue(CircleMember.Role.contributor.canCreateHandoffs)
    }
}
