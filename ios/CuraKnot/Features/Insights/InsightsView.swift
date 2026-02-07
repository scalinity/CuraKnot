import SwiftUI

// MARK: - Insight Models

struct InsightDigest: Identifiable, Codable {
    let id: UUID
    let circleId: UUID
    let patientId: UUID?
    let periodStart: Date
    let periodEnd: Date
    let digestJson: DigestContent
    let createdAt: Date
    
    struct DigestContent: Codable {
        let summary: Summary?
        let highlights: [Highlight]?
        
        struct Summary: Codable {
            let handoffs: Int?
            let tasksCompleted: Int?
            let tasksCreated: Int?
            let tasksOverdue: Int?
            let medChanges: Int?
            
            enum CodingKeys: String, CodingKey {
                case handoffs
                case tasksCompleted = "tasks_completed"
                case tasksCreated = "tasks_created"
                case tasksOverdue = "tasks_overdue"
                case medChanges = "med_changes"
            }
        }
        
        struct Highlight: Codable {
            let title: String?
            let type: String?
            let createdAt: Date?
            
            enum CodingKeys: String, CodingKey {
                case title, type
                case createdAt = "created_at"
            }
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case patientId = "patient_id"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case digestJson = "digest_json"
        case createdAt = "created_at"
    }
}

struct AlertEvent: Identifiable, Codable {
    let id: UUID
    let circleId: UUID
    let patientId: UUID?
    let ruleKey: String
    let firedAt: Date
    let payloadJson: [String: Any]
    var status: Status
    
    enum Status: String, Codable {
        case open = "OPEN"
        case acknowledged = "ACKNOWLEDGED"
        case dismissed = "DISMISSED"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case patientId = "patient_id"
        case ruleKey = "rule_key"
        case firedAt = "fired_at"
        case status
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        circleId = try container.decode(UUID.self, forKey: .circleId)
        patientId = try container.decodeIfPresent(UUID.self, forKey: .patientId)
        ruleKey = try container.decode(String.self, forKey: .ruleKey)
        firedAt = try container.decode(Date.self, forKey: .firedAt)
        status = try container.decode(Status.self, forKey: .status)
        payloadJson = [:]
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(circleId, forKey: .circleId)
        try container.encodeIfPresent(patientId, forKey: .patientId)
        try container.encode(ruleKey, forKey: .ruleKey)
        try container.encode(firedAt, forKey: .firedAt)
        try container.encode(status, forKey: .status)
    }
    
    init(id: UUID, circleId: UUID, patientId: UUID?, ruleKey: String, firedAt: Date, payloadJson: [String: Any], status: Status) {
        self.id = id
        self.circleId = circleId
        self.patientId = patientId
        self.ruleKey = ruleKey
        self.firedAt = firedAt
        self.payloadJson = payloadJson
        self.status = status
    }
    
    var displayTitle: String {
        switch ruleKey {
        case "OVERDUE_TASKS": return "Overdue Tasks"
        case "STALENESS": return "No Recent Updates"
        case "UNCONFIRMED_MEDS": return "Unconfirmed Medications"
        default: return ruleKey
        }
    }
    
    var icon: String {
        switch ruleKey {
        case "OVERDUE_TASKS": return "exclamationmark.circle"
        case "STALENESS": return "clock.badge.exclamationmark"
        case "UNCONFIRMED_MEDS": return "pills"
        default: return "bell"
        }
    }
    
    var color: Color {
        switch ruleKey {
        case "OVERDUE_TASKS": return .red
        case "STALENESS": return .orange
        default: return .blue
        }
    }
}

// MARK: - Insights View

struct InsightsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dependencies: DependencyContainer
    @State private var latestDigest: InsightDigest?
    @State private var alerts: [AlertEvent] = []
    @State private var showingAlertRules = false
    @State private var isLoading = false

    /// Optional patient for symptom patterns (passed from patient context)
    var patient: Patient?
    var circleId: UUID?

