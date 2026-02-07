import XCTest

final class CuraKnotUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Verify app launched by checking for auth screen elements
        // When not signed in, should show Sign in with Apple button
        let signInButton = app.buttons["Sign in with Apple"]
        
        // Either we see sign in button or we're already authenticated
        // and see the main tab bar
        let tabBar = app.tabBars.firstMatch
        
        XCTAssertTrue(signInButton.exists || tabBar.exists)
    }
    
    // TODO: Add more UI tests for:
    // - Onboarding flow
    // - Handoff creation
    // - Task management
    // - Binder editing
    // - Export flow
}
