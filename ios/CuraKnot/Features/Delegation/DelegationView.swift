import SwiftUI

// MARK: - Member Stats Model

struct MemberStats: Identifiable, Codable {
    let id: UUID
    let circleId: UUID
    let userId: UUID
    let statsJson: Stats
    let computedAt: Date
    
    struct Stats: Codable {
        let tasksCompleted7d: Int?
        let tasksCompleted30d: Int?
        let tasksAssignedOpen: Int?
        let tasksCreated7d: Int?
        let avgCompletionTimeHours: Double?
        let overdueRate: Double?
        let handoffsCreated7d: Int?
        let handoffsCreated30d: Int?
        
        enum CodingKeys: String, CodingKey {
            case tasksCompleted7d = "tasks_completed_7d"
            case tasksCompleted30d = "tasks_completed_30d"
            case tasksAssignedOpen = "tasks_assigned_open"
            case tasksCreated7d = "tasks_created_7d"
            case avgCompletionTimeHours = "avg_completion_time_hours"
            case overdueRate = "overdue_rate"
            case handoffsCreated7d = "handoffs_created_7d"
            case handoffsCreated30d = "handoffs_created_30d"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case userId = "user_id"
        case statsJson = "stats_json"
        case computedAt = "computed_at"
    }
}

struct TaskSuggestion: Identifiable, Codable {
    var id: UUID { userId }
    let userId: UUID
    let displayName: String
    let score: Double
    let reasons: [String]
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case score, reasons
    }
}

// MARK: - Workload Dashboard View

struct WorkloadDashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var memberStats: [(user: User, stats: MemberStats.Stats)] = []
    @State private var circleTotals: CircleTotals?
    @State private var isLoading = false
    
    struct CircleTotals {
        let openTasks: Int
        let completed7d: Int
        let handoffs7d: Int
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Circle Overview
                    if let totals = circleTotals {
                        CircleOverviewCard(totals: totals)
                    }
                    
                    // Member Workloads
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Team Workload")
                            .font(.headline)
                        
                        if memberStats.isEmpty {
                            Text("No member statistics available yet.")
                                .foregroundStyle(.secondary)
                                .padding()
                        } else {
                            ForEach(memberStats, id: \.user.id) { item in
                                MemberWorkloadCard(user: item.user, stats: item.stats)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Workload")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshStats() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                await loadData()
            }
        }
    }
    
    private func loadData() async {
        isLoading = true
        // TODO: Call get_workload_dashboard RPC
        isLoading = false
    }
    
    private func refreshStats() async {
        // TODO: Call compute_member_stats RPC
        await loadData()
    }
}

// MARK: - Circle Overview Card

struct CircleOverviewCard: View {
    let totals: WorkloadDashboardView.CircleTotals
    
    var body: some View {
        VStack(spacing: 16) {
            Text("This Week")
                .font(.headline)
            
            HStack(spacing: 0) {
                OverviewStat(value: totals.openTasks, label: "Open Tasks", color: .blue)
                OverviewStat(value: totals.completed7d, label: "Completed", color: .green)
                OverviewStat(value: totals.handoffs7d, label: "Updates", color: .purple)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct OverviewStat: View {
    let value: Int
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Member Workload Card

struct MemberWorkloadCard: View {
    let user: User
    let stats: MemberStats.Stats
    
    var workloadLevel: WorkloadLevel {
        let open = stats.tasksAssignedOpen ?? 0
        if open >= 10 { return .heavy }
        if open >= 5 { return .moderate }
        return .light
    }
    
    enum WorkloadLevel {
        case light, moderate, heavy
        
        var color: Color {
            switch self {
            case .light: return .green
            case .moderate: return .orange
            case .heavy: return .red
            }
        }
        
        var label: String {
            switch self {
            case .light: return "Light"
            case .moderate: return "Moderate"
            case .heavy: return "Heavy"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Avatar
                SwiftUI.Circle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(String(user.displayName.prefix(1)))
                            .font(.headline)
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    HStack(spacing: 4) {
                        SwiftUI.Circle()
                            .fill(workloadLevel.color)
                            .frame(width: 8, height: 8)
                        Text(workloadLevel.label + " workload")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Text("\(stats.tasksAssignedOpen ?? 0) open")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Stats Row
            HStack(spacing: 16) {
                MiniStat(label: "Done (7d)", value: stats.tasksCompleted7d ?? 0)
                MiniStat(label: "Created (7d)", value: stats.tasksCreated7d ?? 0)
                MiniStat(label: "Handoffs", value: stats.handoffsCreated7d ?? 0)
                if let rate = stats.overdueRate, rate > 0 {
                    MiniStat(label: "Overdue %", value: Int(rate), color: .orange)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MiniStat: View {
    let label: String
    let value: Int
    var color: Color = .primary
    
    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Task Suggestion View

struct TaskSuggestionView: View {
    let suggestions: [TaskSuggestion]
    let onSelect: (TaskSuggestion) -> Void
    
    var body: some View {
        let topSuggestions = Array(suggestions.prefix(3))
        return VStack(alignment: .leading, spacing: 12) {
            Label("Suggested Assignees", systemImage: "lightbulb")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            ForEach(topSuggestions, id: \.displayName) { suggestion in
                suggestionRow(suggestion)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private func suggestionRow(_ suggestion: TaskSuggestion) -> some View {
        Button {
            onSelect(suggestion)
        } label: {
            HStack {
                SwiftUI.Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Text(String(suggestion.displayName.prefix(1)))
                            .font(.caption)
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.displayName)
                        .font(.body)
                    
                    if !suggestion.reasons.isEmpty {
                        Text(suggestion.reasons.joined(separator: " • "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    WorkloadDashboardView()
        .environmentObject(AppState())
}
