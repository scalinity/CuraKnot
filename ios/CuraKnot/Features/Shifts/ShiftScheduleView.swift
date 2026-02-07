import SwiftUI

// MARK: - Shift Schedule View

struct ShiftScheduleView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var shifts: [CareShift] = []
    @State private var selectedDate = Date()
    @State private var showingNewShift = false
    @State private var isLoading = false
    
    var shiftsForSelectedDate: [CareShift] {
        shifts.filter { shift in
            Calendar.current.isDate(shift.startAt, inSameDayAs: selectedDate)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Date Picker
                DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                
                Divider()
                
                // Shifts for selected date
                if shiftsForSelectedDate.isEmpty {
                    VStack(spacing: 16) {
                        Text("No shifts scheduled")
                            .foregroundStyle(.secondary)
                        
                        Button {
                            showingNewShift = true
                        } label: {
                            Label("Add Shift", systemImage: "plus")
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(shiftsForSelectedDate) { shift in
                            ShiftRow(shift: shift)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Shift Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewShift = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewShift) {
                NewShiftView(initialDate: selectedDate) { newShift in
                    shifts.append(newShift)
                }
            }
            .task {
                await loadShifts()
            }
        }
    }
    
    private func loadShifts() async {
        isLoading = true
        // TODO: Load from Supabase
        isLoading = false
    }
}

// MARK: - Shift Row

struct ShiftRow: View {
    let shift: CareShift
    
    var body: some View {
        HStack(spacing: 12) {
            // Time
            VStack(spacing: 2) {
                Text(shift.startAt, style: .time)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("-")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(shift.endAt, style: .time)
                    .font(.subheadline)
            }
            .frame(width: 60)
            
            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text(shift.duration)
                    .font(.headline)
                
                // TODO: Show owner name
                Text("Assigned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Status
            Text(shift.status.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(shift.status.color.opacity(0.15))
                .foregroundStyle(shift.status.color)
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }
}

// MARK: - New Shift View

struct NewShiftView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    let initialDate: Date
    let onSave: (CareShift) -> Void
    
    @State private var selectedPatient: Patient?
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var assignee: User?
    @State private var useTemplate = true
    @State private var checklistItems: [CareShift.ChecklistItem] = []
    @State private var newItemText = ""
    
    @State private var isSaving = false
    
    var body: some View {
        NavigationStack {
            Form {
                // Patient
                Section {
                    Picker("Patient", selection: $selectedPatient) {
                        Text("Select Patient").tag(nil as Patient?)
                        ForEach(appState.patients) { patient in
                            Text(patient.displayName).tag(patient as Patient?)
                        }
                    }
                }
                
                // Time
                Section("Shift Time") {
                    DatePicker("Start", selection: $startTime)
                    DatePicker("End", selection: $endTime)
                }
                
                // Assignee
                Section("Assignee") {
                    // TODO: Member picker
                    Text("Assign to yourself")
                        .foregroundStyle(.secondary)
                }
                
                // Checklist
                Section("Checklist") {
                    Toggle("Use default template", isOn: $useTemplate)
                    
                    if !useTemplate {
                        ForEach(checklistItems) { item in
                            HStack {
                                Text(item.text)
                                Spacer()
                                Button {
                                    checklistItems.removeAll { $0.id == item.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                        
                        HStack {
                            TextField("Add item", text: $newItemText)
                            Button {
                                if !newItemText.isEmpty {
                                    checklistItems.append(CareShift.ChecklistItem(text: newItemText))
                                    newItemText = ""
                                }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                            }
                            .disabled(newItemText.isEmpty)
                        }
                    }
                }
            }
            .navigationTitle("New Shift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createShift()
                    }
                    .disabled(selectedPatient == nil || isSaving)
                }
            }
            .onAppear {
                // Set initial times
                startTime = initialDate
                endTime = Calendar.current.date(byAdding: .hour, value: 4, to: initialDate) ?? initialDate
                selectedPatient = appState.patients.first
                
                // Default checklist items
                checklistItems = [
                    CareShift.ChecklistItem(text: "Check medications taken"),
                    CareShift.ChecklistItem(text: "Assess comfort and pain level"),
                    CareShift.ChecklistItem(text: "Review any new instructions"),
                    CareShift.ChecklistItem(text: "Note any changes or concerns")
                ]
            }
        }
    }
    
    private func createShift() {
        guard let patient = selectedPatient else { return }
        isSaving = true
        
        let shift = CareShift(
            id: UUID(),
            circleId: UUID(uuidString: appState.currentCircle?.id ?? "") ?? UUID(),
            patientId: UUID(uuidString: patient.id) ?? UUID(),
            ownerUserId: UUID(uuidString: appState.currentUser?.id ?? "") ?? UUID(),
            startAt: startTime,
            endAt: endTime,
            status: .scheduled,
            checklistJson: useTemplate ? checklistItems : checklistItems,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // TODO: Save to Supabase
        
        onSave(shift)
        dismiss()
    }
}

// MARK: - Shift Delta View

struct ShiftDeltaView: View {
    @Environment(\.dismiss) private var dismiss
    
    let changes: ShiftModeView.ShiftChanges
    
    var body: some View {
        NavigationStack {
            List {
                if !changes.handoffs.isEmpty {
                    Section("Recent Updates (\(changes.handoffs.count))") {
                        ForEach(changes.handoffs) { handoff in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(handoff.title)
                                    .font(.body)
                                HStack {
                                    Text(handoff.type)
                                    Text("•")
                                    Text(handoff.createdBy)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                if !changes.tasks.isEmpty {
                    Section("Tasks (\(changes.tasks.count))") {
                        ForEach(changes.tasks) { task in
                            HStack {
                                Text(task.title)
                                Spacer()
                                Text(task.priority)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                
                if !changes.medChanges.isEmpty {
                    Section("Medication Changes (\(changes.medChanges.count))") {
                        ForEach(changes.medChanges) { med in
                            HStack {
                                Text(med.name)
                                Spacer()
                                Text(med.updatedAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("What's Changed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Finalize Shift View

struct FinalizeShiftView: View {
    @Environment(\.dismiss) private var dismiss
    
    let shift: CareShift
    let onComplete: () -> Void
    
    @State private var notes = ""
    @State private var createHandoff = true
    @State private var isSaving = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Shift Summary") {
                    LabeledContent("Duration", value: shift.duration)
                    LabeledContent("Checklist", value: "\(shift.checklistJson.filter { $0.completed }.count)/\(shift.checklistJson.count) completed")
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
                
                Section {
                    Toggle("Create handoff summary", isOn: $createHandoff)
                }
                
                Section {
                    Button {
                        finalizeShift()
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                            }
                            Text(isSaving ? "Saving..." : "Complete Shift")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .navigationTitle("End Shift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func finalizeShift() {
        isSaving = true
        
        // TODO: Call finalize_shift RPC
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isSaving = false
            onComplete()
            dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    ShiftScheduleView()
        .environmentObject(AppState())
}
