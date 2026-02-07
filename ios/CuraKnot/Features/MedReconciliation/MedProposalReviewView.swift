import SwiftUI

// MARK: - Med Proposal Review View

struct MedProposalReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    let proposals: [MedProposal]
    let onComplete: ([MedProposal]) -> Void
    
    @State private var reviewedProposals: [MedProposal]
    @State private var currentIndex = 0
    @State private var showingEditSheet = false
    @State private var isProcessing = false
    
    init(proposals: [MedProposal], onComplete: @escaping ([MedProposal]) -> Void) {
        self.proposals = proposals
        self.onComplete = onComplete
        self._reviewedProposals = State(initialValue: proposals)
    }
    
    var pendingProposals: [MedProposal] {
        reviewedProposals.filter { $0.status == .proposed }
    }
    
    var acceptedCount: Int {
        reviewedProposals.filter { $0.status == .accepted }.count
    }
    
    var rejectedCount: Int {
        reviewedProposals.filter { $0.status == .rejected }.count
    }
    
    var currentProposal: MedProposal? {
        guard currentIndex < pendingProposals.count else { return nil }
        return pendingProposals[currentIndex]
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress Header
                ProgressHeader(
                    total: reviewedProposals.count,
                    accepted: acceptedCount,
                    rejected: rejectedCount,
                    pending: pendingProposals.count
                )
                .padding()
                
                if let proposal = currentProposal {
                    // Current Proposal Card
                    ScrollView {
                        ProposalCard(proposal: proposal)
                            .padding()
                    }
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        // Accept Button
                        Button {
                            acceptProposal(proposal)
                        } label: {
                            Label("Accept", systemImage: "checkmark.circle.fill")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        
                        HStack(spacing: 12) {
                            // Edit Button
                            Button {
                                showingEditSheet = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            }
                            .buttonStyle(.bordered)
                            
                            // Reject Button
                            Button {
                                rejectProposal(proposal)
                            } label: {
                                Label("Skip", systemImage: "xmark")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }
                    .padding()
                } else {
                    // All Reviewed
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)
                        
                        Text("Review Complete")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        VStack(spacing: 8) {
                            Text("\(acceptedCount) medications added to binder")
                            Text("\(rejectedCount) skipped")
                                .foregroundStyle(.secondary)
                        }
                        
                        Button {
                            completeReview()
                        } label: {
                            Text("Done")
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
            .navigationTitle("Review Medications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                if let proposal = currentProposal {
                    EditProposalSheet(proposal: proposal) { editedProposal in
                        updateProposal(editedProposal)
                    }
                }
            }
        }
    }
    
    private func acceptProposal(_ proposal: MedProposal) {
        guard let index = reviewedProposals.firstIndex(where: { $0.id == proposal.id }) else { return }
        
        reviewedProposals[index].status = .accepted
        reviewedProposals[index].acceptedAt = Date()
        
        // TODO: Call accept_med_proposal RPC
        
        // Move to next
        if currentIndex >= pendingProposals.count {
            currentIndex = max(0, pendingProposals.count - 1)
        }
    }
    
    private func rejectProposal(_ proposal: MedProposal) {
        guard let index = reviewedProposals.firstIndex(where: { $0.id == proposal.id }) else { return }
        
        reviewedProposals[index].status = .rejected
        
        // TODO: Call reject_med_proposal RPC
        
        // Move to next
        if currentIndex >= pendingProposals.count {
            currentIndex = max(0, pendingProposals.count - 1)
        }
    }
    
    private func updateProposal(_ proposal: MedProposal) {
        guard let index = reviewedProposals.firstIndex(where: { $0.id == proposal.id }) else { return }
        reviewedProposals[index] = proposal
    }
    
    private func completeReview() {
        onComplete(reviewedProposals)
        dismiss()
    }
}

// MARK: - Progress Header

struct ProgressHeader: View {
    let total: Int
    let accepted: Int
    let rejected: Int
    let pending: Int
    
