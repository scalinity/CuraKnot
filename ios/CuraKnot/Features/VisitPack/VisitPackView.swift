import SwiftUI

// MARK: - Appointment Pack Model

struct AppointmentPack: Identifiable, Codable {
    let id: UUID
    let circleId: UUID
    let patientId: UUID
    let createdBy: UUID
    let rangeStart: Date
    let rangeEnd: Date
    let template: String
    let contentJson: PackContent
    let pdfObjectKey: String
    let createdAt: Date
    
    struct PackContent: Codable {
        let patient: PatientInfo?
        let handoffs: [HandoffSummary]?
        let medChanges: [MedChange]?
        let openTasks: [TaskSummary]?
        let questions: [VisitQuestion]?
        let counts: ContentCounts?
        
        struct PatientInfo: Codable {
            let id: UUID?
            let name: String?
            let initials: String?
        }
        
        struct HandoffSummary: Codable {
            let id: UUID?
            let type: String?
            let title: String?
            let summary: String?
            let createdAt: Date?
            
            enum CodingKeys: String, CodingKey {
                case id, type, title, summary
                case createdAt = "created_at"
            }
        }
        
        struct MedChange: Codable {
            let name: String?
            let content: [String: Any]?
            let updatedAt: Date?
            
            enum CodingKeys: String, CodingKey {
                case name
                case updatedAt = "updated_at"
            }
            
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try container.decodeIfPresent(String.self, forKey: .name)
                updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
                content = nil
            }
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeIfPresent(name, forKey: .name)
                try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
            }
        }
        
        struct TaskSummary: Codable {
            let id: UUID?
            let title: String?
            let priority: String?
            let dueAt: Date?
            
            enum CodingKeys: String, CodingKey {
                case id, title, priority
                case dueAt = "due_at"
            }
        }
        
        struct VisitQuestion: Codable {
            let id: UUID?
            let question: String?
            let priority: String?
            let createdBy: UUID?
            
            enum CodingKeys: String, CodingKey {
                case id, question, priority
                case createdBy = "created_by"
            }
        }
        
        struct ContentCounts: Codable {
            let handoffs: Int?
            let medChanges: Int?
            let openTasks: Int?
            let questions: Int?
            
            enum CodingKeys: String, CodingKey {
                case handoffs
                case medChanges = "med_changes"
                case openTasks = "open_tasks"
                case questions
            }
        }
        
        enum CodingKeys: String, CodingKey {
            case patient, handoffs, questions, counts
            case medChanges = "med_changes"
            case openTasks = "open_tasks"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case patientId = "patient_id"
        case createdBy = "created_by"
        case rangeStart = "range_start"
        case rangeEnd = "range_end"
        case template
        case contentJson = "content_json"
        case pdfObjectKey = "pdf_object_key"
        case createdAt = "created_at"
    }
}

// MARK: - Visit Pack View

