import XCTest
@testable import CuraKnot

@MainActor
final class CareCostViewModelTests: XCTestCase {

    private var databaseManager: DatabaseManager!

    override func setUp() async throws {
        try await super.setUp()
        databaseManager = DatabaseManager()
        try databaseManager.setupInMemory()
    }

    override func tearDown() async throws {
        databaseManager = nil
        try await super.tearDown()
    }

    // MARK: - Dashboard ViewModel Tests

    func testDashboardInitialState() {
        let viewModel = makeDashboardViewModel()
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertEqual(viewModel.currentMonthlyTotal, 0)
        XCTAssertTrue(viewModel.costBreakdown.isEmpty)
        XCTAssertEqual(viewModel.expenseCount, 0)
    }

    func testDashboardCalculatesBreakdownFromExpenses() {
        let service = makeService()
        let expenses = [
            makeExpense(amount: 600, coveredByInsurance: 200, category: .homeCare),
            makeExpense(amount: 200, coveredByInsurance: 50, category: .medications),
            makeExpense(amount: 100, coveredByInsurance: 0, category: .transportation),
        ]

        let summary = service.calculateMonthlySummary(expenses: expenses)

        XCTAssertEqual(summary.total, 900)
        XCTAssertEqual(summary.breakdown.count, 3)
        XCTAssertEqual(summary.breakdown[.homeCare], 600)
        XCTAssertEqual(summary.breakdown[.medications], 200)
        XCTAssertEqual(summary.breakdown[.transportation], 100)
    }

    // MARK: - Add Expense ViewModel Tests

    func testAddExpenseValidationEmptyDescription() {
        let vm = makeAddExpenseViewModel()
        vm.expenseDescription = ""
        vm.amount = 100
        XCTAssertFalse(vm.isValid)
    }

    func testAddExpenseValidationZeroAmount() {
        let vm = makeAddExpenseViewModel()
        vm.expenseDescription = "Test"
        vm.amount = 0
        XCTAssertFalse(vm.isValid)
    }

    func testAddExpenseValidationNegativeAmount() {
        let vm = makeAddExpenseViewModel()
        vm.expenseDescription = "Test"
        vm.amount = -100
        XCTAssertFalse(vm.isValid)
    }

    func testAddExpenseValidationCoverageExceedsAmount() {
        let vm = makeAddExpenseViewModel()
        vm.expenseDescription = "Test"
        vm.amount = 100
        vm.coveredByInsurance = 200
        XCTAssertFalse(vm.isValid)
    }

    func testAddExpenseValidationValid() {
        let vm = makeAddExpenseViewModel()
        vm.expenseDescription = "Test expense"
        vm.amount = 100
        vm.coveredByInsurance = 50
        XCTAssertTrue(vm.isValid)
    }

    func testAddExpenseOutOfPocketCalculation() {
        let vm = makeAddExpenseViewModel()
        vm.amount = 500
        vm.coveredByInsurance = 200
        XCTAssertEqual(vm.outOfPocket, 300)
    }

    func testAddExpenseOutOfPocketNilValues() {
        let vm = makeAddExpenseViewModel()
        vm.amount = nil
        vm.coveredByInsurance = nil
        XCTAssertEqual(vm.outOfPocket, 0)
    }

    // MARK: - Cost Projections ViewModel Tests

    func testProjectionsInitialState() {
        let vm = makeProjectionsViewModel()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertNil(vm.currentScenario)
        XCTAssertTrue(vm.projectedScenarios.isEmpty)
        XCTAssertEqual(vm.zipCode, "")
    }

    // MARK: - Financial Resources ViewModel Tests

    func testResourcesInitialState() {
        let vm = makeResourcesViewModel()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertTrue(vm.resources.isEmpty)
        XCTAssertNil(vm.selectedCategory)
    }

    // MARK: - Expense Tracker ViewModel Tests

    func testTrackerInitialState() {
        let vm = makeTrackerViewModel()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertTrue(vm.expenses.isEmpty)
        XCTAssertTrue(vm.monthlyGroups.isEmpty)
        XCTAssertFalse(vm.showingAddExpense)
    }

    // MARK: - Export Format Tests

    func testExportFormatRawValues() {
        XCTAssertEqual(ExportFormat.pdf.rawValue, "PDF")
        XCTAssertEqual(ExportFormat.csv.rawValue, "CSV")
    }

    // MARK: - Resource Category Tests

    func testResourceCategoryRawValues() {
        XCTAssertEqual(ResourceCategory.medicare.rawValue, "MEDICARE")
        XCTAssertEqual(ResourceCategory.medicaid.rawValue, "MEDICAID")
        XCTAssertEqual(ResourceCategory.va.rawValue, "VA")
        XCTAssertEqual(ResourceCategory.tax.rawValue, "TAX")
        XCTAssertEqual(ResourceCategory.planning.rawValue, "PLANNING")
    }

    // MARK: - CareCostError Tests

    func testErrorDescriptions() {
        XCTAssertNotNil(CareCostError.featureNotAvailable.errorDescription)
        XCTAssertNotNil(CareCostError.invalidAmount.errorDescription)
        XCTAssertNotNil(CareCostError.coverageExceedsAmount.errorDescription)
        XCTAssertNotNil(CareCostError.invalidZipCode.errorDescription)
        XCTAssertNotNil(CareCostError.uploadFailed("test").errorDescription)
        XCTAssertNotNil(CareCostError.exportFailed("test").errorDescription)
    }

    // MARK: - Helpers

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

    private func makeDashboardViewModel() -> CareCostDashboardViewModel {
        CareCostDashboardViewModel(
            careCostService: makeService(),
            circleId: "circle-1",
            patientId: "patient-1"
        )
    }

    private func makeAddExpenseViewModel() -> AddExpenseViewModel {
        AddExpenseViewModel(
            careCostService: makeService(),
            circleId: "circle-1",
            patientId: "patient-1",
            userId: "user-1"
        )
    }

    private func makeProjectionsViewModel() -> CostProjectionsViewModel {
        CostProjectionsViewModel(
            careCostService: makeService(),
            circleId: "circle-1",
            patientId: "patient-1"
        )
    }

    private func makeResourcesViewModel() -> FinancialResourcesViewModel {
        FinancialResourcesViewModel(careCostService: makeService())
    }

    private func makeTrackerViewModel() -> ExpenseTrackerViewModel {
        ExpenseTrackerViewModel(
            careCostService: makeService(),
            circleId: "circle-1",
            patientId: "patient-1"
        )
    }

    private func makeExpense(
        amount: Decimal,
        coveredByInsurance: Decimal,
        category: ExpenseCategory = .homeCare
    ) -> CareExpense {
        CareExpense(
            id: UUID().uuidString,
            circleId: "circle-1",
            patientId: "patient-1",
            createdBy: "user-1",
            category: category,
            description: "Test expense",
            vendorName: "Test Vendor",
            amount: amount,
            expenseDate: Date(),
            isRecurring: false,
            recurrenceRule: nil,
            parentExpenseId: nil,
            coveredByInsurance: coveredByInsurance,
            receiptStorageKey: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
