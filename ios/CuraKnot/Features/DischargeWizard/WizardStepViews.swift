import SwiftUI

// MARK: - Step 1: Discharge Setup

struct DischargeSetupStep: View {
    @ObservedObject var viewModel: DischargeWizardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                StepHeader(
                    icon: "doc.text",
                    title: "Discharge Information",
                    subtitle: "Let's capture the basic details about this hospital stay"
                )

                // Facility name
                FormField(label: "Facility Name", required: true) {
                    TextField("Hospital or facility name", text: $viewModel.facilityName)
                        .textContentType(.organizationName)
                }

                // Discharge date
                FormField(label: "Discharge Date", required: true) {
                    DatePicker(
                        "",
                        selection: $viewModel.dischargeDate,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                }

                // Admission date (optional)
                FormField(label: "Admission Date", required: false) {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { viewModel.admissionDate ?? Date() },
                            set: { viewModel.admissionDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                }

                // Reason for stay
                FormField(label: "Reason for Stay", required: true) {
                    TextField("e.g., Hip replacement surgery", text: $viewModel.reasonForStay, axis: .vertical)
                        .lineLimit(2...4)
                }

                // Discharge type
                FormField(label: "Type of Discharge", required: true) {
                    DischargeTypePicker(selection: $viewModel.selectedDischargeType)
                }

                // Info callout
                InfoCallout(
                    icon: "lightbulb.fill",
                    text: "We'll use this information to provide a customized checklist based on the type of discharge."
                )
            }
            .padding()
        }
    }
}

// MARK: - Step 2: Medications

struct MedicationsStep: View {
    @ObservedObject var viewModel: DischargeWizardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                StepHeader(
                    icon: "pills.fill",
                    title: "Medications",
                    subtitle: "Review medication changes and reconcile with existing prescriptions"
                )

                // Checklist items for medications
                ChecklistSection(
                    category: .beforeLeaving,
                    items: viewModel.items(for: .beforeLeaving).filter { item in
                        item.itemText.lowercased().contains("medication") ||
                        item.itemText.lowercased().contains("prescri")
                    },
                    viewModel: viewModel
                )

                ChecklistSection(
                    category: .medications,
                    items: viewModel.items(for: .medications),
                    viewModel: viewModel
                )

                // Medication changes section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Medication Changes")
                            .font(.headline)

                        Spacer()

                        Button {
                            viewModel.showMedScanner = true
                        } label: {
                            Label("Scan List", systemImage: "camera.fill")
                                .font(.subheadline)
                        }
                    }

                    if viewModel.medicationChanges.isEmpty {
                        EmptyMedicationChangesView {
                            viewModel.showMedScanner = true
                        }
                    } else {
                        ForEach(viewModel.medicationChanges) { change in
                            MedicationChangeRow(
                                change: change,
                                onEdit: { viewModel.updateMedicationChange($0) },
                                onDelete: { viewModel.removeMedicationChange(change) }
                            )
                        }
                    }

                    Button {
                        let newChange = DischargeMedicationChange(
                            name: "",
                            changeType: .new
                        )
                        viewModel.addMedicationChange(newChange)
                    } label: {
                        Label("Add Medication Change", systemImage: "plus.circle.fill")
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                // Warning callout
                WarningCallout(
                    text: "Always verify medication changes with your healthcare provider before making any changes."
                )
            }
            .padding()
        }
        .sheet(isPresented: $viewModel.showMedScanner) {
            // TODO: Integrate with document scanner
            Text("Medication Scanner")
        }
    }
}

// MARK: - Step 3: Equipment

struct EquipmentStep: View {
    @ObservedObject var viewModel: DischargeWizardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                StepHeader(
                    icon: "cross.vial.fill",
                    title: "Equipment & Supplies",
                    subtitle: "Identify durable medical equipment and supplies needed at home"
                )

                // Equipment checklist
                ChecklistSection(
                    category: .equipment,
                    items: viewModel.items(for: .equipment),
                    viewModel: viewModel
                )

                // Resource links
                VStack(alignment: .leading, spacing: 12) {
                    Text("Helpful Resources")
                        .font(.headline)

                    ResourceLinkRow(
                        title: "Medicare DME Coverage",
                        icon: "doc.text",
                        url: "https://www.medicare.gov/coverage/durable-medical-equipment-dme-coverage"
                    )

                    ResourceLinkRow(
                        title: "Equipment Rental Options",
                        icon: "building.2",
                        url: nil
                    )
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
    }
}