struct VisitPackView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedPatient: Patient?
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var selectedTemplate = "general"
    @State private var questions: [String] = []
    @State private var newQuestion = ""
    @State private var isGenerating = false
    @State private var generatedPack: GeneratedPackResult?
    @State private var showingPreview = false
    @State private var showingShareSheet = false
    
    struct GeneratedPackResult {
        let packId: UUID
        let pdfURL: URL?
        let shareLink: ShareLink?
        let contentSummary: ContentSummary
        
        struct ShareLink {
            let token: String
            let url: String
            let expiresAt: Date
        }
        
        struct ContentSummary {
            let handoffs: Int
            let medChanges: Int
            let openTasks: Int
            let questions: Int
        }
    }
    
    let templates = [
        ("general", "General Visit"),
        ("specialist", "Specialist Appointment"),
        ("emergency", "ER/Urgent Care"),
        ("follow_up", "Follow-up Visit")
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                // Patient Selection
                Section {
                    Picker("Patient", selection: $selectedPatient) {
                        Text("Select Patient").tag(nil as Patient?)
                        ForEach(appState.patients) { patient in
                            Text(patient.displayName).tag(patient as Patient?)
                        }
                    }
                }
                
                // Date Range
                Section("Time Period") {
                    DatePicker("From", selection: $startDate, displayedComponents: .date)
                    DatePicker("To", selection: $endDate, displayedComponents: .date)
                    
                    // Quick presets
                    HStack(spacing: 8) {
                        QuickDateButton(title: "1 Week") {
                            startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                        }
                        QuickDateButton(title: "2 Weeks") {
                            startDate = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
                        }
                        QuickDateButton(title: "1 Month") {
                            startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Template
                Section("Template") {
                    Picker("Template", selection: $selectedTemplate) {
                        ForEach(templates, id: \.0) { template in
                            Text(template.1).tag(template.0)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                // Questions to Ask
                Section("Questions to Ask") {
                    ForEach(questions.indices, id: \.self) { index in
                        HStack {
                            Text(questions[index])
                            Spacer()
                            Button {
                                questions.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    
                    HStack {
                        TextField("Add a question", text: $newQuestion)
                        Button {
                            if !newQuestion.isEmpty {
                                questions.append(newQuestion)
                                newQuestion = ""
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.blue)
                        }
                        .disabled(newQuestion.isEmpty)
                    }
                }
                
                // Generate Button
                Section {
                    Button {
                        generatePack()
                    } label: {
                        HStack {
                            Spacer()
                            if isGenerating {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isGenerating ? "Generating..." : "Generate Visit Pack")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(selectedPatient == nil || isGenerating)
                }
                
                // Generated Pack Result
                if let pack = generatedPack {
                    Section("Generated Pack") {
                        // Summary
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 16) {
                                SummaryBadge(count: pack.contentSummary.handoffs, label: "Updates")
                                SummaryBadge(count: pack.contentSummary.medChanges, label: "Med Changes")
                                SummaryBadge(count: pack.contentSummary.openTasks, label: "Tasks")
                                SummaryBadge(count: pack.contentSummary.questions, label: "Questions")
                            }
                        }
                        
                        // Actions
                        Button {
                            showingPreview = true
                        } label: {
                            Label("Preview", systemImage: "eye")
                        }
                        
                        Button {
                            showingShareSheet = true
                        } label: {
                            Label("Share PDF", systemImage: "square.and.arrow.up")
                        }
                        
                        if let shareLink = pack.shareLink {
                            Button {
                                UIPasteboard.general.string = shareLink.url
                            } label: {
                                Label("Copy Share Link", systemImage: "link")
                            }
                            
                            Text("Link expires \(shareLink.expiresAt, style: .relative)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Visit Pack")
            .sheet(isPresented: $showingPreview) {
                if let pack = generatedPack, let url = pack.pdfURL {
                    VisitPackPreviewView(url: url)
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let pack = generatedPack, let url = pack.pdfURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }
    
    private func generatePack() {
        guard selectedPatient != nil else { return }
        isGenerating = true
        
        // TODO: Call generate-appointment-pack edge function
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isGenerating = false
            generatedPack = GeneratedPackResult(
                packId: UUID(),
                pdfURL: nil,
                shareLink: GeneratedPackResult.ShareLink(
                    token: "abc123",
                    url: "https://app.curaknot.com/share/abc123",
                    expiresAt: Date().addingTimeInterval(86400)
                ),
                contentSummary: GeneratedPackResult.ContentSummary(
                    handoffs: 3,
                    medChanges: 1,
                    openTasks: 2,
                    questions: questions.count
                )
            )
        }
    }
}

// MARK: - Quick Date Button

struct QuickDateButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Summary Badge

struct SummaryBadge: View {
    let count: Int
    let label: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Visit Pack Preview View

struct VisitPackPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    
    var body: some View {
        NavigationStack {
            // TODO: WebView or PDFKit preview
            Text("Preview loading...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.secondary.opacity(0.1))
                .navigationTitle("Pack Preview")
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

// MARK: - Preview

#Preview {
    VisitPackView()
        .environmentObject(AppState())
}
