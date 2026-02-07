import SwiftUI

// MARK: - Helper Link Model

struct HelperLink: Identifiable, Codable {
    let id: UUID
    let circleId: UUID
    let patientId: UUID
    let token: String
    var name: String?
    let expiresAt: Date
    var revokedAt: Date?
    var maxSubmissions: Int
    var submissionCount: Int
    var lastUsedAt: Date?
    let createdBy: UUID
    let createdAt: Date
    
    var isActive: Bool {
        revokedAt == nil && expiresAt > Date()
    }
    
    var shareURL: String {
        "https://app.curaknot.com/helper/\(token)"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case patientId = "patient_id"
        case token, name
        case expiresAt = "expires_at"
        case revokedAt = "revoked_at"
        case maxSubmissions = "max_submissions"
        case submissionCount = "submission_count"
        case lastUsedAt = "last_used_at"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}

struct HelperSubmission: Identifiable, Codable {
    let id: UUID
    let circleId: UUID
    let patientId: UUID
    let helperLinkId: UUID
    let submittedAt: Date
    var status: Status
    let payloadJson: SubmissionPayload
    var submitterName: String?
    var submitterRole: String?
    var reviewedBy: UUID?
    var reviewedAt: Date?
    var reviewNote: String?
    var resultHandoffId: UUID?
    
    enum Status: String, Codable {
        case pending = "PENDING"
        case approved = "APPROVED"
        case rejected = "REJECTED"
        
        var color: Color {
            switch self {
            case .pending: return .orange
            case .approved: return .green
            case .rejected: return .red
            }
        }
    }
    
    struct SubmissionPayload: Codable {
        var title: String?
        var summary: String?
        var updateType: String?
        var notes: String?
        
        enum CodingKeys: String, CodingKey {
            case title, summary, notes
            case updateType = "update_type"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case patientId = "patient_id"
        case helperLinkId = "helper_link_id"
        case submittedAt = "submitted_at"
        case status
        case payloadJson = "payload_json"
        case submitterName = "submitter_name"
        case submitterRole = "submitter_role"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case reviewNote = "review_note"
        case resultHandoffId = "result_handoff_id"
    }
}

// MARK: - Helper Admin View

struct HelperAdminView: View {
    @EnvironmentObject var appState: AppState
    @State private var links: [HelperLink] = []
    @State private var submissions: [HelperSubmission] = []
    @State private var selectedTab = 0
    @State private var showingNewLink = false
    @State private var isLoading = false
    
    var pendingSubmissions: [HelperSubmission] {
        submissions.filter { $0.status == .pending }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab Picker
                Picker("View", selection: $selectedTab) {
                    Text("Links (\(links.filter { $0.isActive }.count))").tag(0)
                    Text("Pending (\(pendingSubmissions.count))").tag(1)
                    Text("All Submissions").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content
                if isLoading {
                    ProgressView()
                        .frame(maxHeight: .infinity)
                } else {
                    switch selectedTab {
                    case 0:
                        linksView
                    case 1:
                        pendingView
                    default:
                        allSubmissionsView
                    }
                }
            }
            .navigationTitle("Helper Portal")
            .toolbar {
                if selectedTab == 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingNewLink = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingNewLink) {
                NewHelperLinkView { newLink in
                    links.insert(newLink, at: 0)
                }
            }
            .task {
                await loadData()
            }
        }
    }
    
    // MARK: - Links View
    
    private var linksView: some View {
        Group {
            if links.isEmpty {
                EmptyStateView(
                    icon: "link.badge.plus",
                    title: "No Helper Links",
                    message: "Create links to allow facility staff to submit updates.",
                    actionTitle: "Create Link"
                ) {
                    showingNewLink = true
                }
            } else {
                List {
                    ForEach(links) { link in
                        HelperLinkRow(link: link) {
                            revokeLink(link)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    // MARK: - Pending View
    
    private var pendingView: some View {
        Group {
            if pendingSubmissions.isEmpty {
                EmptyStateView(
                    icon: "tray",
                    title: "No Pending Submissions",
                    message: "Submissions from helpers will appear here for review."
                )
            } else {
                List {
                    ForEach(pendingSubmissions) { submission in
                        NavigationLink {
                            SubmissionReviewView(submission: submission) { updated in
                                if let index = submissions.firstIndex(where: { $0.id == updated.id }) {
                                    submissions[index] = updated
                                }
                            }
                        } label: {
                            SubmissionRow(submission: submission)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    // MARK: - All Submissions View
    
    private var allSubmissionsView: some View {
        Group {
            if submissions.isEmpty {
                EmptyStateView(
                    icon: "doc.plaintext",
                    title: "No Submissions",
                    message: "Helper submissions will appear here."
                )
            } else {
                List {
                    ForEach(submissions) { submission in
                        SubmissionRow(submission: submission)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    private func loadData() async {
        isLoading = true
        // TODO: Load from Supabase
        isLoading = false
    }
    
    private func revokeLink(_ link: HelperLink) {
        // TODO: Call revoke function
    }
}

// MARK: - Helper Link Row

struct HelperLinkRow: View {
    let link: HelperLink
    let onRevoke: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(link.name ?? "Helper Link")
                    .font(.headline)
                
                Spacer()
                
                if link.isActive {
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text(link.revokedAt != nil ? "Revoked" : "Expired")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            
            HStack(spacing: 12) {
                Label("\(link.submissionCount)", systemImage: "doc.text")
                Label("Expires \(link.expiresAt, style: .relative)", systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            
            if link.isActive {
                HStack {
                    Button {
                        UIPasteboard.general.string = link.shareURL
                    } label: {
                        Label("Copy Link", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(role: .destructive) {
                        onRevoke()
                    } label: {
                        Label("Revoke", systemImage: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Submission Row

struct SubmissionRow: View {
    let submission: HelperSubmission
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(submission.payloadJson.title ?? "Update")
                    .font(.body)
                
                Spacer()
                
                Text(submission.status.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(submission.status.color.opacity(0.15))
                    .foregroundStyle(submission.status.color)
                    .clipShape(Capsule())
            }
            
            HStack {
                if let name = submission.submitterName {
                    Text(name)
                }
                if let role = submission.submitterRole {
                    Text("• \(role)")
                }
                Text("• \(submission.submittedAt, style: .relative)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    HelperAdminView()
        .environmentObject(AppState())
}