// MARK: - Step 4: Home Preparation

struct HomePrepStep: View {
    @ObservedObject var viewModel: DischargeWizardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                StepHeader(
                    icon: "house.fill",
                    title: "Home Preparation",
                    subtitle: "Prepare the home environment for safe recovery"
                )

                // Home prep checklist
                ChecklistSection(
                    category: .homePrep,
                    items: viewModel.items(for: .homePrep),
                    viewModel: viewModel
                )

                // Safety tips
                VStack(alignment: .leading, spacing: 12) {
                    Text("Safety Tips")
                        .font(.headline)

                    SafetyTipRow(text: "Remove throw rugs and loose cords to prevent falls")
                    SafetyTipRow(text: "Ensure adequate lighting in hallways and stairs")
                    SafetyTipRow(text: "Place frequently used items within easy reach")
                    SafetyTipRow(text: "Consider a hospital bed or bed rails if recommended")
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
    }
}

// MARK: - Step 5: Care Schedule

struct CareScheduleStep: View {
    @ObservedObject var viewModel: DischargeWizardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                StepHeader(
                    icon: "calendar",
                    title: "Care Schedule",
                    subtitle: "Plan caregiver coverage for the first week at home"
                )

                // First 48 hours warning
                WarningCallout(
                    text: "The first 48-72 hours after discharge are the highest risk for complications. Plan for extra support during this time."
                )

                // Shift scheduler
                VStack(alignment: .leading, spacing: 16) {
                    Text("First Week Coverage")
                        .font(.headline)

                    ForEach(0..<7, id: \.self) { dayOffset in
                        ShiftDayRow(
                            dischargeDate: viewModel.dischargeDate,
                            dayOffset: dayOffset,
                            assignedMemberId: viewModel.shiftAssignments[dayOffset],
                            members: viewModel.circleMembers,
                            isHighPriority: dayOffset < 3,
                            onAssign: { memberId in
                                viewModel.assignShift(dayOffset: dayOffset, to: memberId)
                            }
                        )
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
    }
}

// MARK: - Step 6: Follow-ups

struct FollowUpsStep: View {
    @ObservedObject var viewModel: DischargeWizardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                StepHeader(
                    icon: "person.badge.clock",
                    title: "Follow-up Appointments",
                    subtitle: "Schedule necessary follow-up care and therapy"
                )

                // Before leaving checklist (appointment related)
                ChecklistSection(
                    category: .beforeLeaving,
                    items: viewModel.items(for: .beforeLeaving).filter { item in
                        item.itemText.lowercased().contains("follow") ||
                        item.itemText.lowercased().contains("schedule") ||
                        item.itemText.lowercased().contains("appointment")
                    },
                    viewModel: viewModel
                )

                // First week items
                ChecklistSection(
                    category: .firstWeek,
                    items: viewModel.items(for: .firstWeek),
                    viewModel: viewModel
                )

                // Reminder to add to calendar
                InfoCallout(
                    icon: "calendar.badge.plus",
                    text: "Don't forget to add follow-up appointments to your calendar. CuraKnot can sync with your calendar if you enable it in settings."
                )
            }
            .padding()
        }
    }
}

// MARK: - Step 7: Review

struct ReviewStep: View {
    @ObservedObject var viewModel: DischargeWizardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                StepHeader(
                    icon: "checkmark.circle.fill",
                    title: "Ready to Go Home!",
                    subtitle: "Review what we'll create for your care circle"
                )

                // Progress summary
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Checklist Progress")
                            .font(.headline)

                        Spacer()

                        Text(viewModel.checklistProgressText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: viewModel.checklistProgress)
                        .tint(viewModel.checklistProgress == 1 ? .green : .accentColor)
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                // Output preview
                if let summary = viewModel.outputSummary {
                    OutputPreviewCard(summary: summary)
                }

                // Discharge info summary
                DischargeInfoSummary(
                    facilityName: viewModel.facilityName,
                    dischargeDate: viewModel.dischargeDate,
                    reasonForStay: viewModel.reasonForStay,
                    dischargeType: viewModel.selectedDischargeType
                )

