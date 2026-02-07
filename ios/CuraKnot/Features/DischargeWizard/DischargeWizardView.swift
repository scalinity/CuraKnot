import SwiftUI

// MARK: - Discharge Wizard View

struct DischargeWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: DischargeWizardViewModel

    let patient: Patient

    init(
        patient: Patient,
        service: DischargeWizardService,
        circleId: String,
        userId: String
    ) {
        self.patient = patient
        self._viewModel = StateObject(wrappedValue: DischargeWizardViewModel(
            service: service,
            patient: patient,
            circleId: circleId,
            userId: userId
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress indicator
                WizardProgressView(
                    currentStep: viewModel.currentStep,
                    totalSteps: viewModel.totalSteps,
                    stepTitles: DischargeRecord.WizardStep.allCases.map(\.title)
                )
                .padding(.horizontal)
                .padding(.top, 8)

                // Step content
                TabView(selection: $viewModel.currentStep) {
                    DischargeSetupStep(viewModel: viewModel)
                        .tag(1)

                    MedicationsStep(viewModel: viewModel)
                        .tag(2)

                    EquipmentStep(viewModel: viewModel)
                        .tag(3)

                    HomePrepStep(viewModel: viewModel)
                        .tag(4)

                    CareScheduleStep(viewModel: viewModel)
                        .tag(5)

                    FollowUpsStep(viewModel: viewModel)
                        .tag(6)

                    ReviewStep(viewModel: viewModel)
                        .tag(7)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)

                // Navigation buttons
                WizardNavigationBar(
                    canGoBack: viewModel.canGoBack,
                    canGoNext: viewModel.canGoNext,
                    isLastStep: viewModel.isLastStep,
                    nextButtonTitle: viewModel.nextButtonTitle,
                    isLoading: viewModel.isGenerating,
                    onBack: viewModel.goToPreviousStep,
                    onNext: viewModel.goToNextStep
                )
            }
            .navigationTitle("Discharge Planning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.onAppear()
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred")
            }
            .alert("Discharge Plan Created!", isPresented: $viewModel.showCompletionAlert) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                if let result = viewModel.generationResult {
                    Text("Created \(result.summary)")
                }
            }
            .sheet(isPresented: $viewModel.showUpgradePaywall) {
                DischargeUpgradePaywallView()
            }
            .overlay {
                if viewModel.isLoading {
                    DischargeLoadingOverlay(message: "Loading...")
                }
                if viewModel.isGenerating {
                    DischargeLoadingOverlay(message: "Creating your discharge plan...")
                }
            }
            .overlay(alignment: .top) {
                // Auto-save warning banner
                if viewModel.showAutoSaveWarning {
                    AutoSaveWarningBanner(message: viewModel.autoSaveWarningMessage ?? "Changes may not be saved")
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut, value: viewModel.showAutoSaveWarning)
                }
            }
        }
    }
}

// MARK: - Wizard Progress View

struct WizardProgressView: View {
    let currentStep: Int
    let totalSteps: Int
    let stepTitles: [String]

    var body: some View {
        VStack(spacing: 8) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color(.systemGray5))
                        .frame(height: 4)

                    // Progress fill
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * progress, height: 4)
                        .animation(.easeInOut(duration: 0.3), value: currentStep)
                }
            }
            .frame(height: 4)

            // Step indicators
            HStack {
                ForEach(1...totalSteps, id: \.self) { step in
                    StepIndicator(
                        step: step,
                        title: step <= stepTitles.count ? stepTitles[step - 1] : "",
                        isActive: step == currentStep,
                        isCompleted: step < currentStep
                    )

                    if step < totalSteps {
                        Spacer()
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var progress: Double {
        Double(currentStep) / Double(totalSteps)
    }
}

struct StepIndicator: View {
    let step: Int
    let title: String
    let isActive: Bool
    let isCompleted: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                SwiftUI.Circle()
                    .fill(backgroundColor)
                    .frame(width: 24, height: 24)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                } else {
                    Text("\(step)")
                        .font(.caption.bold())
                        .foregroundStyle(isActive ? .white : .secondary)
                }
            }

            Text(title)
                .font(.caption2)
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
        }
        .frame(width: 50)
    }

    private var backgroundColor: Color {
        if isCompleted {
            return .green
        } else if isActive {
            return .accentColor
        } else {
            return Color(.systemGray4)
        }
    }
}

// MARK: - Wizard Navigation Bar

struct WizardNavigationBar: View {
    let canGoBack: Bool
    let canGoNext: Bool
    let isLastStep: Bool
    let nextButtonTitle: String
    let isLoading: Bool
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            if canGoBack {
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button(action: onNext) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                    } else {
                        Text(nextButtonTitle)
                        if !isLastStep {
                            Image(systemName: "chevron.right")
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canGoNext || isLoading)
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

// MARK: - Discharge Loading Overlay

private struct DischargeLoadingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Discharge Upgrade Paywall View

private struct DischargeUpgradePaywallView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Hero icon
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.yellow)
                    .padding(.top, 40)

                // Title
                Text("Upgrade to Plus")
                    .font(.largeTitle.bold())

                // Feature description
                VStack(alignment: .leading, spacing: 16) {
                    DischargeUpgradeFeatureRow(
                        icon: "cross.case.fill",
                        title: "Discharge Planning Wizard",
                        description: "Structured guidance through hospital-to-home transitions"
                    )

                    DischargeUpgradeFeatureRow(
                        icon: "checklist",
                        title: "Smart Checklists",
                        description: "Pre-built templates for surgery, cardiac, stroke, and more"
                    )

                    DischargeUpgradeFeatureRow(
                        icon: "square.and.arrow.up",
                        title: "Auto-Create Tasks",
                        description: "Convert checklist items into assignable tasks"
                    )

                    DischargeUpgradeFeatureRow(
                        icon: "doc.text.fill",
                        title: "Discharge Handoff",
                        description: "Automatically create a structured handoff for your care circle"
                    )
                }
                .padding(.horizontal, 24)

                Spacer()

                // Upgrade button
                Button {
                    // Open subscription view
                } label: {
                    Text("Upgrade to Plus — $9.99/month")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 24)

                // Dismiss
                Button("Maybe Later") {
                    dismiss()
                }
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct DischargeUpgradeFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Auto-Save Warning Banner

private struct AutoSaveWarningBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()
    }
}
