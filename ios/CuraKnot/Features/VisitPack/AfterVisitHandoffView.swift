import SwiftUI

// MARK: - After Visit Handoff View

struct AfterVisitHandoffView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    let appointmentPackId: UUID?
    let patient: Patient?
    
    // Visit outcomes
    @State private var visitType = "APPOINTMENT"
    @State private var providerName = ""
    @State private var visitDate = Date()
    @State private var summary = ""
    
    // Decisions made
    @State private var decisions: [Decision] = []
    @State private var newDecisionText = ""
    
    // Med changes
    @State private var medChanges: [MedChangeEntry] = []
    @State private var showingAddMedChange = false
    
    // Follow-ups
    @State private var followUps: [FollowUp] = []
    @State private var newFollowUpText = ""
    @State private var newFollowUpDate: Date?
    
    // Questions answered
    @State private var questionsAnswered: [QuestionAnswer] = []
    
    @State private var isSaving = false
    
    struct Decision: Identifiable {
        let id = UUID()
        var text: String
        var createTask: Bool = false
    }
    
    struct MedChangeEntry: Identifiable {
        let id = UUID()
        var medName: String
        var changeType: String
        var details: String
    }
    
    struct FollowUp: Identifiable {
        let id = UUID()
        var text: String
        var dueDate: Date?
    }
    
    struct QuestionAnswer: Identifiable {
        let id = UUID()
        var questionId: UUID
        var question: String
        var answer: String
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Visit Info
                Section("Visit Information") {
                    Picker("Type", selection: $visitType) {
                        Text("Appointment").tag("APPOINTMENT")
                        Text("ER/Urgent").tag("ER")
                        Text("Specialist").tag("SPECIALIST")
                        Text("Telehealth").tag("TELEHEALTH")
                    }
                    
                    TextField("Provider / Facility", text: $providerName)
                    
                    DatePicker("Visit Date", selection: $visitDate, displayedComponents: [.date, .hourAndMinute])
                }
                
                // Summary
                Section("Summary") {
                    TextEditor(text: $summary)
                        .frame(minHeight: 100)
                }
                
                // Decisions Made
                Section("Decisions Made") {
                    ForEach(decisions.indices, id: \.self) { index in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(decisions[index].text)
                            Spacer()
                            Toggle("Task", isOn: $decisions[index].createTask)
                                .labelsHidden()
                        }
                    }
                    
                    HStack {
                        TextField("Add decision", text: $newDecisionText)
                        Button {
                            if !newDecisionText.isEmpty {
                                decisions.append(Decision(text: newDecisionText))
                                newDecisionText = ""
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newDecisionText.isEmpty)
                    }
                }
                
                // Medication Changes
                Section("Medication Changes") {
                    ForEach(medChanges) { change in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(change.medName)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(change.changeType)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(changeTypeColor(change.changeType).opacity(0.15))
                                    .foregroundStyle(changeTypeColor(change.changeType))
                                    .clipShape(Capsule())
                            }
                            if !change.details.isEmpty {
                                Text(change.details)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    Button {
                        showingAddMedChange = true
                    } label: {
                        Label("Add Medication Change", systemImage: "pills")
                    }
                }
                
                // Follow-ups
                Section("Follow-up Actions") {
                    ForEach(followUps) { followUp in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(followUp.text)
                            if let date = followUp.dueDate {
                                Text("Due: \(date, style: .date)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    HStack {
                        TextField("Add follow-up task", text: $newFollowUpText)
                        Button {
                            if !newFollowUpText.isEmpty {
                                followUps.append(FollowUp(text: newFollowUpText, dueDate: nil))
                                newFollowUpText = ""
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newFollowUpText.isEmpty)
                    }
                }
                
                // Questions that were answered
                if !questionsAnswered.isEmpty {
                    Section("Questions Answered") {
                        ForEach(questionsAnswered) { qa in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(qa.question)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(qa.answer)
                                    .font(.body)
                            }
                        }
                    }
                }
            }
            .navigationTitle("After-Visit Handoff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Publish") {
                        publishHandoff()
                    }
                    .disabled(summary.isEmpty || isSaving)
                }
            }
            .sheet(isPresented: $showingAddMedChange) {
                AddMedChangeSheet { change in
                    medChanges.append(change)
                }
            }
        }
    }
    
    private func changeTypeColor(_ type: String) -> Color {
        switch type.uppercased() {
        case "START": return .green
        case "STOP": return .red
        case "DOSE": return .orange
        case "SCHEDULE": return .blue
        default: return .secondary
        }
    }
    
    private func publishHandoff() {
        isSaving = true
        
        // TODO: Create handoff with after-visit template
        // Include: summary, decisions, med changes, follow-ups
        // Create tasks for follow-ups and flagged decisions
        // Update binder meds if med changes
        // Mark questions as answered
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - Add Med Change Sheet

struct AddMedChangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let onAdd: (AfterVisitHandoffView.MedChangeEntry) -> Void
    
    @State private var medName = ""
    @State private var changeType = "START"
    @State private var details = ""
    
    let changeTypes = ["START", "STOP", "DOSE", "SCHEDULE", "OTHER"]
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Medication Name", text: $medName)
                
                Picker("Change Type", selection: $changeType) {
                    ForEach(changeTypes, id: \.self) { type in
                        Text(type.capitalized).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                
                TextField("Details (e.g., new dosage)", text: $details, axis: .vertical)
                    .lineLimit(2...4)
            }
            .navigationTitle("Medication Change")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(AfterVisitHandoffView.MedChangeEntry(
                            medName: medName,
                            changeType: changeType,
                            details: details
                        ))
                        dismiss()
                    }
                    .disabled(medName.isEmpty)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AfterVisitHandoffView(appointmentPackId: nil, patient: nil)
        .environmentObject(AppState())
}
