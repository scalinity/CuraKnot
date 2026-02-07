import XCTest
import GRDB
@testable import CuraKnot

final class CareCostServiceTests: XCTestCase {

    private var databaseManager: DatabaseManager!

    override func setUp() async throws {
        try await super.setUp()
        databaseManager = DatabaseManager()
        try databaseManager.setupInMemory()

        // Insert required parent records for foreign key constraints
        try databaseManager.write { db in
            try db.execute(
                sql: """
                    INSERT INTO circles (id, name, ownerUserId, plan, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: ["circle-1", "Test Circle", "user-1", "FREE", Date(), Date()]
            )
            try db.execute(
                sql: """
                    INSERT INTO circles (id, name, ownerUserId, plan, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: ["circle-other", "Other Circle", "user-1", "FREE", Date(), Date()]
            )
            try db.execute(
                sql: """
                    INSERT INTO patients (id, circleId, displayName, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: ["patient-1", "circle-1", "Test Patient", Date(), Date()]
            )
        }
    }

    override func tearDown() async throws {
        databaseManager = nil
        try await super.tearDown()
    }

    // MARK: - Expense Category Tests

    func testExpenseCategoryDisplayNames() {
        XCTAssertEqual(ExpenseCategory.homeCare.displayName, "Home Care")
        XCTAssertEqual(ExpenseCategory.medications.displayName, "Medications")
        XCTAssertEqual(ExpenseCategory.supplies.displayName, "Medical Supplies")
        XCTAssertEqual(ExpenseCategory.transportation.displayName, "Transportation")
        XCTAssertEqual(ExpenseCategory.insurance.displayName, "Insurance")
        XCTAssertEqual(ExpenseCategory.equipment.displayName, "Equipment")
        XCTAssertEqual(ExpenseCategory.facility.displayName, "Facility")
        XCTAssertEqual(ExpenseCategory.professional.displayName, "Professional")
    }

    func testExpenseCategoryRawValues() {
        XCTAssertEqual(ExpenseCategory.homeCare.rawValue, "HOME_CARE")
        XCTAssertEqual(ExpenseCategory.medications.rawValue, "MEDICATIONS")
        XCTAssertEqual(ExpenseCategory.supplies.rawValue, "SUPPLIES")
    }

    func testAllCategoriesHaveSystemImages() {
        for category in ExpenseCategory.allCases {
            XCTAssertFalse(category.systemImage.isEmpty, "\(category) missing systemImage")
        }
    }

    // MARK: - Recurrence Rule Tests

    func testRecurrenceRuleRawValues() {
        XCTAssertEqual(RecurrenceRule.weekly.rawValue, "WEEKLY")
        XCTAssertEqual(RecurrenceRule.biweekly.rawValue, "BIWEEKLY")
        XCTAssertEqual(RecurrenceRule.monthly.rawValue, "MONTHLY")
    }

    // MARK: - Scenario Type Tests

    func testScenarioTypeDisplayNames() {
        XCTAssertEqual(ScenarioType.current.displayName, "Current Care")
        XCTAssertEqual(ScenarioType.fullTimeHome.displayName, "Full-Time Home Care")
        XCTAssertEqual(ScenarioType.twentyFourSeven.displayName, "24/7 Home Care")
        XCTAssertEqual(ScenarioType.assistedLiving.displayName, "Assisted Living")
        XCTAssertEqual(ScenarioType.memoryCare.displayName, "Memory Care")
        XCTAssertEqual(ScenarioType.nursingHome.displayName, "Nursing Home")
        XCTAssertEqual(ScenarioType.custom.displayName, "Custom Scenario")
    }

    // MARK: - CareExpense Model Tests

    func testCareExpenseOutOfPocket() {
        let expense = makeExpense(amount: 500, coveredByInsurance: 200)
        XCTAssertEqual(expense.outOfPocket, 300)
    }

    func testCareExpenseOutOfPocketZeroCoverage() {
        let expense = makeExpense(amount: 500, coveredByInsurance: 0)
        XCTAssertEqual(expense.outOfPocket, 500)
    }

    func testCareExpenseOutOfPocketFullCoverage() {
        let expense = makeExpense(amount: 500, coveredByInsurance: 500)
        XCTAssertEqual(expense.outOfPocket, 0)
    }

    // MARK: - GRDB Persistence Tests

    func testCareExpensePersistence() throws {
        let expense = makeExpense(amount: 600, coveredByInsurance: 100)

        try databaseManager.write { db in
            var mutableExpense = expense
            try mutableExpense.insert(db)
        }

        let fetched = try databaseManager.read { db in
            try CareExpense.fetchOne(db, key: expense.id)
        }

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, expense.id)
        XCTAssertEqual(fetched?.amount, 600)
        XCTAssertEqual(fetched?.coveredByInsurance, 100)
        XCTAssertEqual(fetched?.category, .homeCare)
        XCTAssertEqual(fetched?.description, "Test expense")
    }

    func testCareExpenseUpdate() throws {
        var expense = makeExpense(amount: 600, coveredByInsurance: 100)

        try databaseManager.write { db in
            try expense.insert(db)
        }

        expense.amount = 700
        expense.vendorName = "Updated Vendor"

        try databaseManager.write { db in
            try expense.update(db)
        }

        let fetched = try databaseManager.read { db in
            try CareExpense.fetchOne(db, key: expense.id)
        }

        XCTAssertEqual(fetched?.amount, 700)
        XCTAssertEqual(fetched?.vendorName, "Updated Vendor")
    }

    func testCareExpenseDelete() throws {
        let expense = makeExpense(amount: 600, coveredByInsurance: 100)

        try databaseManager.write { db in
            var mutableExpense = expense
            try mutableExpense.insert(db)
        }

        try databaseManager.write { db in
            _ = try CareExpense.deleteOne(db, key: expense.id)
        }

        let fetched = try databaseManager.read { db in
            try CareExpense.fetchOne(db, key: expense.id)
        }

        XCTAssertNil(fetched)
    }

    func testCareExpenseFetchByCircle() throws {
        let circleId = "circle-1"

        for i in 0..<5 {
            let expense = makeExpense(amount: Decimal(100 * (i + 1)), coveredByInsurance: 0, circleId: circleId)

            try databaseManager.write { db in
                var mutable = expense
                try mutable.insert(db)
            }
        }

        // Add one from different circle
        let otherExpense = makeExpense(amount: 999, coveredByInsurance: 0, circleId: "circle-other")
        try databaseManager.write { db in
            var mutable = otherExpense
            try mutable.insert(db)
        }

        let expenses = try databaseManager.read { db in
            try CareExpense
                .filter(Column("circleId") == circleId)
                .order(Column("expenseDate").desc)
                .fetchAll(db)
        }

        XCTAssertEqual(expenses.count, 5)
        XCTAssertTrue(expenses.allSatisfy { $0.circleId == circleId })
    }

    func testCareExpenseRecurringValidation() {
        let recurring = makeExpense(amount: 600, coveredByInsurance: 0, isRecurring: true, recurrenceRule: .weekly)
        XCTAssertTrue(recurring.isRecurring)
        XCTAssertEqual(recurring.recurrenceRule, .weekly)

        let nonRecurring = makeExpense(amount: 600, coveredByInsurance: 0)
        XCTAssertFalse(nonRecurring.isRecurring)
        XCTAssertNil(nonRecurring.recurrenceRule)
    }

    // MARK: - CareCostEstimate Persistence Tests

    func testCareCostEstimatePersistence() throws {
        let estimate = makeEstimate(scenarioType: .assistedLiving, totalMonthly: 5500)

        try databaseManager.write { db in
            var mutableEstimate = estimate
            try mutableEstimate.insert(db)
        }

        let fetched = try databaseManager.read { db in
            try CareCostEstimate.fetchOne(db, key: estimate.id)
        }

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.scenarioType, .assistedLiving)
        XCTAssertEqual(fetched?.totalMonthly, 5500)
    }

    // MARK: - FinancialResource Persistence Tests

    func testFinancialResourcePersistence() throws {
        let resource = FinancialResource(
            id: UUID().uuidString,
            title: "Medicare Home Health",
            resourceDescription: "Official Medicare guide to home health services.",
            url: "https://www.medicare.gov/coverage/home-health-services",
            resourceType: .officialLink,
            category: .medicare,
            contentMarkdown: nil,
            states: nil,
            isFeatured: true,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        try databaseManager.write { db in
            try resource.save(db)
        }

        let fetched = try databaseManager.read { db in
            try FinancialResource.fetchOne(db, key: resource.id)
        }

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, resource.id)
        XCTAssertEqual(fetched?.title, "Medicare Home Health")
        XCTAssertEqual(fetched?.resourceDescription, "Official Medicare guide to home health services.")
        XCTAssertEqual(fetched?.category, .medicare)
        XCTAssertEqual(fetched?.isFeatured, true)
    }

    func testFinancialResourceWithStates() throws {
        let resource = FinancialResource(
            id: UUID().uuidString,
            title: "State Medicaid Office",
            resourceDescription: "Find your state Medicaid office.",
            url: "https://www.medicaid.gov",
            resourceType: .directory,
            category: .medicaid,
            contentMarkdown: nil,
            states: ["CA", "NY", "TX"],
            isFeatured: false,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        try databaseManager.write { db in
            try resource.save(db)
        }

        let fetched = try databaseManager.read { db in
            try FinancialResource.fetchOne(db, key: resource.id)
        }

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.states, ["CA", "NY", "TX"])
        XCTAssertTrue(fetched?.isStateSpecific ?? false)
    }

    // MARK: - Monthly Summary Calculation Tests

    @MainActor
    func testMonthlySummaryCalculation() {
        let expenses = [
            makeExpense(amount: 600, coveredByInsurance: 200, category: .homeCare),
            makeExpense(amount: 200, coveredByInsurance: 50, category: .medications),
            makeExpense(amount: 100, coveredByInsurance: 0, category: .transportation),
        ]

        let service = makeService()
        let summary = service.calculateMonthlySummary(expenses: expenses)

        XCTAssertEqual(summary.total, 900)
        XCTAssertEqual(summary.insuranceCovered, 250)
        XCTAssertEqual(summary.outOfPocket, 650)
        XCTAssertEqual(summary.breakdown[.homeCare], 600)
        XCTAssertEqual(summary.breakdown[.medications], 200)
        XCTAssertEqual(summary.breakdown[.transportation], 100)
    }

    @MainActor
    func testMonthlySummaryEmptyExpenses() {
        let service = makeService()
        let summary = service.calculateMonthlySummary(expenses: [])

        XCTAssertEqual(summary.total, 0)
        XCTAssertEqual(summary.insuranceCovered, 0)
        XCTAssertEqual(summary.outOfPocket, 0)
        XCTAssertTrue(summary.breakdown.isEmpty)
    }

    @MainActor
    func testMonthlySummarySingleCategory() {
        let expenses = [
            makeExpense(amount: 100, coveredByInsurance: 0, category: .medications),
            makeExpense(amount: 200, coveredByInsurance: 50, category: .medications),
            makeExpense(amount: 150, coveredByInsurance: 25, category: .medications),
        ]

        let service = makeService()
        let summary = service.calculateMonthlySummary(expenses: expenses)

        XCTAssertEqual(summary.total, 450)
        XCTAssertEqual(summary.breakdown.count, 1)
        XCTAssertEqual(summary.breakdown[.medications], 450)
        XCTAssertEqual(summary.insuranceCovered, 75)
    }

    // MARK: - Zip Code Validation Tests

    func testValidZipCode() {
        let validZip = "94102"
        XCTAssertEqual(validZip.count, 5)
        XCTAssertTrue(validZip.allSatisfy(\.isNumber))
    }

    func testInvalidZipCodes() {
        let invalid = ["1234", "123456", "abcde", "9410", ""]
        for zip in invalid {
            let isValid = zip.count == 5 && zip.allSatisfy(\.isNumber)
            XCTAssertFalse(isValid, "Expected '\(zip)' to be invalid")
        }
    }

    // MARK: - Helpers

    private func makeExpense(
        amount: Decimal,
        coveredByInsurance: Decimal,
        category: ExpenseCategory = .homeCare,
        circleId: String = "circle-1",
        isRecurring: Bool = false,
        recurrenceRule: RecurrenceRule? = nil
    ) -> CareExpense {
        CareExpense(
            id: UUID().uuidString,
            circleId: circleId,
            patientId: "patient-1",
            createdBy: "user-1",
            category: category,
            description: "Test expense",
            vendorName: "Test Vendor",
            amount: amount,
            expenseDate: Date(),
            isRecurring: isRecurring,
            recurrenceRule: recurrenceRule,
            parentExpenseId: nil,
            coveredByInsurance: coveredByInsurance,
            receiptStorageKey: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func makeEstimate(
        scenarioType: ScenarioType,
        totalMonthly: Decimal
    ) -> CareCostEstimate {
        CareCostEstimate(
            id: UUID().uuidString,
            circleId: "circle-1",
            patientId: "patient-1",
            scenarioName: scenarioType.displayName,
            scenarioType: scenarioType,
            isCurrent: scenarioType == .current,
            homeCareHoursWeekly: nil,
            homeCareHourlyRate: nil,
            homeCareMonthly: nil,
            medicationsMonthly: nil,
            suppliesMonthly: nil,
            transportationMonthly: nil,
            facilityMonthly: scenarioType == .assistedLiving ? totalMonthly : nil,
            otherMonthly: nil,
            totalMonthly: totalMonthly,
            medicareCoveragePct: nil,
            medicaidCoveragePct: nil,
            privateInsurancePct: nil,
            outOfPocketMonthly: totalMonthly,
            notes: nil,
            dataSource: "TEST",
            dataYear: 2024,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    @MainActor
    private func makeService() -> CareCostService {
        let supabaseClient = SupabaseClient(
            url: URL(string: "http://localhost:54321")!,
            anonKey: "test-key"
        )
        let subscriptionManager = SubscriptionManager(supabaseClient: supabaseClient)
        return CareCostService(
            databaseManager: databaseManager,
            supabaseClient: supabaseClient,
            subscriptionManager: subscriptionManager
        )
    }
}
