import SwiftUI
import PhotosUI

// MARK: - Add Expense Sheet

struct AddExpenseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AddExpenseViewModel
    @State private var amountText: String = ""
    @State private var insuranceText: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingImageSource = false

    init(circleId: String, patientId: String, userId: String, careCostService: CareCostService) {
        _viewModel = StateObject(wrappedValue: AddExpenseViewModel(
            careCostService: careCostService,
            circleId: circleId,
            patientId: patientId,
            userId: userId
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                categorySection
                detailsSection
                dateSection
                recurringSection
                insuranceSection
                receiptSection

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await viewModel.save() {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!viewModel.isValid || viewModel.isSaving)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
    }

    // MARK: - Category Section

    private var categorySection: some View {
        Section {
            Picker("Category", selection: $viewModel.category) {
                ForEach(ExpenseCategory.allCases) { category in
                    Label(category.displayName, systemImage: category.systemImage)
                        .tag(category)
                }
            }
            .accessibilityLabel("Expense category")
        }
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        Section("Details") {
            TextField("Description", text: $viewModel.expenseDescription)
                .accessibilityLabel("Expense description")

            TextField("Vendor / Provider (optional)", text: $viewModel.vendorName)
                .accessibilityLabel("Vendor or provider name")

            HStack {
                Text("$")
                    .foregroundStyle(.secondary)
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                    .onChange(of: amountText) { _, newValue in
                        viewModel.amount = Decimal(string: newValue.replacingOccurrences(of: ",", with: ""))
                    }
                    .accessibilityLabel("Expense amount in dollars")
            }
        }
    }

    // MARK: - Date Section

    private var dateSection: some View {
        Section {
            DatePicker("Date", selection: $viewModel.expenseDate, displayedComponents: .date)
                .accessibilityLabel("Expense date")
        }
    }

    // MARK: - Recurring Section

    private var recurringSection: some View {
        Section {
            Toggle("Recurring Expense", isOn: $viewModel.isRecurring)
                .accessibilityLabel("Mark as recurring expense")

            if viewModel.isRecurring {
                Picker("Frequency", selection: $viewModel.recurrenceRule) {
                    ForEach(RecurrenceRule.allCases, id: \.self) { rule in
                        Text(rule.displayName).tag(rule)
                    }
                }
                .accessibilityLabel("Recurrence frequency")
            }
        }
    }

    // MARK: - Insurance Section

    private var insuranceSection: some View {
        Section("Insurance Coverage") {
            HStack {
                Text("$")
                    .foregroundStyle(.secondary)
                TextField("Covered by Insurance", text: $insuranceText)
                    .keyboardType(.decimalPad)
                    .onChange(of: insuranceText) { _, newValue in
                        viewModel.coveredByInsurance = Decimal(string: newValue.replacingOccurrences(of: ",", with: ""))
                    }
                    .accessibilityLabel("Amount covered by insurance in dollars")
            }

            HStack {
                Text("Out of Pocket")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.outOfPocket, format: .currency(code: "USD"))
                    .fontWeight(.medium)
                    .foregroundStyle(viewModel.outOfPocket > 0 ? .primary : .secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Out of pocket, \(viewModel.outOfPocket, format: .currency(code: "USD"))")
        }
    }

    // MARK: - Receipt Section

    private var receiptSection: some View {
        Section("Receipt") {
            if let image = viewModel.receiptImage {
                VStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .cornerRadius(8)
                        .accessibilityLabel("Attached receipt image")

                    Button(role: .destructive) {
                        viewModel.receiptImage = nil
                    } label: {
                        Label("Remove Receipt", systemImage: "trash")
                    }
                    .accessibilityLabel("Remove attached receipt")
                }
            } else {
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images
                ) {
                    Label("Attach Receipt", systemImage: "camera")
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Attach receipt photo")
                .onChange(of: selectedPhotoItem) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            viewModel.receiptImage = uiImage
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AddExpenseSheet(
        circleId: "preview-circle",
        patientId: "preview-patient",
        userId: "preview-user",
        careCostService: CareCostService.preview
    )
}
