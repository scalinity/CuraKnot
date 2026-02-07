import SwiftUI

// MARK: - Triage Destination

enum TriageDestination: String, CaseIterable {
    case handoff = "Handoff"
    case task = "Task"
    case binder = "Binder"
    case archive = "Archive"
    
    var icon: String {
        switch self {
        case .handoff: return "doc.text"
        case .task: return "checklist"
        case .binder: return "folder"
        case .archive: return "archivebox"
        }
    }
    
    var description: String {
        switch self {
        case .handoff: return "Create a draft handoff from this item"
        case .task: return "Create a task for follow-up"
        case .binder: return "Save to the care binder"
        case .archive: return "Archive without action"
        }
    }
    
    var apiValue: String {
        switch self {
        case .handoff: return "HANDOFF"
        case .task: return "TASK"
        case .binder: return "BINDER"
        case .archive: return "ARCHIVE"
        }
    }
}

// MARK: - Triage Sheet

struct TriageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    let item: InboxItem
    let onComplete: (InboxItem) -> Void
    
    @State private var selectedDestination: TriageDestination?
    @State private var showingDetails = false
    @State private var isProcessing = false
    
    // Handoff options
    @State private var handoffType = "OTHER"
    @State private var selectedPatient: Patient?
    
    // Task options
    @State private var taskOwner: User?
    @State private var taskDueDate: Date?
    @State private var hasDueDate = false
    @State private var taskPriority = "MED"
    
    // Common
    @State private var note = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Item Preview
                itemPreview
                    .padding()
                
                Divider()
                
                // Destination Selection
                if !showingDetails {
                    destinationPicker
                } else if let destination = selectedDestination {
                    destinationDetails(for: destination)
                }
            }
            .navigationTitle("Route Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                if showingDetails {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation {
                                showingDetails = false
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    if showingDetails {
                        Button("Confirm") {
                            processItem()
                        }
                        .disabled(isProcessing)
                    }
                }
            }
        }
        .onAppear {
            selectedPatient = item.patientId.flatMap { uuid in appState.patients.first { $0.id == uuid.uuidString } }
        }
    }
    
    // MARK: - Item Preview
    
    private var itemPreview: some View {
        HStack(spacing: 12) {
            // Kind Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 48, height: 48)
                
                Image(systemName: item.kind.icon)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title ?? item.kind.displayName)
                    .font(.headline)
                
                if let note = item.note ?? item.textPayload {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Text(item.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Destination Picker
    
    private var destinationPicker: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(TriageDestination.allCases, id: \.self) { destination in
                    DestinationCard(
                        destination: destination,
                        isSelected: selectedDestination == destination
                    ) {
                        selectedDestination = destination
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingDetails = true
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Destination Details
    
    @ViewBuilder
    private func destinationDetails(for destination: TriageDestination) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                switch destination {
                case .handoff:
                    handoffOptions
                case .task:
                    taskOptions
                case .binder:
                    binderOptions
                case .archive:
                    archiveOptions
                }
                
                // Common note field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Note (optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextField("Add a note about this decision", text: $note, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Handoff Options
    
    private var handoffOptions: some View {
        VStack(spacing: 16) {
            GroupBox("Handoff Type") {
                Picker("Type", selection: $handoffType) {
                    Text("Visit").tag("VISIT")
                    Text("Call").tag("CALL")
                    Text("Appointment").tag("APPOINTMENT")
                    Text("Facility Update").tag("FACILITY_UPDATE")
                    Text("Other").tag("OTHER")
                }
                .pickerStyle(.segmented)
            }
            
            GroupBox("Patient") {
                Picker("Patient", selection: $selectedPatient) {
                    Text("Select Patient").tag(nil as Patient?)
                    ForEach(appState.patients) { patient in
                        Text(patient.displayName).tag(patient as Patient?)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
    
    // MARK: - Task Options
    
    private var taskOptions: some View {
        VStack(spacing: 16) {
            GroupBox("Assign To") {
                // TODO: Member picker
                Text("Assign to yourself")
                    .foregroundStyle(.secondary)
            }
            
            GroupBox("Priority") {
                Picker("Priority", selection: $taskPriority) {
                    Text("Low").tag("LOW")
                    Text("Medium").tag("MED")
                    Text("High").tag("HIGH")
                }
                .pickerStyle(.segmented)
            }
            
            GroupBox("Due Date") {
                VStack {
                    Toggle("Set Due Date", isOn: $hasDueDate)
                    
                    if hasDueDate {
                        DatePicker(
                            "Due",
                            selection: Binding(
                                get: { taskDueDate ?? Date() },
                                set: { taskDueDate = $0 }
                            ),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Binder Options
    
    private var binderOptions: some View {
        VStack(spacing: 16) {
            GroupBox("Patient") {
                Picker("Patient", selection: $selectedPatient) {
                    Text("No Patient").tag(nil as Patient?)
                    ForEach(appState.patients) { patient in
                        Text(patient.displayName).tag(patient as Patient?)
                    }
                }
                .pickerStyle(.menu)
            }
            
            HStack(spacing: 12) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                
                Text("This item will be saved as a \(item.kind == .text ? "note" : "document") in the binder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    
    // MARK: - Archive Options
    
    private var archiveOptions: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "archivebox")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Archive This Item")
                        .font(.headline)
                    Text("The item will be moved to the archive. You can optionally add a note explaining why.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Process Item
    
    private func processItem() {
        guard let destination = selectedDestination else { return }
        
        isProcessing = true
        
        // Build destination data
        var destinationData: [String: Any] = [:]
        
        switch destination {
        case .handoff:
            destinationData["type"] = handoffType
            if let patientId = selectedPatient?.id {
                destinationData["patient_id"] = patientId
            }
        case .task:
            if let ownerId = taskOwner?.id ?? appState.currentUser?.id {
                destinationData["owner_user_id"] = ownerId
            }
            destinationData["priority"] = taskPriority
            if hasDueDate, let due = taskDueDate {
                destinationData["due_at"] = ISO8601DateFormatter().string(from: due)
            }
        case .binder, .archive:
            break
        }
        
        // TODO: Call triage-inbox-item edge function
        
        // Update local state
        var updatedItem = item
        updatedItem.status = .triaged
        updatedItem.updatedAt = Date()
        
        onComplete(updatedItem)
        dismiss()
    }
}

// MARK: - Destination Card

struct DestinationCard: View {
    let destination: TriageDestination
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    SwiftUI.Circle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: destination.icon)
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(destination.rawValue)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(destination.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    TriageSheet(
        item: InboxItem(
            id: UUID(),
            circleId: UUID(),
            patientId: nil,
            createdBy: UUID(),
            kind: .photo,
            status: .new,
            title: "Prescription Photo",
            note: "New medication from Dr. Smith",
            createdAt: Date(),
            updatedAt: Date()
        )
    ) { _ in }
    .environmentObject(AppState())
}