                // Medication changes summary
                if !viewModel.medicationChanges.isEmpty {
                    MedicationChangesSummary(changes: viewModel.medicationChanges)
                }

                // Shift summary
                if !viewModel.shiftAssignments.isEmpty {
                    ShiftAssignmentsSummary(
                        assignments: viewModel.shiftAssignments,
                        members: viewModel.circleMembers,
                        dischargeDate: viewModel.dischargeDate
                    )
                }
            }
            .padding()
        }
        .task {
            await viewModel.updateOutputPreview()
        }
    }
}

// MARK: - Supporting Views

struct StepHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)

                Text(title)
                    .font(.title2.bold())
            }

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct FormField<Content: View>: View {
    let label: String
    let required: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.subheadline.weight(.medium))

                if required {
                    Text("*")
                        .foregroundStyle(.red)
                }
            }

            content()
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct DischargeTypePicker: View {
    @Binding var selection: DischargeRecord.DischargeType

    var body: some View {
        VStack(spacing: 8) {
            ForEach(DischargeRecord.DischargeType.allCases, id: \.self) { type in
                DischargeTypeOption(
                    type: type,
                    isSelected: selection == type,
                    onSelect: { selection = type }
                )
            }
        }
    }
}

struct DischargeTypeOption: View {
    let type: DischargeRecord.DischargeType
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: type.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : .accentColor)
                    .frame(width: 30)

                Text(type.displayName)
                    .foregroundStyle(isSelected ? .white : .primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

struct InfoCallout: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.yellow)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct WarningCallout: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Checklist Section

