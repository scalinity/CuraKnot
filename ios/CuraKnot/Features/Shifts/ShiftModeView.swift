import SwiftUI

// MARK: - Care Shift Model

struct CareShift: Identifiable, Codable {
    let id: UUID
    let circleId: UUID
    let patientId: UUID
    var ownerUserId: UUID
    var startAt: Date
    var endAt: Date
    var status: Status
    var checklistJson: [ChecklistItem]
    var summaryHandoffId: UUID?
    var notes: String?
    let createdAt: Date
    var updatedAt: Date
    
    enum Status: String, Codable {
        case scheduled = "SCHEDULED"
        case active = "ACTIVE"
        case completed = "COMPLETED"
        case canceled = "CANCELED"
        
        var displayName: String {
            switch self {
            case .scheduled: return "Scheduled"
            case .active: return "Active"
            case .completed: return "Completed"
            case .canceled: return "Canceled"
            }
        }
        
        var color: Color {
            switch self {
            case .scheduled: return .blue
            case .active: return .green
            case .completed: return .secondary
            case .canceled: return .red
            }
        }
    }
    
    struct ChecklistItem: Identifiable, Codable {
        let id: UUID
        var text: String
        var completed: Bool
        var completedAt: Date?
        
        init(id: UUID = UUID(), text: String, completed: Bool = false, completedAt: Date? = nil) {
            self.id = id
            self.text = text
            self.completed = completed
            self.completedAt = completedAt
        }
        
        enum CodingKeys: String, CodingKey {
            case id, text, completed
            case completedAt = "completed_at"
        }
    }
    
    var isActive: Bool {
        let now = Date()
        return startAt <= now && endAt > now && status != .completed && status != .canceled
    }
    
    var duration: String {
        let hours = Calendar.current.dateComponents([.hour], from: startAt, to: endAt).hour ?? 0
        return "\(hours)h"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case patientId = "patient_id"
        case ownerUserId = "owner_user_id"
        case startAt = "start_at"
        case endAt = "end_at"
        case status
        case checklistJson = "checklist_json"
        case summaryHandoffId = "summary_handoff_id"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Shift Mode View

struct ShiftModeView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentShift: CareShift?
    @State private var shiftChanges: ShiftChanges?
    @State private var showingSchedule = false
    @State private var showingDelta = false
    @State private var showingFinalize = false
    @State private var isLoading = false
    
    struct ShiftChanges {
        let since: Date
        let previousOwner: String?
        let handoffs: [HandoffSummary]
        let tasks: [TaskSummary]
        let medChanges: [MedChange]
        
        struct HandoffSummary: Identifiable {
            let id: UUID
            let type: String
            let title: String
            let createdBy: String
        }
        
        struct TaskSummary: Identifiable {
            let id: UUID
            let title: String
            let priority: String
        }
        
        struct MedChange: Identifiable {
            let id = UUID()
            let name: String
            let updatedAt: Date
        }
    }
    
    var body: some View {
        NavigationStack {
            if let shift = currentShift, shift.isActive {
                // Active Shift View
                ActiveShiftView(shift: shift, changes: shiftChanges) {
                    showingDelta = true
                } onFinalize: {
                    showingFinalize = true
                } onChecklistToggle: { item in
                    toggleChecklistItem(item)
                }
            } else if let shift = currentShift, shift.status == .scheduled {
                // Upcoming Shift
                UpcomingShiftView(shift: shift) {
                    startShift()
                }
            } else {
                // No Active Shift
                NoShiftView {
                    showingSchedule = true
                }
            }
        }
        .navigationTitle("Shift Mode")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSchedule = true
                } label: {
                    Image(systemName: "calendar")
                }
            }
        }
        .sheet(isPresented: $showingSchedule) {
            ShiftScheduleView()
        }
        .sheet(isPresented: $showingDelta) {
            if let changes = shiftChanges {
                ShiftDeltaView(changes: changes)
            }
        }
        .sheet(isPresented: $showingFinalize) {
            if let shift = currentShift {
                FinalizeShiftView(shift: shift) {
                    currentShift = nil
                }
            }
        }
        .task {
            await loadCurrentShift()
        }
    }
    
    private func loadCurrentShift() async {
        isLoading = true
        // TODO: Call get_current_shift RPC
        isLoading = false
    }
    
    private func startShift() {
        // TODO: Update shift status to ACTIVE
    }
    
    private func toggleChecklistItem(_ item: CareShift.ChecklistItem) {
        guard var shift = currentShift,
              let index = shift.checklistJson.firstIndex(where: { $0.id == item.id }) else { return }
        
        shift.checklistJson[index].completed.toggle()
        if shift.checklistJson[index].completed {
            shift.checklistJson[index].completedAt = Date()
        } else {
            shift.checklistJson[index].completedAt = nil
        }
        
        currentShift = shift
        // TODO: Persist to Supabase
    }
}

