import Foundation
import SwiftUI
import Combine

// MARK: - Discharge Wizard ViewModel

@MainActor
final class DischargeWizardViewModel: ObservableObject {
    // MARK: - Published State

    // Wizard navigation
    @Published var currentStep: Int = 1
    @Published var isNavigating = false

    // Data state
    @Published var record: DischargeRecord?
    @Published var template: DischargeTemplate?
    @Published var checklistItems: [DischargeChecklistItem] = []
    @Published var circleMembers: [WizardCircleMember] = []

    // Setup step
    @Published var facilityName = ""
    @Published var dischargeDate = Date()
    @Published var admissionDate: Date?
    @Published var reasonForStay = ""
    @Published var selectedDischargeType: DischargeRecord.DischargeType = .other

    // Medication step
    @Published var medicationChanges: [DischargeMedicationChange] = []
    @Published var showMedScanner = false

    // Shift assignments (day offset -> member ID)
    @Published var shiftAssignments: [Int: String] = [:]

    // Loading states
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var isGenerating = false
    @Published var isSavingProgress = false

    // Output preview
    @Published var outputSummary: DischargeOutputSummary?

    // Errors and alerts
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var showUpgradePaywall = false
    @Published var showCompletionAlert = false
    @Published var showAutoSaveWarning = false
    @Published var autoSaveWarningMessage: String?

    // Result
    @Published var generationResult: GenerateOutputsResult?

    // MARK: - Dependencies

    private let service: DischargeWizardService
    private let patient: Patient
    private let circleId: String
    private let userId: String

    // MARK: - Debouncing

    private var lastNavigationTime: Date?
    private let navigationDebounceInterval: TimeInterval = 0.5
    private var autoSaveTask: Task<Void, Never>?

    // MARK: - Constants

    let totalSteps = DischargeRecord.WizardStep.totalSteps

    // MARK: - Initialization

    init(
        service: DischargeWizardService,
        patient: Patient,
        circleId: String,
        userId: String
    ) {
        self.service = service
        self.patient = patient
        self.circleId = circleId
        self.userId = userId
    }

    // MARK: - Computed Properties

    var progress: Double {
        Double(currentStep) / Double(totalSteps)
    }

    var currentWizardStep: DischargeRecord.WizardStep? {
        DischargeRecord.WizardStep(rawValue: currentStep)
    }

    var canGoBack: Bool {
        currentStep > 1
    }

    var canGoNext: Bool {
        switch currentWizardStep {
        case .setup:
            return !facilityName.isEmpty && !reasonForStay.isEmpty
        case .review:
            return true
        default:
            return true
        }
    }

    var isLastStep: Bool {
        currentStep == totalSteps
    }

    var nextButtonTitle: String {
        isLastStep ? "Create All" : "Next"
    }

    // Checklist progress
    var checklistProgress: Double {
        guard !checklistItems.isEmpty else { return 0 }
        let completed = checklistItems.filter(\.isCompleted).count
        return Double(completed) / Double(checklistItems.count)
    }

    var checklistProgressText: String {
        let completed = checklistItems.filter(\.isCompleted).count
        return "\(completed)/\(checklistItems.count) completed"
    }

