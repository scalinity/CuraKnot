import SwiftUI

// MARK: - Inbox Item Model

struct InboxItem: Identifiable, Codable {
    let id: UUID
    let circleId: UUID
    var patientId: UUID?
    let createdBy: UUID
    let kind: Kind
    var status: Status
    var assignedTo: UUID?
    var title: String?
    var note: String?
    var attachmentId: UUID?
    var textPayload: String?
    let createdAt: Date
    var updatedAt: Date
    
    enum Kind: String, Codable, CaseIterable {
        case photo = "PHOTO"
        case pdf = "PDF"
        case audio = "AUDIO"
        case text = "TEXT"
        
        var icon: String {
            switch self {
            case .photo: return "photo"
            case .pdf: return "doc.fill"
            case .audio: return "waveform"
            case .text: return "text.alignleft"
            }
        }
        
        var displayName: String {
            switch self {
            case .photo: return "Photo"
            case .pdf: return "PDF"
            case .audio: return "Audio"
            case .text: return "Text"
            }
        }
    }
    
    enum Status: String, Codable {
        case new = "NEW"
        case assigned = "ASSIGNED"
        case triaged = "TRIAGED"
        case archived = "ARCHIVED"
        
        var color: Color {
            switch self {
            case .new: return .blue
            case .assigned: return .orange
            case .triaged: return .green
            case .archived: return .secondary
            }
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case patientId = "patient_id"
        case createdBy = "created_by"
        case kind
        case status
        case assignedTo = "assigned_to"
        case title
        case note
        case attachmentId = "attachment_id"
        case textPayload = "text_payload"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Inbox View

struct InboxView: View {
    @EnvironmentObject var appState: AppState
    @State private var items: [InboxItem] = []
    @State private var selectedFilter: InboxFilter = .pending
    @State private var showingQuickCapture = false
    @State private var selectedItem: InboxItem?
    @State private var showingTriage = false
    @State private var isLoading = false
    
    enum InboxFilter: String, CaseIterable {
        case pending = "Pending"
        case assigned = "Assigned to Me"
        case all = "All"
        
        var icon: String {
            switch self {
            case .pending: return "tray"
            case .assigned: return "person"
            case .all: return "tray.full"
            }
        }
    }
    
    var filteredItems: [InboxItem] {
        switch selectedFilter {
        case .pending:
            return items.filter { $0.status == .new || $0.status == .assigned }
        case .assigned:
            let currentUserId = (appState.currentUser?.id).flatMap { UUID(uuidString: $0) }
            return items.filter { $0.assignedTo == currentUserId }
        case .all:
            return items
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter Picker
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(InboxFilter.allCases, id: \.self) { filter in
                        Label(filter.rawValue, systemImage: filter.icon)
                            .tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content
                if isLoading {
                    ProgressView()
                        .frame(maxHeight: .infinity)
                } else if filteredItems.isEmpty {
                    EmptyStateView(
                        icon: "tray",
                        title: emptyTitle,
                        message: emptyMessage,
                        actionTitle: "Quick Capture"
                    ) {
                        showingQuickCapture = true
                    }
                } else {
                    List {
                        ForEach(filteredItems) { item in
                            InboxItemCell(item: item)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedItem = item
                                    showingTriage = true
                                }
                                .swipeActions(edge: .trailing) {
                                    Button("Archive", systemImage: "archivebox") {
                                        archiveItem(item)
                                    }
                                    .tint(.secondary)
                                }
                                .swipeActions(edge: .leading) {
                                    Button("Triage", systemImage: "arrow.right.circle") {
                                        selectedItem = item
                                        showingTriage = true
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await loadItems()
                    }
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingQuickCapture = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingQuickCapture) {
                QuickCaptureView { newItem in
                    items.insert(newItem, at: 0)
                }
            }
            .sheet(isPresented: $showingTriage) {
                if let item = selectedItem {
                    TriageSheet(item: item) { updatedItem in
                        if let index = items.firstIndex(where: { $0.id == updatedItem.id }) {
                            items[index] = updatedItem
                        }
                    }
                }
            }
            .task {
                await loadItems()
            }
        }
    }
    
    private var emptyTitle: String {
        switch selectedFilter {
        case .pending: return "Inbox Empty"
        case .assigned: return "Nothing Assigned"
        case .all: return "No Items"
        }
    }
    
    private var emptyMessage: String {
        switch selectedFilter {
        case .pending: return "Capture photos, documents, or notes for later processing."
        case .assigned: return "Items assigned to you will appear here."
        case .all: return "Use Quick Capture to add items to your inbox."
        }
    }
    
    private func loadItems() async {
        isLoading = true
        // TODO: Load from Supabase
        isLoading = false
    }
    
    private func archiveItem(_ item: InboxItem) {
        // TODO: Archive via API
    }
}

// MARK: - Inbox Item Cell

struct InboxItemCell: View {
    let item: InboxItem
    
    var body: some View {
        HStack(spacing: 12) {
            // Kind Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: item.kind.icon)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.title ?? item.kind.displayName)
                        .font(.body)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Status Badge
                    Text(item.status.rawValue)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(item.status.color.opacity(0.15))
                        .foregroundStyle(item.status.color)
                        .clipShape(Capsule())
                }
                
                HStack(spacing: 8) {
                    // Date
                    Text(item.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Note preview
                    if let note = item.note ?? item.textPayload, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    InboxView()
        .environmentObject(AppState())
}
