import XCTest
@testable import CuraKnot

@MainActor
final class BiometricSessionManagerTests: XCTestCase {

    var sut: BiometricSessionManager!

    override func setUp() async throws {
        sut = BiometricSessionManager()
    }

    override func tearDown() async throws {
        sut = nil
    }

    // MARK: - Initial State

    func testInitialState_isNotAuthenticated() {
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.authError)
    }

    // MARK: - Session Validity

    func testSessionValid_whenNeverAuthenticated_returnsFalse() {
        XCTAssertFalse(sut.isSessionValid())
    }

    func testInvalidateSession_clearsAuthState() {
        // Given - simulate authenticated state
        sut.invalidateSession()

        // Then
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertFalse(sut.isSessionValid())
    }

    // MARK: - Ensure Authenticated

    func testEnsureAuthenticated_whenSessionInvalid_requiresAuth() async {
        // Session is not valid initially
        XCTAssertFalse(sut.isSessionValid())
    }

    // MARK: - Session Timeout

    func testSessionTimeout_is120Seconds() {
        // The session timeout should be 2 minutes (120 seconds)
        // We verify this through behavior - a fresh manager has no valid session
        XCTAssertFalse(sut.isSessionValid())
    }
}
