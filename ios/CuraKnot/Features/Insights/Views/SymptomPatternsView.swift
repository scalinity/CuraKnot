import SwiftUI

/// Main view for symptom pattern surfacing
struct SymptomPatternsView: View {
    let patient: Patient
    let circleId: UUID

    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: SymptomPatternsViewModel

    init(patient: Patient, circleId: UUID, service: SymptomPatternsService) {
        self.patient = patient
        self.circleId = circleId

        // Convert String ID to UUID for internal use
        let patientUUID = UUID(uuidString: patient.id) ?? UUID()
        _viewModel = StateObject(wrappedValue: SymptomPatternsViewModel(
            patientId: patientUUID,
            circleId: circleId,
            service: service
        ))
    }

    var body: some View {
        Group {
            if viewModel.isCheckingAccess {
                ProgressView("Checking access...")
            } else if !viewModel.hasAccess {
                upgradePrompt
            } else {
                patternsContent
            }
        }
        .navigationTitle("Symptom Patterns")
        .task {
            await viewModel.checkAccess()
            if viewModel.hasAccess {
                await viewModel.loadPatterns()
            }
        }
    }

    // MARK: - Upgrade Prompt

    private var upgradePrompt: some View {
        VStack(spacing: 24) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 60))
                .foregroundStyle(.purple)

            Text("Symptom Pattern Insights")
                .font(.title2)
                .fontWeight(.bold)

            Text("Automatically detect patterns in your handoffs and get proactive insights about symptoms, trends, and correlations.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button {
                appState.showUpgradeFlow = true
            } label: {
                Text("Upgrade to Plus")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }

    // MARK: - Patterns Content

    private var patternsContent: some View {
        List {
            // Disclaimer
            Section {
                InsightsDisclaimer()
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            // Loading state
            if viewModel.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if viewModel.patterns.isEmpty && viewModel.trackedConcerns.isEmpty {
                // Empty state
                Section {
                    emptyState
                }
                .listRowBackground(Color.clear)
            } else {
                // Patterns section
                if !viewModel.patterns.isEmpty {
                    Section("Detected Patterns") {
                        ForEach(viewModel.patterns) { pattern in
                            NavigationLink {
                                PatternDetailView(
                                    pattern: pattern,
                                    viewModel: viewModel
                                )
                            } label: {
                                PatternCard(pattern: pattern)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                }

                // Tracked concerns section
                if !viewModel.trackedConcerns.isEmpty {
                    Section("Tracking") {
                        ForEach(viewModel.trackedConcerns) { concern in
                            NavigationLink {
                                ManualTrackingView(
                                    concern: concern,
                                    viewModel: viewModel
                                )
                            } label: {
                                TrackedConcernRow(
                                    concern: concern,
                                    latestEntry: viewModel.latestEntries[concern.id]
                                )
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.refresh()
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            Text("No Patterns Yet")
                .font(.headline)

            Text("Patterns will appear as you log more handoffs. Try recording a few updates about how your loved one is doing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await viewModel.triggerAnalysis()
                }
            } label: {
                Label("Analyze Now", systemImage: "wand.and.stars")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - View Model

@MainActor
final class SymptomPatternsViewModel: ObservableObject {
    private let patientId: UUID
    private let circleId: UUID
    let symptomService: SymptomPatternsService

    @Published var patterns: [DetectedPattern] = []
    @Published var trackedConcerns: [TrackedConcern] = []
    @Published var latestEntries: [UUID: TrackingEntry] = [:]
    @Published var isLoading = false
    @Published var isCheckingAccess = true
    @Published var hasAccess = false
    @Published var showError = false
    @Published var errorMessage: String?

    init(patientId: UUID, circleId: UUID, service: SymptomPatternsService) {
        self.patientId = patientId
        self.circleId = circleId
        self.symptomService = service
    }

    func checkAccess() async {
        isCheckingAccess = true
        hasAccess = await symptomService.hasAccess(circleId: circleId)
        isCheckingAccess = false
    }

    func loadPatterns() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let patternsTask = symptomService.fetchPatterns(patientId: patientId)
            async let concernsTask = symptomService.fetchTrackedConcerns(patientId: patientId)

            patterns = try await patternsTask
            trackedConcerns = try await concernsTask

            // Load latest entries for each tracked concern
            for concern in trackedConcerns {
                let entries = try await symptomService.fetchTrackingEntries(concernId: concern.id, limit: 1)
                latestEntries[concern.id] = entries.first
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func refresh() async {
        do {
            patterns = try await symptomService.fetchPatterns(patientId: patientId, forceRefresh: true)
            trackedConcerns = try await symptomService.fetchTrackedConcerns(patientId: patientId)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func dismissPattern(_ pattern: DetectedPattern) async {
        do {
            try await symptomService.dismissPattern(pattern.id)
            patterns.removeAll { $0.id == pattern.id }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func trackPattern(_ pattern: DetectedPattern) async {
        do {
            let concern = try await symptomService.trackPattern(
                pattern.id,
                circleId: circleId,
                patientId: patientId
            )
            trackedConcerns.insert(concern, at: 0)

            // Update pattern status locally
            if let index = patterns.firstIndex(where: { $0.id == pattern.id }) {
                patterns[index].status = .tracking
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func addToAppointmentQuestions(_ pattern: DetectedPattern) async {
        do {
            try await symptomService.addToAppointmentQuestions(pattern: pattern, appointmentPackId: nil)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func triggerAnalysis() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await symptomService.triggerAnalysis(patientId: patientId)
            // Reload patterns after analysis
            await loadPatterns()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func submitFeedback(for pattern: DetectedPattern, type: PatternFeedbackType, text: String?) async {
        do {
            try await symptomService.submitFeedback(patternId: pattern.id, feedbackType: type, feedbackText: text)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// Patient type is defined in Core/Database/Models/Patient.swift