struct ChecklistSection: View {
    let category: ChecklistCategory
    let items: [DischargeChecklistItem]
    @ObservedObject var viewModel: DischargeWizardViewModel

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: category.icon)
                        .foregroundStyle(Color.accentColor)

                    Text(category.displayName)
                        .font(.headline)

                    Spacer()

                    Text("\(items.filter(\.isCompleted).count)/\(items.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach(items) { item in
                    ChecklistItemRow(
                        item: item,
                        onToggle: {
                            Task { await viewModel.toggleItem(item) }
                        },
                        onConfigureTask: { createTask, assignee, dueDate in
                            Task {
                                await viewModel.updateItemTask(
                                    item,
                                    createTask: createTask,
                                    assignedTo: assignee,
                                    dueDate: dueDate
                                )
                            }
                        }
                    )
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct ChecklistItemRow: View {
    let item: DischargeChecklistItem
    let onToggle: () -> Void
    let onConfigureTask: (Bool, String?, Date?) -> Void

    @State private var showTaskConfig = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Button(action: onToggle) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(item.isCompleted ? .green : .secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.itemText)
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)

                    if item.createTask {
                        HStack {
                            Image(systemName: "arrow.right.circle")
                                .font(.caption)
                            Text("Creates task")
                                .font(.caption)
                            if let dueDate = item.dueDate {
                                Text("• Due \(dueDate, style: .date)")
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                }

                Spacer()

                Button {
                    showTaskConfig = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showTaskConfig) {
            TaskConfigSheet(
                item: item,
                onSave: onConfigureTask
            )
        }
    }
}

struct TaskConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: DischargeChecklistItem
    let onSave: (Bool, String?, Date?) -> Void

    @State private var createTask: Bool
    @State private var assignee: String = ""
    @State private var dueDate: Date

    init(item: DischargeChecklistItem, onSave: @escaping (Bool, String?, Date?) -> Void) {
        self.item = item
        self.onSave = onSave
        self._createTask = State(initialValue: item.createTask)
        self._dueDate = State(initialValue: item.dueDate ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Create Task", isOn: $createTask)

                if createTask {
                    Section("Task Details") {
                        DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Task Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(createTask, assignee.isEmpty ? nil : assignee, createTask ? dueDate : nil)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Medication Views

struct EmptyMedicationChangesView: View {
    let onScan: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.viewfinder")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("No medication changes recorded")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(action: onScan) {
                Label("Scan Medication List", systemImage: "camera.fill")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

struct MedicationChangeRow: View {
    let change: DischargeMedicationChange
    let onEdit: (DischargeMedicationChange) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Image(systemName: change.changeType.icon)
                .foregroundStyle(changeColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(change.name.isEmpty ? "New Medication" : change.name)
                    .font(.headline)

                Text(change.changeType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var changeColor: Color {
        switch change.changeType {
        case .new: return .green
        case .stopped: return .red
        case .doseChanged: return .orange
        case .scheduleChanged: return .blue
        }
    }
}

// MARK: - Shift Views

struct ShiftDayRow: View {
    let dischargeDate: Date
    let dayOffset: Int
    let assignedMemberId: String?
    let members: [WizardCircleMember]
    let isHighPriority: Bool
    let onAssign: (String?) -> Void

    private var date: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: dischargeDate) ?? dischargeDate
    }

    private var assignedMember: WizardCircleMember? {
        guard let id = assignedMemberId else { return nil }
        return members.first { $0.id == id }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(date, format: .dateTime.weekday(.wide))
                        .font(.headline)

                    if isHighPriority {
                        SwiftUI.Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(date, format: .dateTime.month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if dayOffset == 0 {
                    Text("Discharge Day")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            Menu {
                Button("Unassigned") {
                    onAssign(nil)
                }

                ForEach(members) { member in
                    Button(member.displayName) {
                        onAssign(member.id)
                    }
                }
            } label: {
                if let member = assignedMember {
                    HStack {
                        Text(member.initials)
                            .font(.caption.bold())
                            .padding(6)
                            .background(Color.accentColor, in: SwiftUI.Circle())
                            .foregroundStyle(.white)

                        Text(member.displayName)
                            .foregroundStyle(.primary)
                    }
                } else {
                    Text("Assign")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding()
        .background(
            isHighPriority ? Color.red.opacity(0.1) : Color(.tertiarySystemBackground),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}

// MARK: - Resource Views

struct ResourceLinkRow: View {
    let title: String
    let icon: String
    let url: String?

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)

            Text(title)

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SafetyTipRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(.green)

            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Review Step Views

struct OutputPreviewCard: View {
    let summary: DischargeOutputSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What We'll Create")
                .font(.headline)

            HStack(spacing: 16) {
                OutputStat(
                    icon: "checklist",
                    value: "\(summary.tasksToCreate)",
                    label: "Tasks"
                )

                OutputStat(
                    icon: "doc.text.fill",
                    value: "1",
                    label: "Handoff"
                )

                OutputStat(
                    icon: "calendar",
                    value: "\(summary.shiftsScheduled)",
                    label: "Shifts"
                )

                OutputStat(
                    icon: "folder.fill",
                    value: "\(summary.binderUpdates)",
                    label: "Binder"
                )
            }
        }
        .padding()
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct OutputStat: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)

            Text(value)
                .font(.title2.bold())

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct DischargeInfoSummary: View {
    let facilityName: String
    let dischargeDate: Date
    let reasonForStay: String
    let dischargeType: DischargeRecord.DischargeType

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Discharge Summary")
                .font(.headline)

            LabeledContent("Facility", value: facilityName)
            LabeledContent("Date", value: dischargeDate, format: .dateTime.month().day().year())
            LabeledContent("Reason", value: reasonForStay)
            LabeledContent("Type", value: dischargeType.displayName)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct MedicationChangesSummary: View {
    let changes: [DischargeMedicationChange]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Medication Changes")
                    .font(.headline)

                Spacer()

                Text("\(changes.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(changes) { change in
                HStack {
                    Image(systemName: change.changeType.icon)
                        .foregroundStyle(changeColor(for: change.changeType))

                    Text(change.name)

                    Spacer()

                    Text(change.changeType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func changeColor(for type: DischargeMedicationChange.ChangeType) -> Color {
        switch type {
        case .new: return .green
        case .stopped: return .red
        case .doseChanged: return .orange
        case .scheduleChanged: return .blue
        }
    }
}

struct ShiftAssignmentsSummary: View {
    let assignments: [Int: String]
    let members: [WizardCircleMember]
    let dischargeDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Shift Schedule")
                    .font(.headline)

                Spacer()

                Text("\(assignments.count) shifts")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(assignments.keys.sorted()), id: \.self) { dayOffset in
                if let memberId = assignments[dayOffset],
                   let member = members.first(where: { $0.id == memberId }) {
                    let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: dischargeDate) ?? dischargeDate

                    HStack {
                        Text(date, format: .dateTime.weekday(.abbreviated).month().day())

                        Spacer()

                        Text(member.displayName)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
