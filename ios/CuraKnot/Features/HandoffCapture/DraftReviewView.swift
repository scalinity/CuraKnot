import SwiftUI

// MARK: - Draft Review View

struct DraftReviewView: View {
    @Environment(\.dismiss) private var dismiss
    
    let handoffId: String
    @State private var draft: StructuredBrief
    @State private var isPublishing = false
    @State private var showConfirmation = false
    @State private var medChangesConfirmed = false
    
    init(handoffId: String, draft: StructuredBrief) {
        self.handoffId = handoffId
        self._draft = State(initialValue: draft)
    }
    
    var hasMedChanges: Bool {
        guard let changes = draft.changes?.medChanges else { return false }
        return !changes.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Title Section
                    EditableSection(title: "Title") {
                        TextField("Handoff title", text: $draft.title)
                            .font(.headline)
                    }
                    
                    // Summary Section
                    EditableSection(title: "Summary") {
                        TextEditor(text: Binding(
                            get: { draft.summary },
                            set: { draft.summary = $0 }
                        ))
                        .frame(minHeight: 100)
                        
                        HStack {
                            Spacer()
                            Text("\(draft.summary.count)/600")
                                .font(.caption)
                                .foregroundStyle(draft.summary.count > 600 ? .red : .secondary)
                        }
                    }
                    
                    // Status Section
                    if let status = draft.status {
                        StatusSection(status: Binding(
                            get: { status },
                            set: { draft.status = $0 }
                        ))
                    }
                    
                    // Med Changes Section
                    if let medChanges = draft.changes?.medChanges, !medChanges.isEmpty {
                        MedChangesSection(
                            medChanges: Binding(
                                get: { medChanges },
                                set: { draft.changes?.medChanges = $0 }
                            ),
                            confirmed: $medChangesConfirmed
                        )
                    }
                    
                    // Next Steps Section
                    if let nextSteps = draft.nextSteps, !nextSteps.isEmpty {
                        NextStepsSection(nextSteps: Binding(
                            get: { nextSteps },
                            set: { draft.nextSteps = $0 }
                        ))
                    }
                    
                    // Questions Section
                    if let questions = draft.questionsForClinician, !questions.isEmpty {
                        QuestionsSection(questions: Binding(
                            get: { questions },
                            set: { draft.questionsForClinician = $0 }
                        ))
                    }
                }
                .padding()
            }
            .navigationTitle("Review Draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Publish") {
                        if hasMedChanges && !medChangesConfirmed {
                            showConfirmation = true
                        } else {
                            publishHandoff()
                        }
                    }
                    .disabled(isPublishing || draft.title.isEmpty)
                }
            }
            .alert("Confirm Medication Changes", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Confirm & Publish") {
                    medChangesConfirmed = true
                    publishHandoff()
                }
            } message: {
                Text("This handoff contains medication changes. Please confirm they are accurate before publishing.")
            }
            .overlay {
                if isPublishing {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView("Publishing...")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    
    private func publishHandoff() {
        isPublishing = true
        // TODO: Call publish API
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isPublishing = false
            dismiss()
        }
    }
}

// MARK: - Editable Section

struct EditableSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            content()
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Status Section

struct StatusSection: View {
    @Binding var status: StructuredBrief.BriefStatus
    