    // Category-specific items
    func items(for category: ChecklistCategory) -> [DischargeChecklistItem] {
        checklistItems.filter { $0.category == category }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var itemsByCategory: [ChecklistItemGroup] {
        checklistItems.grouped()
    }

    // MARK: - Lifecycle

    func onAppear() async {
        // Check premium access
        guard service.hasAccess() else {
            showUpgradePaywall = true
            return
        }

        await loadData()
    }

    // MARK: - Data Loading

    func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Check for existing in-progress record
            if let existingRecord = try await service.getActiveRecord(
                circleId: circleId,
                patientId: patient.id
            ) {
                // Resume existing wizard
                record = existingRecord
                currentStep = existingRecord.currentStep
                facilityName = existingRecord.facilityName
                dischargeDate = existingRecord.dischargeDate
                admissionDate = existingRecord.admissionDate
                reasonForStay = existingRecord.reasonForStay
                selectedDischargeType = existingRecord.dischargeType
                medicationChanges = existingRecord.medicationChanges ?? []
                shiftAssignments = existingRecord.shiftAssignments ?? [:]

                // Load checklist items
                checklistItems = try await service.getChecklistItems(recordId: existingRecord.id)
            }

            // Load templates
            _ = try await service.fetchTemplates()
        } catch {
            displayError(error)
        }
    }

    // MARK: - Navigation

    func goToNextStep() {
        guard canGoNext else { return }

        // Debounce rapid taps
        let now = Date()
        if let lastTime = lastNavigationTime,
           now.timeIntervalSince(lastTime) < navigationDebounceInterval {
            return
        }
        lastNavigationTime = now

        // Prevent navigation while generating
        guard !isGenerating else { return }

        if isLastStep {
            Task { await generateOutputs() }
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep += 1
            }
            Task { await saveProgress() }
        }
    }

    func goToPreviousStep() {
        guard canGoBack else { return }

        // Debounce rapid taps
        let now = Date()
        if let lastTime = lastNavigationTime,
           now.timeIntervalSince(lastTime) < navigationDebounceInterval {
            return
        }
        lastNavigationTime = now

        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep -= 1
        }
    }

    func goToStep(_ step: Int) {
        guard step >= 1 && step <= totalSteps else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = step
        }
    }

    // MARK: - Record Management

    func createRecord() async {
        guard !facilityName.isEmpty && !reasonForStay.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            let newRecord = try await service.createDischargeRecord(
                circleId: circleId,
                patientId: patient.id,
                userId: userId,
                facilityName: facilityName,
                dischargeDate: dischargeDate,
                admissionDate: admissionDate,
                reasonForStay: reasonForStay,
                dischargeType: selectedDischargeType
            )

            record = newRecord

            // Load checklist items
            checklistItems = try await service.getChecklistItems(recordId: newRecord.id)

            // Move to next step
            withAnimation {
                currentStep = 2
            }
        } catch {
            displayError(error)
        }
    }

    func saveProgress() async {
        guard let recordId = record?.id else { return }
        guard !isSavingProgress else { return }

        isSavingProgress = true
        defer { isSavingProgress = false }

        do {
            try await service.updateStep(recordId: recordId, step: currentStep)
            try await service.saveMedicationChanges(recordId: recordId, changes: medicationChanges)
            try await service.saveShiftAssignments(recordId: recordId, assignments: shiftAssignments)
        } catch {
            // Surface autosave errors as warnings (non-blocking)
            autoSaveWarningMessage = "Changes may not be saved. Check your connection."
            showAutoSaveWarning = true

            // Auto-dismiss after 3 seconds (cancel previous dismiss task to avoid races)
            autoSaveTask?.cancel()
            autoSaveTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                showAutoSaveWarning = false
            }
        }
    }

    // MARK: - Checklist Management

    func toggleItem(_ item: DischargeChecklistItem) async {
        do {
            let updatedItem = try await service.toggleItemCompletion(
                itemId: item.id,
                userId: userId
            )

            // Update local state
            if let index = checklistItems.firstIndex(where: { $0.id == item.id }) {
                checklistItems[index] = updatedItem
            }
        } catch {
            displayError(error)
        }
    }

    func updateItemTask(
        _ item: DischargeChecklistItem,
        createTask: Bool,
        assignedTo: String?,
        dueDate: Date?
    ) async {
        do {
            try await service.configureTaskForItem(
                itemId: item.id,
                createTask: createTask,
                assignedTo: assignedTo,
                dueDate: dueDate
            )

            // Update local state
            if let index = checklistItems.firstIndex(where: { $0.id == item.id }) {
                var updatedItem = checklistItems[index]
                updatedItem.createTask = createTask
                updatedItem.assignedTo = assignedTo
                updatedItem.dueDate = dueDate
                checklistItems[index] = updatedItem
            }
        } catch {
            displayError(error)
        }
    }

    // MARK: - Medication Management

    func addMedicationChange(_ change: DischargeMedicationChange) {
        medicationChanges.append(change)
    }

    func removeMedicationChange(_ change: DischargeMedicationChange) {
        medicationChanges.removeAll { $0.id == change.id }
    }

    func updateMedicationChange(_ change: DischargeMedicationChange) {
        if let index = medicationChanges.firstIndex(where: { $0.id == change.id }) {
            medicationChanges[index] = change
        }
    }

    // MARK: - Shift Management

    func assignShift(dayOffset: Int, to memberId: String?) {
        if let memberId = memberId {
            shiftAssignments[dayOffset] = memberId
        } else {
            shiftAssignments.removeValue(forKey: dayOffset)
        }
    }

    func getMemberForShift(dayOffset: Int) -> WizardCircleMember? {
        guard let memberId = shiftAssignments[dayOffset] else { return nil }
        return circleMembers.first { $0.id == memberId }
    }

    // MARK: - Output Generation

    func updateOutputPreview() async {
        guard let recordId = record?.id else { return }

        do {
            outputSummary = try await service.previewOutputs(recordId: recordId)
        } catch {
            #if DEBUG
            print("Failed to preview outputs: \(error)")
            #endif
        }
    }

    func generateOutputs() async {
        guard let recordId = record?.id else { return }
        guard !isGenerating else { return }

        isGenerating = true
        defer { isGenerating = false }

        do {
            let result = try await service.generateOutputs(
                recordId: recordId,
                userId: userId
            )

            generationResult = result
            showCompletionAlert = true
        } catch let error as DischargeWizardError {
            switch error {
            case .partialFailure(let created):
                // Show partial success with info about what was created
                generationResult = created
                errorMessage = error.localizedDescription
                showError = true
            case .accessDenied:
                showUpgradePaywall = true
            default:
                displayError(error)
            }
        } catch {
            displayError(error)
        }
    }

    // MARK: - Cancellation

    func cancelWizard() async {
        guard let recordId = record?.id else { return }

        do {
            try await service.cancelRecord(id: recordId)
        } catch {
            displayError(error)
        }
    }

    // MARK: - Error Handling

    private func displayError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}

// MARK: - Wizard Circle Member (View Model)

/// View model representation of a circle member for the wizard UI
struct WizardCircleMember: Identifiable {
    let id: String
    let userId: String
    let displayName: String
    let role: String
    let avatarUrl: String?

    var initials: String {
        let components = displayName.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }
}
