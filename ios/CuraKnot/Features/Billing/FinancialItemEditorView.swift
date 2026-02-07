import SwiftUI

// MARK: - Financial Item Editor View

struct FinancialItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    let existingItem: FinancialItem?
    let onSave: (FinancialItem) -> Void
    
    @State private var kind: FinancialItem.Kind = .bill
    @State private var vendor = ""
    @State private var amount = ""
    @State private var status: FinancialItem.Status = .open
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var referenceId = ""
    @State private var notes = ""
    @State private var selectedPatient: Patient?
    
    @State private var isSaving = false
    
    init(existingItem: FinancialItem? = nil, onSave: @escaping (FinancialItem) -> Void) {
        self.existingItem = existingItem
        self.onSave = onSave
    }
    
    var isEditing: Bool {
        existingItem != nil
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Type Section
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(FinancialItem.Kind.allCases, id: \.self) { kind in
                            Label(kind.displayName, systemImage: kind.icon)
                                .tag(kind)
                        }
                    }
                    
                    Picker("Status", selection: $status) {
                        ForEach(FinancialItem.Status.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                }
                
                // Details Section
                Section("Details") {
                    TextField("Vendor / Provider", text: $vendor)
                    
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                    }
                    
                    TextField("Reference # (optional)", text: $referenceId)
                }
                
                // Due Date Section
                Section {
                    Toggle("Has Due Date", isOn: $hasDueDate)
                    
                    if hasDueDate {
                        DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
                    }
                }
                
                // Patient Section
                Section {
                    Picker("Patient", selection: $selectedPatient) {
                        Text("No Patient").tag(nil as Patient?)
                        ForEach(appState.patients) { patient in
                            Text(patient.displayName).tag(patient as Patient?)
                        }
                    }
                }
                
                // Notes Section
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
                
                // Quick Templates
                if !isEditing {
                    Section("Quick Add") {
                        Button {
                            kind = .bill
                            status = .open
                        } label: {
                            Label("Medical Bill", systemImage: "doc.text")
                        }
                        
                        Button {
                            kind = .claim
                            status = .submitted
                        } label: {
                            Label("Insurance Claim", systemImage: "doc.badge.arrow.up")
                        }
                        
                        Button {
                            kind = .eob
                            status = .open
                        } label: {
                            Label("Explanation of Benefits", systemImage: "doc.badge.ellipsis")
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Item" : "New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        saveItem()
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                if let item = existingItem {
                    kind = item.kind
                    vendor = item.vendor ?? ""
                    if let cents = item.amountCents {
                        amount = String(format: "%.2f", Double(cents) / 100.0)
                    }
                    status = item.status
                    if let due = item.dueAt {
                        hasDueDate = true
                        dueDate = due
                    }
                    referenceId = item.referenceId ?? ""
                    notes = item.notes ?? ""
                    selectedPatient = item.patientId.flatMap { uuid in appState.patients.first { $0.id == uuid.uuidString } }
                }
            }
        }
    }
    
    private func saveItem() {
        isSaving = true
        
        // Parse amount
        var amountCents: Int?
        if let amountValue = Double(amount.replacingOccurrences(of: ",", with: "")) {
            amountCents = Int(amountValue * 100)
        }
        
        let item = FinancialItem(
            id: existingItem?.id ?? UUID(),
            circleId: existingItem?.circleId ?? (UUID(uuidString: appState.currentCircle?.id ?? "") ?? UUID()),
            patientId: (selectedPatient?.id).flatMap { UUID(uuidString: $0) },
            createdBy: existingItem?.createdBy ?? (UUID(uuidString: appState.currentUser?.id ?? "") ?? UUID()),
            kind: kind,
            vendor: vendor.isEmpty ? nil : vendor,
            amountCents: amountCents,
            currency: "USD",
            dueAt: hasDueDate ? dueDate : nil,
            status: status,
            referenceId: referenceId.isEmpty ? nil : referenceId,
            notes: notes.isEmpty ? nil : notes,
            attachmentIds: existingItem?.attachmentIds ?? [],
            createdAt: existingItem?.createdAt ?? Date(),
            updatedAt: Date()
        )
        
        // TODO: Save to Supabase
        
        onSave(item)
        dismiss()
    }
}

// MARK: - Financial Export View

struct FinancialExportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var selectedPatient: Patient?
    @State private var exportFormat: ExportFormat = .pdf
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showingShareSheet = false
    
    enum ExportFormat: String, CaseIterable {
        case pdf = "PDF"
        case csv = "CSV"
        
        var icon: String {
            switch self {
            case .pdf: return "doc.richtext"
            case .csv: return "tablecells"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Date Range") {
                    DatePicker("From", selection: $startDate, displayedComponents: .date)
                    DatePicker("To", selection: $endDate, displayedComponents: .date)
                }
                
                Section("Filter") {
                    Picker("Patient", selection: $selectedPatient) {
                        Text("All Patients").tag(nil as Patient?)
                        ForEach(appState.patients) { patient in
                            Text(patient.displayName).tag(patient as Patient?)
                        }
                    }
                }
                
                Section("Format") {
                    Picker("Export Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Label(format.rawValue, systemImage: format.icon)
                                .tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section {
                    Button {
                        generateExport()
                    } label: {
                        HStack {
                            Spacer()
                            if isExporting {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isExporting ? "Generating..." : "Generate Export")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isExporting)
                }
            }
            .navigationTitle("Export Financial Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }
    
    private func generateExport() {
        isExporting = true
        
        // TODO: Call generate-financial-export edge function
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isExporting = false
            // Show share sheet with result
            showingShareSheet = true
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    FinancialItemEditorView { _ in }
        .environmentObject(AppState())
}