    var body: some View {
        EditableSection(title: "Status") {
            VStack(alignment: .leading, spacing: 12) {
                if let moodEnergy = status.moodEnergy {
                    StatusRow(label: "Mood/Energy", value: moodEnergy)
                }
                
                if let pain = status.pain {
                    HStack {
                        Text("Pain Level")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(pain)/10")
                            .fontWeight(.medium)
                    }
                }
                
                if let appetite = status.appetite {
                    StatusRow(label: "Appetite", value: appetite)
                }
                
                if let sleep = status.sleep {
                    StatusRow(label: "Sleep", value: sleep)
                }
                
                if let mobility = status.mobility {
                    StatusRow(label: "Mobility", value: mobility)
                }
                
                if let safetyFlags = status.safetyFlags, !safetyFlags.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Safety Concerns")
                            .foregroundStyle(.secondary)
                        ForEach(safetyFlags, id: \.self) { flag in
                            Label(flag, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
    }
}

struct StatusRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }
}

// MARK: - Med Changes Section

struct MedChangesSection: View {
    @Binding var medChanges: [StructuredBrief.MedChange]
    @Binding var confirmed: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Medication Changes")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            
            VStack(spacing: 12) {
                ForEach(Array(medChanges.enumerated()), id: \.offset) { index, change in
                    MedChangeRow(change: change)
                }
                
                Divider()
                
                Toggle("I confirm these medication changes are accurate", isOn: $confirmed)
                    .font(.subheadline)
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(confirmed ? Color.green : Color.orange, lineWidth: 2)
            )
        }
    }
}

struct MedChangeRow: View {
    let change: StructuredBrief.MedChange
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(change.name)
                    .font(.headline)
                
                Text(changeTypeDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                if let details = change.details {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            changeIcon
        }
    }
    
    private var changeTypeDescription: String {
        switch change.change {
        case "START": return "Started"
        case "STOP": return "Stopped"
        case "DOSE": return "Dose changed"
        case "SCHEDULE": return "Schedule changed"
        default: return change.change
        }
    }
    
    @ViewBuilder
    private var changeIcon: some View {
        switch change.change {
        case "START":
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.green)
        case "STOP":
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.red)
        default:
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - Next Steps Section

struct NextStepsSection: View {
    @Binding var nextSteps: [StructuredBrief.NextStep]
    
    var body: some View {
        EditableSection(title: "Next Steps") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(nextSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.action)
                            
                            if let due = step.due {
                                Text("Due: \(due, style: .date)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if let priority = step.priority {
                            priorityBadge(priority)
                        }
                    }
                    
                    if index < nextSteps.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func priorityBadge(_ priority: StructuredBrief.Priority) -> some View {
        Text(priority.rawValue)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(priorityColor(priority).opacity(0.2), in: Capsule())
            .foregroundStyle(priorityColor(priority))
    }
    
    private func priorityColor(_ priority: StructuredBrief.Priority) -> Color {
        switch priority {
        case .high: return .red
        case .med: return .orange
        case .low: return .green
        }
    }
}

// MARK: - Questions Section

struct QuestionsSection: View {
    @Binding var questions: [StructuredBrief.ClinicalQuestion]
    
    var body: some View {
        EditableSection(title: "Questions for Clinician") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                    HStack(alignment: .top) {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundStyle(.purple)
                        
                        Text(question.question)
                    }
                    
                    if index < questions.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }
}

#Preview {
    let sampleDraft = StructuredBrief(
        handoffId: "test",
        circleId: "circle",
        patientId: "patient",
        createdBy: "user",
        createdAt: Date(),
        type: .visit,
        title: "Visit with Dr. Smith",
        summary: "Visited the doctor today for a routine checkup.",
        status: StructuredBrief.BriefStatus(
            moodEnergy: "Good spirits",
            pain: 3,
            appetite: "Normal",
            sleep: "7 hours",
            mobility: "Walking with cane",
            safetyFlags: nil
        ),
        changes: StructuredBrief.BriefChanges(
            medChanges: [
                StructuredBrief.MedChange(
                    name: "Lisinopril",
                    change: "DOSE",
                    details: "Increased from 10mg to 15mg",
                    effective: nil
                )
            ],
            symptomChanges: nil,
            carePlanChanges: nil
        ),
        questionsForClinician: nil,
        nextSteps: [
            StructuredBrief.NextStep(
                action: "Pick up new prescription",
                suggestedOwner: nil,
                due: Date().addingTimeInterval(86400),
                priority: .high
            )
        ],
        attachments: nil,
        keywords: ["checkup", "medication"],
        confidence: nil,
        revision: 1
    )
    
    DraftReviewView(handoffId: "test", draft: sampleDraft)
}