    var openAlerts: [AlertEvent] {
        alerts.filter { $0.status == .open }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Symptom Patterns Section (Premium Feature)
                    if let patient = patient, let circleId = circleId {
                        symptomPatternsLink(patient: patient, circleId: circleId)
                    }

                    // Active Alerts
                    if !openAlerts.isEmpty {
                        AlertsSection(alerts: openAlerts) { alert in
                            dismissAlert(alert)
                        }
                    }

                    // Weekly Digest
                    if let digest = latestDigest {
                        DigestCard(digest: digest)
                    }

                    // Quick Stats
                    QuickStatsSection()
                }
                .padding()
            }
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAlertRules = true
                    } label: {
                        Image(systemName: "bell.badge")
                    }
                }
            }
            .sheet(isPresented: $showingAlertRules) {
                AlertRulesConfigView()
            }
            .task {
                await loadData()
            }
        }
    }

    // MARK: - Symptom Patterns Link

    @ViewBuilder
    private func symptomPatternsLink(patient: Patient, circleId: UUID) -> some View {
        NavigationLink {
            SymptomPatternsView(
                patient: patient,
                circleId: circleId,
                service: dependencies.symptomPatternsService
            )
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .foregroundStyle(.purple)
                    .frame(width: 44, height: 44)
                    .background(Color.purple.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Symptom Patterns")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("View detected patterns from handoffs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
    
    private func loadData() async {
        isLoading = true
        // TODO: Load from Supabase
        isLoading = false
    }
    
    private func dismissAlert(_ alert: AlertEvent) {
        if let index = alerts.firstIndex(where: { $0.id == alert.id }) {
            alerts[index].status = .dismissed
        }
    }
}

// MARK: - Alerts Section

struct AlertsSection: View {
    let alerts: [AlertEvent]
    let onDismiss: (AlertEvent) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Active Alerts", systemImage: "bell.badge")
                .font(.headline)
            
            ForEach(alerts) { alert in
                AlertCard(alert: alert, onDismiss: { onDismiss(alert) })
            }
        }
    }
}

struct AlertCard: View {
    let alert: AlertEvent
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: alert.icon)
                .font(.title2)
                .foregroundStyle(alert.color)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(alert.displayTitle)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(alert.firedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(alert.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Digest Card

struct DigestCard: View {
    let digest: InsightDigest
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Weekly Summary")
                    .font(.headline)
                Spacer()
                Text("\(digest.periodStart, style: .date) - \(digest.periodEnd, style: .date)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if let summary = digest.digestJson.summary {
                HStack(spacing: 0) {
                    DigestStatItem(value: summary.handoffs ?? 0, label: "Updates")
                    DigestStatItem(value: summary.tasksCompleted ?? 0, label: "Done")
                    DigestStatItem(value: summary.tasksOverdue ?? 0, label: "Overdue", color: (summary.tasksOverdue ?? 0) > 0 ? .red : .secondary)
                    DigestStatItem(value: summary.medChanges ?? 0, label: "Med Δ")
                }
            }
            
            if let highlights = digest.digestJson.highlights, !highlights.isEmpty {
                Divider()
                Text("Highlights")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                ForEach(Array(highlights.enumerated()), id: \.offset) { index, highlight in
                    if let title = highlight.title {
                        HStack {
                            SwiftUI.Circle()
                                .fill(Color.blue)
                                .frame(width: 6, height: 6)
                            Text(title)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct DigestStatItem: View {
    let value: Int
    let label: String
    var color: Color = .primary
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Quick Stats Section

struct QuickStatsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity")
                .font(.headline)
            
            HStack(spacing: 12) {
                StatCard(icon: "doc.text", value: "12", label: "This Week", color: .blue)
                StatCard(icon: "checkmark.circle", value: "8", label: "Completed", color: .green)
            }
        }
    }
}

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Alert Rules Config View

struct AlertRulesConfigView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var overdueEnabled = true
    @State private var overdueThreshold = 3
    @State private var stalenessEnabled = true
    @State private var stalenessDays = 7
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Overdue Tasks Alert") {
                    Toggle("Enabled", isOn: $overdueEnabled)
                    if overdueEnabled {
                        Stepper("Alert when \(overdueThreshold)+ tasks overdue", value: $overdueThreshold, in: 1...10)
                    }
                }
                
                Section("Staleness Alert") {
                    Toggle("Enabled", isOn: $stalenessEnabled)
                    if stalenessEnabled {
                        Stepper("Alert after \(stalenessDays) days without updates", value: $stalenessDays, in: 3...30)
                    }
                }
                
                Section {
                    Text("Alerts help you stay on top of caregiving activities. Configure thresholds based on your needs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Alert Settings")
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
    InsightsView()
        .environmentObject(AppState())
}
