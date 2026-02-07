import SwiftUI

// MARK: - Task List View

struct TaskListView: View {
    @EnvironmentObject var appState: AppState
    @State private var tasks: [CareTask] = []
    @State private var selectedView: TaskViewType = .mine
    @State private var showingNewTask = false
    
    enum TaskViewType: String, CaseIterable {
        case mine = "Mine"
        case all = "All"
        case overdue = "Overdue"
        case done = "Done"
    }
    
    var filteredTasks: [CareTask] {
        switch selectedView {
        case .mine:
            return tasks.filter { $0.ownerUserId == appState.currentUser?.id && $0.status == .open }
        case .all:
            return tasks.filter { $0.status == .open }
        case .overdue:
            return tasks.filter { $0.isOverdue }
        case .done:
            return tasks.filter { $0.status == .done }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented Control
                Picker("View", selection: $selectedView) {
                    ForEach(TaskViewType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Task List
                if filteredTasks.isEmpty {
                    EmptyStateView(
                        icon: "checklist",
                        title: emptyTitle,
                        message: emptyMessage,
                        actionTitle: "Create Task"
                    ) {
                        showingNewTask = true
                    }
                } else {
                    List {
                        ForEach(filteredTasks) { task in
                            TaskCell(task: task) {
                                completeTask(task)
                            }
                            .swipeActions(edge: .leading) {
                                Button("Done", systemImage: "checkmark") {
                                    completeTask(task)
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Snooze", systemImage: "clock") {
                                    // TODO: Snooze task
                                }
                                .tint(.orange)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewTask = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewTask) {
                TaskEditorView()
            }
        }
    }
    
    private var emptyTitle: String {
        switch selectedView {
        case .mine: return "No Tasks Assigned"
        case .all: return "No Open Tasks"
        case .overdue: return "Nothing Overdue"
        case .done: return "No Completed Tasks"
        }
    }
    
    private var emptyMessage: String {
        switch selectedView {
        case .mine: return "Tasks assigned to you will appear here."
        case .all: return "Create tasks to track care activities."
        case .overdue: return "Great job staying on top of things!"
        case .done: return "Completed tasks will appear here."
        }
    }
    
    private func completeTask(_ task: CareTask) {
        // TODO: Complete task via service
    }
}

// MARK: - Task Cell

struct TaskCell: View {
    let task: CareTask
    let onComplete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Completion Button
            Button {
                onComplete()
            } label: {
                Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.isComplete ? .green : .secondary)
            }
            .buttonStyle(.plain)
            
            // Task Info
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.isComplete)
                    .foregroundStyle(task.isComplete ? .secondary : .primary)
                
                HStack(spacing: 8) {
                    // Priority
                    priorityBadge
                    
                    // Due Date
                    if let dueText = task.formattedDueDate {
                        Label(dueText, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(task.isOverdue ? .red : .secondary)
                    }
                }
            }
            
            Spacer()
            
            // Linked handoff indicator
            if task.handoffId != nil {
                Image(systemName: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var priorityBadge: some View {
        switch task.priority {
        case .high:
            Label("High", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        case .med:
            EmptyView()
        case .low:
            Label("Low", systemImage: "arrow.down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Task Editor View

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var title = ""
    @State private var description = ""
    @State private var selectedPatient: Patient?
    @State private var assignee: User?
    @State private var dueDate: Date?
    @State private var hasDueDate = false
    @State private var priority: CareTask.Priority = .med
    @State private var enableReminder = true
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task title", text: $title)
                    
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section {
                    // Patient
                    Picker("Patient", selection: $selectedPatient) {
                        Text("None").tag(nil as Patient?)
                        ForEach(appState.patients) { patient in
                            Text(patient.displayName).tag(patient as Patient?)
                        }
                    }
                    
                    // Assignee
                    // TODO: Member picker
                    
                    // Priority
                    Picker("Priority", selection: $priority) {
                        ForEach(CareTask.Priority.allCases, id: \.self) { priority in
                            Text(priority.displayName).tag(priority)
                        }
                    }
                }
                
                Section {
                    Toggle("Set Due Date", isOn: $hasDueDate)
                    
                    if hasDueDate {
                        DatePicker(
                            "Due",
                            selection: Binding(
                                get: { dueDate ?? Date() },
                                set: { dueDate = $0 }
                            ),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        
                        Toggle("Reminder", isOn: $enableReminder)
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createTask()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
    
    private func createTask() {
        // TODO: Create task via service
        dismiss()
    }
}

#Preview {
    TaskListView()
        .environmentObject(AppState())
}