// MARK: - Active Shift View

struct ActiveShiftView: View {
    let shift: CareShift
    let changes: ShiftModeView.ShiftChanges?
    let onShowDelta: () -> Void
    let onFinalize: () -> Void
    let onChecklistToggle: (CareShift.ChecklistItem) -> Void
    
    var completedCount: Int {
        shift.checklistJson.filter { $0.completed }.count
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Shift Header
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundStyle(.green)
                        Text("Active Shift")
                            .fontWeight(.semibold)
                    }
                    .font(.headline)
                    
                    Text("\(shift.startAt, style: .time) - \(shift.endAt, style: .time)")
                        .font(.title2)
                    
                    Text("Ends \(shift.endAt, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                // Changes Summary
                if let changes = changes {
                    Button(action: onShowDelta) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("What's Changed")
                                    .font(.headline)
                                Text("Since \(changes.previousOwner ?? "last shift")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 12) {
                                ChangeBadge(count: changes.handoffs.count, label: "Updates")
                                ChangeBadge(count: changes.tasks.count, label: "Tasks")
                            }
                            
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                
                // Checklist
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Shift Checklist")
                            .font(.headline)
                        Spacer()
                        Text("\(completedCount)/\(shift.checklistJson.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    ForEach(shift.checklistJson) { item in
                        ChecklistRow(item: item) {
                            onChecklistToggle(item)
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                // Finalize Button
                Button(action: onFinalize) {
                    Label("End Shift & Create Summary", systemImage: "checkmark.circle")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}

// MARK: - Change Badge

struct ChangeBadge: View {
    let count: Int
    let label: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.headline)
            Text(label)
                .font(.caption2)
        }
        .foregroundStyle(.blue)
    }
}

// MARK: - Checklist Row

struct ChecklistRow: View {
    let item: CareShift.ChecklistItem
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.completed ? .green : .secondary)
                
                Text(item.text)
                    .strikethrough(item.completed)
                    .foregroundStyle(item.completed ? .secondary : .primary)
                
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Upcoming Shift View

struct UpcomingShiftView: View {
    let shift: CareShift
    let onStart: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            
            Text("Upcoming Shift")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(spacing: 8) {
                Text("\(shift.startAt, style: .date)")
                Text("\(shift.startAt, style: .time) - \(shift.endAt, style: .time)")
                    .font(.headline)
            }
            .foregroundStyle(.secondary)
            
            Text("Starts \(shift.startAt, style: .relative)")
                .font(.caption)
            
            Button(action: onStart) {
                Text("Start Shift Now")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - No Shift View

struct NoShiftView: View {
    let onSchedule: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.badge.clock")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Active Shift")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Schedule shifts to coordinate care coverage with your circle.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            
            Button(action: onSchedule) {
                Label("Schedule Shift", systemImage: "calendar.badge.plus")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    ShiftModeView()
        .environmentObject(AppState())
}
