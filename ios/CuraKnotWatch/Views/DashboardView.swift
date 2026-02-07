import SwiftUI

// MARK: - Dashboard View

struct DashboardView: View {
    @EnvironmentObject var dataManager: WatchDataManager
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Patient Header
                    PatientHeader(patient: dataManager.currentPatient)

                    // Next Task Card
                    if let nextTask = dataManager.nextTask {
                        NextTaskCard(task: nextTask)
                    }

                    // Last Handoff Card
                    if let lastHandoff = dataManager.lastHandoff {
                        LastHandoffCard(handoff: lastHandoff)
                    }

                    // Quick Actions
                    QuickActionsRow()
                }
                .padding(.horizontal)
            }
            .navigationTitle("CuraKnot")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("SettingsButton")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .overlay(alignment: .bottom) {
                if dataManager.isStale {
                    StalenessIndicator(age: dataManager.formattedDataAge)
                }
            }
        }
    }
}

// MARK: - Patient Header

struct PatientHeader: View {
    let patient: WatchPatient?

    var body: some View {
        HStack {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 40, height: 40)

                Text(patient?.displayInitials ?? "?")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(patient?.displayName ?? "No Patient")
                    .font(.headline)
                    .lineLimit(1)

                Text("Care Circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("PatientHeader")
    }
}

// MARK: - Next Task Card

struct NextTaskCard: View {
    let task: WatchTask
    @EnvironmentObject var dataManager: WatchDataManager
    @State private var showingDetail = false

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "checklist")
                        .foregroundStyle(.orange)
                    Text("Next Task")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Text(task.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let dueAt = task.dueAt {
                    HStack {
                        Image(systemName: task.isOverdue ? "exclamationmark.triangle.fill" : "clock")
                            .font(.caption2)
                            .foregroundStyle(task.isOverdue ? .red : .secondary)
                        Text(dueAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(task.isOverdue ? .red : .secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("NextTaskCard")
        .sheet(isPresented: $showingDetail) {
            TaskDetailView(task: task)
        }
    }
}

// MARK: - Last Handoff Card

struct LastHandoffCard: View {
    let handoff: WatchHandoff
    @State private var showingDetail = false

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.blue)
                    Text("Last Handoff")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Text(handoff.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)

                if let summary = handoff.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                if let publishedAt = handoff.publishedAt {
                    HStack {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(publishedAt, style: .relative)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("LastHandoffCard")
        .sheet(isPresented: $showingDetail) {
            HandoffDetailView(handoff: handoff)
        }
    }
}

// MARK: - Quick Actions Row

struct QuickActionsRow: View {
    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(destination: HandoffCaptureView()) {
                QuickActionButton(icon: "mic.fill", label: "Handoff", color: .green)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("NewHandoffButton")

            NavigationLink(destination: TaskListView()) {
                QuickActionButton(icon: "checklist", label: "Tasks", color: .orange)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("TasksButton")

            NavigationLink(destination: EmergencyCardView()) {
                QuickActionButton(icon: "staroflife.fill", label: "Emergency", color: .red)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("EmergencyButton")
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Staleness Indicator

struct StalenessIndicator: View {
    let age: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.icloud")
                .font(.caption2)
            Text("Data: \(age)")
                .font(.caption2)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 8)
        .accessibilityIdentifier("StalenessIndicator")
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var dataManager: WatchDataManager
    @EnvironmentObject var connectivityHandler: WatchConnectivityHandler
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Patient Selector
                Section("Patient") {
                    ForEach(dataManager.patients) { patient in
                        Button {
                            dataManager.selectPatient(patient.id)
                        } label: {
                            HStack {
                                Text(patient.displayName)
                                Spacer()
                                if patient.id == dataManager.currentPatientId {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }

                // Sync Status
                Section("Sync") {
                    HStack {
                        Text("Last Sync")
                        Spacer()
                        Text(dataManager.formattedDataAge)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("iPhone")
                        Spacer()
                        Text(connectivityHandler.isPhoneReachable ? "Connected" : "Not Connected")
                            .foregroundStyle(connectivityHandler.isPhoneReachable ? .green : .secondary)
                    }

                    if connectivityHandler.isPhoneReachable {
                        Button("Sync Now") {
                            connectivityHandler.requestSync()
                        }
                        .accessibilityIdentifier("SyncNowButton")
                    }
                }

                // Subscription
                Section("Account") {
                    HStack {
                        Text("Plan")
                        Spacer()
                        Text(dataManager.cachedSubscriptionStatus)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
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

// MARK: - Handoff Detail View

struct HandoffDetailView: View {
    let handoff: WatchHandoff
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(handoff.title)
                    .font(.headline)

                if let summary = handoff.summary {
                    Text(summary)
                        .font(.body)
                }

                Divider()

                HStack {
                    Image(systemName: "person")
                    Text(handoff.createdByName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let publishedAt = handoff.publishedAt {
                    HStack {
                        Image(systemName: "clock")
                        Text(publishedAt, style: .date)
                        Text(publishedAt, style: .time)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Handoff")
    }
}

// MARK: - Task Detail View

struct TaskDetailView: View {
    let task: WatchTask
    @EnvironmentObject var dataManager: WatchDataManager
    @Environment(\.dismiss) private var dismiss
    @State private var didComplete = false  // State for haptic trigger (DB1-Bug4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(task.title)
                    .font(.headline)

                if let description = task.description {
                    Text(description)
                        .font(.body)
                }

                if let dueAt = task.dueAt {
                    HStack {
                        Image(systemName: "clock")
                        Text("Due: ")
                        Text(dueAt, style: .relative)
                    }
                    .font(.caption)
                    .foregroundStyle(task.isOverdue ? .red : .secondary)
                }

                Spacer(minLength: 20)

                Button {
                    dataManager.markTaskCompleted(task.id)
                    didComplete = true  // Trigger haptic feedback
                    dismiss()
                } label: {
                    Label("Mark Complete", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .sensoryFeedback(.success, trigger: didComplete)  // Use state variable
                .accessibilityIdentifier("MarkCompleteButton")
            }
            .padding()
        }
        .navigationTitle("Task")
    }
}

#Preview {
    DashboardView()
        .environmentObject(WatchDataManager.shared)
}