    var body: some View {
        HStack(spacing: 0) {
            ProgressItem(count: accepted, label: "Accepted", color: .green)
            ProgressItem(count: rejected, label: "Skipped", color: .red)
            ProgressItem(count: pending, label: "Pending", color: .blue)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ProgressItem: View {
    let count: Int
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Proposal Card

struct ProposalCard: View {
    let proposal: MedProposal
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "pills.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(proposal.proposedJson.name ?? "Unknown Medication")
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    if let dose = proposal.proposedJson.dose {
                        Text(dose)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Confidence indicator
                if let confidence = proposal.proposedJson.confidence?.name {
                    ConfidenceBadge(confidence: confidence)
                }
            }
            
            Divider()
            
            // Fields
            VStack(alignment: .leading, spacing: 12) {
                if let schedule = proposal.proposedJson.schedule {
                    FieldRow(label: "Schedule", value: schedule, confidence: proposal.proposedJson.confidence?.schedule)
                }
                
                if let purpose = proposal.proposedJson.purpose {
                    FieldRow(label: "Purpose", value: purpose, confidence: nil)
                }
                
                if let prescriber = proposal.proposedJson.prescriber {
                    FieldRow(label: "Prescriber", value: prescriber, confidence: nil)
                }
            }
            
            // Diff Info
            if let diff = proposal.diffJson {
                Divider()
                
                if diff.isNew == true {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.blue)
                        Text("New medication - not currently in binder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if diff.hasMatch == true {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.orange)
                            Text("Updates existing: \(diff.existingTitle ?? "medication")")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        
                        if diff.doseChanged == true {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Dose has changed")
                                    .font(.caption)
                            }
                        }
                        
                        if diff.scheduleChanged == true {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Schedule has changed")
                                    .font(.caption)
                            }
                        }
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Field Row

struct FieldRow: View {
    let label: String
    let value: String
    let confidence: Double?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack {
                Text(value)
                    .font(.body)
                
                if let conf = confidence, conf < 0.8 {
                    Image(systemName: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

// MARK: - Confidence Badge

struct ConfidenceBadge: View {
    let confidence: Double
    
    var color: Color {
        if confidence >= 0.9 { return .green }
        if confidence >= 0.7 { return .orange }
        return .red
    }
    
    var body: some View {
        Text("\(Int(confidence * 100))%")
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Edit Proposal Sheet

struct EditProposalSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let proposal: MedProposal
    let onSave: (MedProposal) -> Void
    
    @State private var name: String
    @State private var dose: String
    @State private var schedule: String
    @State private var purpose: String
    @State private var prescriber: String
    
    init(proposal: MedProposal, onSave: @escaping (MedProposal) -> Void) {
        self.proposal = proposal
        self.onSave = onSave
        self._name = State(initialValue: proposal.proposedJson.name ?? "")
        self._dose = State(initialValue: proposal.proposedJson.dose ?? "")
        self._schedule = State(initialValue: proposal.proposedJson.schedule ?? "")
        self._purpose = State(initialValue: proposal.proposedJson.purpose ?? "")
        self._prescriber = State(initialValue: proposal.proposedJson.prescriber ?? "")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    TextField("Name", text: $name)
                    TextField("Dose", text: $dose)
                }
                
                Section("Schedule") {
                    TextField("Schedule (e.g., twice daily)", text: $schedule)
                }
                
                Section("Additional Info") {
                    TextField("Purpose (optional)", text: $purpose)
                    TextField("Prescriber (optional)", text: $prescriber)
                }
            }
            .navigationTitle("Edit Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func saveChanges() {
        var updated = proposal
        updated.proposedJson.name = name
        updated.proposedJson.dose = dose.isEmpty ? nil : dose
        updated.proposedJson.schedule = schedule.isEmpty ? nil : schedule
        updated.proposedJson.purpose = purpose.isEmpty ? nil : purpose
        updated.proposedJson.prescriber = prescriber.isEmpty ? nil : prescriber
        
        onSave(updated)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    MedProposalReviewView(proposals: []) { _ in }
        .environmentObject(AppState())
}
