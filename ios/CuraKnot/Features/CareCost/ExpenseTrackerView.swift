import SwiftUI

// MARK: - Expense Tracker View

struct ExpenseTrackerView: View {
    @StateObject private var viewModel: ExpenseTrackerViewModel
    @EnvironmentObject private var appState: AppState
    @State private var showingExportSheet = false
    @State private var exportStartDate = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @State private var exportEndDate = Date()
    @State private var exportFormat: CareCostExportFormat = .pdf
    @State private var showingShareSheet = false

    let circleId: String
    let patientId: String
    private let careCostService: CareCostService

    init(circleId: String, patientId: String, careCostService: CareCostService) {
        self.circleId = circleId
        self.patientId = patientId
        self.careCostService = careCostService
        _viewModel = StateObject(wrappedValue: ExpenseTrackerViewModel(
            careCostService: careCostService,
            circleId: circleId,
            patientId: patientId
        ))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Loading expenses...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error:
                errorView
            case .loaded:
                if viewModel.monthlyGroups.isEmpty {
                    emptyView
                } else {
                    expenseList
                }
            }
        }
        .navigationTitle("Expense Tracker")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingExportSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(viewModel.expenses.isEmpty)
                .accessibilityLabel("Export expense report")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.showingAddExpense = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add expense")
            }
        }
        .sheet(isPresented: $viewModel.showingAddExpense) {
            Task { await viewModel.load() }
        } content: {
            AddExpenseSheet(
                circleId: circleId,
                patientId: patientId,
                userId: appState.currentUser?.id ?? "",
                careCostService: careCostService
            )
        }
        .sheet(isPresented: $showingExportSheet) {
            exportSheet
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = viewModel.exportURL {
                ShareSheet(items: [url])
            }
        }
        .task { await viewModel.load() }
    }

    // MARK: - Expense List

    private var expenseList: some View {
        List {
            ForEach(Array(viewModel.monthlyGroups.enumerated()), id: \.offset) { _, group in
                Section {
                    ForEach(group.expenses) { expense in
                        ExpenseRow(expense: expense)
                    }
                    .onDelete { indexSet in
                        deleteExpenses(in: group, at: indexSet)
                    }
                } header: {
                    HStack {
                        Text(group.month)
                        Spacer()
                        Text(formatCurrency(group.total))
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                }
            }

            Section {
                FinancialDisclaimerView()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await viewModel.load() }
    }

    // MARK: - Export Sheet

    private var exportSheet: some View {
        NavigationStack {
            Form {
                Section("Date Range") {
                    DatePicker("From", selection: $exportStartDate, displayedComponents: .date)
                    DatePicker("To", selection: $exportEndDate, displayedComponents: .date)
                }

                Section("Format") {
                    Picker("Export Format", selection: $exportFormat) {
                        ForEach(CareCostExportFormat.allCases, id: \.self) { format in
                            Label(format.rawValue, systemImage: format.icon)
                                .tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button {
                        Task {
                            await viewModel.exportReport(
                                format: exportFormat,
                                startDate: exportStartDate,
                                endDate: exportEndDate
                            )
                            if viewModel.exportURL != nil {
                                showingExportSheet = false
                                showingShareSheet = true
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isExporting {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(viewModel.isExporting ? "Generating..." : "Generate Report")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(viewModel.isExporting)
                }

                Section {
                    FinancialDisclaimerView()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Export Expenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingExportSheet = false
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyView: some View {
        EmptyStateView(
            icon: "receipt",
            title: "No Expenses Yet",
            message: "Track care-related expenses like medications, home care, and more.",
            actionTitle: "Add First Expense"
        ) {
            viewModel.showingAddExpense = true
        }
    }

    // MARK: - Error State

    private var errorView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            Text("Unable to Load Expenses")
                .font(.headline)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button("Try Again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
    }

    // MARK: - Helpers

    private func deleteExpenses(in group: (month: String, expenses: [CareExpense], total: Decimal), at indexSet: IndexSet) {
        for index in indexSet {
            let expense = group.expenses[index]
            Task { await viewModel.deleteExpense(expense) }
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ExpenseTrackerView(
            circleId: "preview-circle",
            patientId: "preview-patient",
            careCostService: CareCostService.preview
        )
        .environmentObject(AppState())
    }
}
