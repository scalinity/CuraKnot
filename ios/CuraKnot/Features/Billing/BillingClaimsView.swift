import SwiftUI

// MARK: - Financial Item Model

struct FinancialItem: Identifiable, Codable {
    let id: UUID
    let circleId: UUID
    var patientId: UUID?
    let createdBy: UUID
    var kind: Kind
    var vendor: String?
    var amountCents: Int?
    var currency: String
    var dueAt: Date?
    var status: Status
    var referenceId: String?
    var notes: String?
    var attachmentIds: [UUID]
    let createdAt: Date
    var updatedAt: Date
    
    enum Kind: String, Codable, CaseIterable {
        case bill = "BILL"
        case claim = "CLAIM"
        case eob = "EOB"
        case auth = "AUTH"
        case receipt = "RECEIPT"
        
        var displayName: String {
            switch self {
            case .bill: return "Bill"
            case .claim: return "Claim"
            case .eob: return "EOB"
            case .auth: return "Authorization"
            case .receipt: return "Receipt"
            }
        }
        
        var icon: String {
            switch self {
            case .bill: return "doc.text"
            case .claim: return "doc.badge.arrow.up"
            case .eob: return "doc.badge.ellipsis"
            case .auth: return "checkmark.seal"
            case .receipt: return "receipt"
            }
        }
    }
    
    enum Status: String, Codable, CaseIterable {
        case open = "OPEN"
        case submitted = "SUBMITTED"
        case paid = "PAID"
        case denied = "DENIED"
        case closed = "CLOSED"
        
        var displayName: String {
            switch self {
            case .open: return "Open"
            case .submitted: return "Submitted"
            case .paid: return "Paid"
            case .denied: return "Denied"
            case .closed: return "Closed"
            }
        }
        
        var color: Color {
            switch self {
            case .open: return .blue
            case .submitted: return .orange
            case .paid: return .green
            case .denied: return .red
            case .closed: return .secondary
            }
        }
    }
    
