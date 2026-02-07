import SwiftUI

// MARK: - Submission Review View

struct SubmissionReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    let submission: HelperSubmission
    let onUpdate: (HelperSubmission) -> Void
    
    @State private var reviewNote = ""
    @State private var isProcessing = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Submitter Info
                VStack(alignment: .leading, spacing: 8) {
                    Label("Submitted by", systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Text(submission.submitterName ?? "Unknown")
                            .font(.headline)
                        
                        if let role = submission.submitterRole {
                            Text("• \(role)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Text(submission.submittedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Content
                VStack(alignment: .leading, spacing: 12) {
                    if let title = submission.payloadJson.title {
                        Text(title)
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                    
                    if let summary = submission.payloadJson.summary {
                        Text(summary)
                            .font(.body)
                    }
                    
                    if let notes = submission.payloadJson.notes, !notes.isEmpty {
                        Divider()
                        Text("Additional Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(notes)
                            .font(.body)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Review Note
                VStack(alignment: .leading, spacing: 8) {
                    Text("Review Note (optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextField("Add a note about your decision", text: $reviewNote, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                }
                
                // Actions
                if submission.status == .pending {
                    VStack(spacing: 12) {
                        Button {
                            approveSubmission()
                        } label: {
                            HStack {
                                if isProcessing {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text("Approve & Create Handoff")
                            }
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(isProcessing)
                        
                        Button(role: .destructive) {
                            rejectSubmission()
                        } label: {
                            Text("Reject")
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isProcessing)
                    }
                } else {
                    // Already reviewed
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: submission.status == .approved ? "checkmark.circle.fill" : "xmark.circle.fill")
                            Text(submission.status == .approved ? "Approved" : "Rejected")
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(submission.status.color)
                        
                        if let reviewedAt = submission.reviewedAt {
                            Text("Reviewed \(reviewedAt, style: .relative)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if let note = submission.reviewNote, !note.isEmpty {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(submission.status.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
        .navigationTitle("Review Submission")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func approveSubmission() {
        isProcessing = true
        
        // TODO: Call review_helper_submission RPC with APPROVE
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isProcessing = false
            var updated = submission
            updated.status = .approved
            updated.reviewedAt = Date()
            updated.reviewNote = reviewNote.isEmpty ? nil : reviewNote
            onUpdate(updated)
            dismiss()
        }
    }
    
    private func rejectSubmission() {
        isProcessing = true
        
        // TODO: Call review_helper_submission RPC with REJECT
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isProcessing = false
            var updated = submission
            updated.status = .rejected
            updated.reviewedAt = Date()
            updated.reviewNote = reviewNote.isEmpty ? nil : reviewNote
            onUpdate(updated)
            dismiss()
        }
    }
}

// MARK: - New Helper Link View

struct NewHelperLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    let onSave: (HelperLink) -> Void
    
    @State private var name = ""
    @State private var selectedPatient: Patient?
    @State private var ttlDays = 30
    @State private var maxSubmissions = 100
    @State private var isSaving = false
    @State private var createdLink: HelperLink?
    
    let ttlOptions = [7, 14, 30, 60, 90]
    
    var body: some View {
        NavigationStack {
            if let link = createdLink {
                // Success view
                VStack(spacing: 24) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                    
                    Text("Link Created!")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    VStack(spacing: 12) {
                        Text("Share this link with the helper or facility:")
                            .foregroundStyle(.secondary)
                        
                        Text(link.shareURL)
                            .font(.caption)
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    HStack(spacing: 16) {
                        Button {
                            UIPasteboard.general.string = link.shareURL
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        
                        ShareLink(item: URL(string: link.shareURL)!) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    Button("Done") {
                        dismiss()
                    }
                    .padding(.top)
                }
                .padding()
            } else {
                Form {
                    Section {
                        TextField("Name (e.g., Sunrise Care Facility)", text: $name)
                        
                        Picker("Patient", selection: $selectedPatient) {
                            Text("Select Patient").tag(nil as Patient?)
                            ForEach(appState.patients) { patient in
                                Text(patient.displayName).tag(patient as Patient?)
                            }
                        }
                    }
                    
                    Section("Link Settings") {
                        Picker("Expires After", selection: $ttlDays) {
                            ForEach(ttlOptions, id: \.self) { days in
                                Text("\(days) days").tag(days)
                            }
                        }
                        
                        Stepper("Max Submissions: \(maxSubmissions)", value: $maxSubmissions, in: 10...500, step: 10)
                    }
                    
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.blue)
                            
                            Text("Anyone with this link can submit updates for the selected patient. Submissions require your approval.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("New Helper Link")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            createLink()
                        }
                        .disabled(selectedPatient == nil || isSaving)
                    }
                }
                .onAppear {
                    selectedPatient = appState.patients.first
                }
            }
        }
    }
    
    private func createLink() {
        guard let patient = selectedPatient else { return }
        isSaving = true
        
        // TODO: Call create_helper_link RPC
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isSaving = false
            
            let newLink = HelperLink(
                id: UUID(),
                circleId: UUID(uuidString: appState.currentCircle?.id ?? "") ?? UUID(),
                patientId: UUID(uuidString: patient.id) ?? UUID(),
                token: UUID().uuidString.prefix(24).lowercased(),
                name: name.isEmpty ? nil : name,
                expiresAt: Calendar.current.date(byAdding: .day, value: ttlDays, to: Date()) ?? Date(),
                maxSubmissions: maxSubmissions,
                submissionCount: 0,
                createdBy: UUID(uuidString: appState.currentUser?.id ?? "") ?? UUID(),
                createdAt: Date()
            )
            
            createdLink = newLink
            onSave(newLink)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SubmissionReviewView(
            submission: HelperSubmission(
                id: UUID(),
                circleId: UUID(),
                patientId: UUID(),
                helperLinkId: UUID(),
                submittedAt: Date(),
                status: .pending,
                payloadJson: HelperSubmission.SubmissionPayload(
                    title: "Daily Update",
                    summary: "Patient had a good day. Ate breakfast and lunch well. Walked in the hallway with assistance.",
                    notes: "Mentioned mild headache in the afternoon."
                ),
                submitterName: "Sarah Johnson",
                submitterRole: "CNA"
            )
        ) { _ in }
        .environmentObject(AppState())
    }
}
