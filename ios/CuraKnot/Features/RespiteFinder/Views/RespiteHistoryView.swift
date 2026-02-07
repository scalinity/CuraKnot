import SwiftUI

// MARK: - Respite History View

struct RespiteHistoryView: View {
    let service: RespiteFinderService
    let circleId: String
    let patientId: String?

    @State private var selectedTab: Int
    @State private var showAddLogEntry = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(service: RespiteFinderService, circleId: String, patientId: String?) {
        self.service = service
        self.circleId = circleId
        self.patientId = patientId
        // Default to Respite Log tab if user can't submit requests
        _selectedTab = State(initialValue: service.canSubmitRequests ? 0 : 1)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if service.canSubmitRequests || service.canTrackRespite {
                    Picker(String(localized: "View"), selection: $selectedTab) {
                        if service.canSubmitRequests {
                            Text(String(localized: "Requests")).tag(0)
                        }
                        if service.canTrackRespite {
                            Text(String(localized: "Respite Log")).tag(1)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                }

                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    Text(error)
                        .foregroundStyle(.secondary)
                    Button(String(localized: "Retry")) { Task { await loadData() } }
                        .buttonStyle(.bordered)
                    Spacer()
                } else {
                    if selectedTab == 0 {
                        requestsList
                    } else {
                        respiteLogList
                    }
                }
            }
            .navigationTitle(String(localized: "History"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Done")) { dismiss() }
                }
                if selectedTab == 1 && service.canTrackRespite {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showAddLogEntry = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(String(localized: "Add respite log entry"))
                    }
                }
            }
            .sheet(isPresented: $showAddLogEntry) {
                AddRespiteLogSheet(service: service, circleId: circleId)
            }
            .task {
                await loadData()
            }
            .refreshable {
                await loadData()
            }
        }
    }

    // MARK: - Requests List

    private var requestsList: some View {
        Group {
            if service.requests.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "No Requests Yet"))
                        .font(.headline)
                    Text(String(localized: "Submitted availability requests will appear here."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List(service.requests) { request in
                    RequestRow(request: request)
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Respite Log List

    private var respiteLogList: some View {
        Group {
            if service.canTrackRespite {
                VStack(spacing: 0) {
                    // Summary card
                    respiteSummaryCard

                    if service.respiteLog.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text(String(localized: "No Respite Logged"))
                                .font(.headline)
                            Text(String(localized: "Track your respite breaks to monitor self-care."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    } else {
                        List(service.respiteLog) { entry in
                            LogEntryRow(entry: entry)
                        }
                        .listStyle(.plain)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Family Plan Required"))
                        .font(.headline)
                    Text(String(localized: "Respite tracking is available on the Family plan."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Summary Card

    private var respiteSummaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Respite This Year"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(service.respiteDaysThisYear) days")
                    .font(.title2)
                    .bold()
            }
            Spacer()
            Image(systemName: "heart.text.clipboard")
                .font(.title)
                .foregroundStyle(.blue)
        }
        .padding()
        .background(Color.blue.opacity(0.05))
    }

    // MARK: - Load Data

    private func loadData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Run all fetches in parallel; each independently catches errors so
            // one failure doesn't prevent the others from loading.
            try await withThrowingTaskGroup(of: Void.self) { group in
                if service.canSubmitRequests {
                    group.addTask { @MainActor in
                        try Task.checkCancellation()
                        do {
                            try await self.service.fetchRequests(circleId: self.circleId)
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            if self.errorMessage == nil {
                                self.errorMessage = error.localizedDescription
                            }
                        }
                    }
                }
                if service.canTrackRespite {
                    group.addTask { @MainActor in
                        try Task.checkCancellation()
                        do {
                            try await self.service.fetchRespiteLog(circleId: self.circleId)
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            if self.errorMessage == nil {
                                self.errorMessage = error.localizedDescription
                            }
                        }
                    }
                    group.addTask { @MainActor in
                        try Task.checkCancellation()
                        do {
                            try await self.service.fetchRespiteDaysThisYear(circleId: self.circleId, patientId: self.patientId)
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            // Non-critical — year count is informational
                        }
                    }
                }
                for try await _ in group {
                    try Task.checkCancellation()
                }
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            // Silently ignore cancellation
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Request Row

private struct RequestRow: View {
    let request: RespiteRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(request.providerName ?? String(localized: "Provider"))
                    .font(.subheadline)
                    .bold()
                Spacer()
                Label(request.status.displayName, systemImage: request.status.icon)
                    .font(.caption)
                    .foregroundStyle(colorForStatus(request.status))
            }

            Text("\(request.startDate) – \(request.endDate)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Contact: \(request.contactMethod.displayName) (\(request.contactValue))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func colorForStatus(_ status: RespiteRequest.RequestStatus) -> Color {
        switch status {
        case .pending: return .orange
        case .confirmed: return .green
        case .declined: return .red
        case .cancelled: return .gray
        case .completed: return .blue
        }
    }
}

// MARK: - Log Entry Row

private struct LogEntryRow: View {
    let entry: RespiteLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.providerType)
                    .font(.subheadline)
                    .bold()
                Spacer()
                Text(entry.totalDays == 1 ? String(localized: "1 day") : String(localized: "\(entry.totalDays) days"))
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())
            }

            Text(entry.providerName)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(entry.dateRange)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let notes = entry.notes {
                Text(notes)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Respite Log Sheet

private struct AddRespiteLogSheet: View {
    let service: RespiteFinderService
    let circleId: String

    @EnvironmentObject private var appState: AppState
    @State private var providerType = "IN_HOME"
    @State private var providerName = ""
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var notes = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private let providerTypes = RespiteProvider.ProviderType.allCases.map { ($0.rawValue, $0.displayName) }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Type")) {
                    Picker(String(localized: "Provider Type"), selection: $providerType) {
                        ForEach(providerTypes, id: \.0) { type in
                            Text(type.1).tag(type.0)
                        }
                    }
                }

                Section(String(localized: "Provider")) {
                    TextField(String(localized: "Provider name (required)"), text: $providerName)
                }

                Section(String(localized: "Dates")) {
                    DatePicker(String(localized: "Start"), selection: $startDate, displayedComponents: .date)
                    DatePicker(String(localized: "End"), selection: $endDate, in: startDate..., displayedComponents: .date)
                }

                Section(String(localized: "Notes (Optional)")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(String(localized: "Log Respite"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Save")) {
                        Task { await save() }
                    }
                    .bold()
                    .disabled(isSubmitting || providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .disabled(isSubmitting)
        }
    }

    private func save() async {
        guard let patientId = appState.currentPatientId else {
            errorMessage = String(localized: "No patient selected.")
            return
        }

        guard !providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = String(localized: "Provider name is required.")
            return
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await service.addRespiteLogEntry(
                circleId: circleId,
                patientId: patientId,
                providerType: providerType,
                providerName: providerName,
                startDate: Self.dateFormatter.string(from: startDate),
                endDate: Self.dateFormatter.string(from: endDate),
                notes: notes.isEmpty ? nil : notes
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