    var amountFormatted: String? {
        guard let cents = amountCents else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: Double(cents) / 100.0))
    }
    
    var isOverdue: Bool {
        guard let due = dueAt, status == .open else { return false }
        return due < Date()
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case patientId = "patient_id"
        case createdBy = "created_by"
        case kind
        case vendor
        case amountCents = "amount_cents"
        case currency
        case dueAt = "due_at"
        case status
        case referenceId = "reference_id"
        case notes
        case attachmentIds = "attachment_ids"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Billing Claims View

struct BillingClaimsView: View {
    @EnvironmentObject var appState: AppState
    @State private var items: [FinancialItem] = []
    @State private var selectedFilter: BillingFilter = .all
    @State private var showingNewItem = false
    @State private var showingExport = false
    @State private var isLoading = false
    @State private var summary: BillingSummary?
    
    enum BillingFilter: String, CaseIterable {
        case all = "All"
        case open = "Open"
        case overdue = "Overdue"
        case resolved = "Resolved"
    }
    
    struct BillingSummary {
        var totalOpen: Int = 0
        var totalPaid: Int = 0
        var overdueCount: Int = 0
    }
    
    var filteredItems: [FinancialItem] {
        switch selectedFilter {
        case .all:
            return items
        case .open:
            return items.filter { $0.status == .open || $0.status == .submitted }
        case .overdue:
            return items.filter { $0.isOverdue }
        case .resolved:
            return items.filter { $0.status == .paid || $0.status == .denied || $0.status == .closed }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Summary Card
                if let summary = summary {
                    SummaryCard(summary: summary)
                        .padding()
                }
                
                // Filter
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(BillingFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                // Content
                if isLoading {
                    ProgressView()
                        .frame(maxHeight: .infinity)
                } else if filteredItems.isEmpty {
                    EmptyStateView(
                        icon: "doc.text",
                        title: "No Items",
                        message: "Track bills, claims, and other financial items here.",
                        actionTitle: "Add Item"
                    ) {
                        showingNewItem = true
                    }
                } else {
                    List {
                        ForEach(filteredItems) { item in
                            NavigationLink {
                                FinancialItemDetailView(item: item)
                            } label: {
                                FinancialItemCell(item: item)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await loadItems()
                    }
                }
            }
            .navigationTitle("Billing & Claims")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingExport = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewItem = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewItem) {
                FinancialItemEditorView { newItem in
                    items.insert(newItem, at: 0)
                    updateSummary()
                }
            }
            .sheet(isPresented: $showingExport) {
                FinancialExportView()
            }
            .task {
                await loadItems()
            }
        }
    }
    
    private func loadItems() async {
        isLoading = true
        // TODO: Load from Supabase
        isLoading = false
        updateSummary()
    }
    
    private func updateSummary() {
        var newSummary = BillingSummary()
        for item in items {
            if item.status == .open || item.status == .submitted {
                newSummary.totalOpen += item.amountCents ?? 0
            }
            if item.status == .paid {
                newSummary.totalPaid += item.amountCents ?? 0
            }
            if item.isOverdue {
                newSummary.overdueCount += 1
            }
        }
        summary = newSummary
    }
}

// MARK: - Summary Card

struct SummaryCard: View {
    let summary: BillingClaimsView.BillingSummary
    
    var body: some View {
        HStack(spacing: 0) {
            SummaryItem(
                title: "Open",
                value: formatCurrency(summary.totalOpen),
                color: .blue
            )
            
            Divider()
                .frame(height: 40)
            
            SummaryItem(
                title: "Paid",
                value: formatCurrency(summary.totalPaid),
                color: .green
            )
            
            Divider()
                .frame(height: 40)
            
            SummaryItem(
                title: "Overdue",
                value: "\(summary.overdueCount)",
                color: summary.overdueCount > 0 ? .red : .secondary
            )
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func formatCurrency(_ cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$0"
    }
}

struct SummaryItem: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Financial Item Cell

struct FinancialItemCell: View {
    let item: FinancialItem
    
    var body: some View {
        HStack(spacing: 12) {
            // Kind Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(item.status.color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: item.kind.icon)
                    .font(.title3)
                    .foregroundStyle(item.status.color)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.vendor ?? item.kind.displayName)
                        .font(.body)
                        .lineLimit(1)
                    
                    if item.isOverdue {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                
                HStack(spacing: 8) {
                    // Status Badge
                    Text(item.status.displayName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(item.status.color.opacity(0.15))
                        .foregroundStyle(item.status.color)
                        .clipShape(Capsule())
                    
                    // Due date
                    if let dueAt = item.dueAt {
                        Text(dueAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(item.isOverdue ? .red : .secondary)
                    }
                }
            }
            
            Spacer()
            
            // Amount
            if let amount = item.amountFormatted {
                Text(amount)
                    .font(.body.monospacedDigit())
                    .fontWeight(.medium)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Financial Item Detail View

struct FinancialItemDetailView: View {
    let item: FinancialItem
    @State private var showingEdit = false
    
    var body: some View {
        List {
            Section {
                LabeledContent("Type", value: item.kind.displayName)
                LabeledContent("Status", value: item.status.displayName)
                if let vendor = item.vendor {
                    LabeledContent("Vendor", value: vendor)
                }
                if let amount = item.amountFormatted {
                    LabeledContent("Amount", value: amount)
                }
            }
            
            if item.dueAt != nil || item.referenceId != nil {
                Section {
                    if let dueAt = item.dueAt {
                        LabeledContent("Due Date") {
                            Text(dueAt, style: .date)
                                .foregroundStyle(item.isOverdue ? .red : .primary)
                        }
                    }
                    if let ref = item.referenceId {
                        LabeledContent("Reference #", value: ref)
                    }
                }
            }
            
            if let notes = item.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                        .font(.body)
                }
            }
            
            Section {
                Button {
                    // TODO: Create reminder task
                } label: {
                    Label("Create Reminder Task", systemImage: "bell")
                }
                
                Button {
                    // TODO: Add attachment
                } label: {
                    Label("Add Attachment", systemImage: "paperclip")
                }
            }
        }
        .navigationTitle(item.vendor ?? item.kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    showingEdit = true
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            FinancialItemEditorView(existingItem: item) { _ in }
        }
    }
}

// MARK: - Preview

#Preview {
    BillingClaimsView()
        .environmentObject(AppState())
}
