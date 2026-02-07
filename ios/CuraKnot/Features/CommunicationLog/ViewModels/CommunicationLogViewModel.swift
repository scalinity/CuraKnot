import Foundation
import SwiftUI

// MARK: - Communication Log List ViewModel

@MainActor
class CommunicationLogListViewModel: ObservableObject {
    // MARK: - Published State

    @Published var groupedLogs: [CommunicationLogGroup] = []
    @Published var isLoading = false
    @Published var searchText = ""
    @Published var selectedFilter: LogFilter = .all
    @Published var showingNewLog = false
    @Published var showingFilters = false
    @Published var errorMessage: String?

    // MARK: - Dependencies

    private let service: CommunicationLogService
    private let circleId: String
    private let patientId: String?

    // MARK: - Initialization

    init(service: CommunicationLogService, circleId: String, patientId: String? = nil) {
        self.service = service
        self.circleId = circleId
        self.patientId = patientId
    }

    // MARK: - Feature Access

    var hasFeatureAccess: Bool {
        service.hasFeatureAccess
    }

    var hasAISuggestionsAccess: Bool {
        service.hasAISuggestionsAccess
    }

    // MARK: - Computed Properties

    var filteredLogs: [CommunicationLogGroup] {
        guard !searchText.isEmpty else {
            return applyFilter(to: groupedLogs)
        }

        let lowercasedSearch = searchText.lowercased()
        let filtered = groupedLogs.compactMap { group -> CommunicationLogGroup? in
            let matchingLogs = group.logs.filter { log in
                log.facilityName.lowercased().contains(lowercasedSearch) ||
                log.contactName.lowercased().contains(lowercasedSearch) ||
                log.summary.lowercased().contains(lowercasedSearch)
            }
            guard !matchingLogs.isEmpty else { return nil }
            return CommunicationLogGroup(id: group.id, date: group.date, logs: matchingLogs)
        }

        return applyFilter(to: filtered)
    }

    var pendingFollowUpsCount: Int {
        groupedLogs.flatMap { $0.logs }.filter { $0.followUpStatus == .pending }.count
    }

    var overdueFollowUpsCount: Int {
        groupedLogs.flatMap { $0.logs }.filter { $0.isFollowUpOverdue }.count
    }

    // MARK: - Data Loading

    func loadLogs() async {
        isLoading = true
        errorMessage = nil

        do {
            groupedLogs = try await service.fetchGroupedLogs(
                circleId: circleId,
                patientId: patientId
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refresh() async {
        await loadLogs()
    }

    // MARK: - Actions

    func deleteLog(_ log: CommunicationLog) async {
        guard !isLoading else { return } // Prevent concurrent operations
        isLoading = true
        errorMessage = nil
        do {
            try await service.deleteLog(log)
            // Optimistically update local state (avoid full reload)
            groupedLogs = groupedLogs.compactMap { group in
                let filtered = group.logs.filter { $0.id != log.id }
                guard !filtered.isEmpty else { return nil }
                return CommunicationLogGroup(id: group.id, date: group.date, logs: filtered)
            }
        } catch {
            errorMessage = error.localizedDescription
            await loadLogs() // Reload on error to recover state
        }
        isLoading = false
    }

    func markFollowUpComplete(_ log: CommunicationLog) async {
        guard !isLoading else { return } // Prevent concurrent operations
        isLoading = true
        errorMessage = nil
        do {
            try await service.markFollowUpComplete(log)
            // Optimistically update local state (avoid full reload)
            groupedLogs = groupedLogs.map { group in
                let updatedLogs = group.logs.map { existingLog -> CommunicationLog in
                    guard existingLog.id == log.id else { return existingLog }
                    var updated = existingLog
                    updated.followUpStatus = .complete
                    updated.followUpCompletedAt = Date()
                    return updated
                }
                return CommunicationLogGroup(id: group.id, date: group.date, logs: updatedLogs)
            }
        } catch {
            errorMessage = error.localizedDescription
            await loadLogs() // Reload on error to recover state
        }
        isLoading = false
    }

    // MARK: - Filtering

    private func applyFilter(to groups: [CommunicationLogGroup]) -> [CommunicationLogGroup] {
        switch selectedFilter {
        case .all:
            return groups
        case .pendingFollowUp:
            return groups.compactMap { group in
                let filtered = group.logs.filter { $0.followUpStatus == .pending }
                guard !filtered.isEmpty else { return nil }
                return CommunicationLogGroup(id: group.id, date: group.date, logs: filtered)
            }
        case .overdue:
            return groups.compactMap { group in
                let filtered = group.logs.filter { $0.isFollowUpOverdue }
                guard !filtered.isEmpty else { return nil }
                return CommunicationLogGroup(id: group.id, date: group.date, logs: filtered)
            }
        case .resolved:
            return groups.compactMap { group in
                let filtered = group.logs.filter { $0.resolutionStatus == .resolved }
                guard !filtered.isEmpty else { return nil }
                return CommunicationLogGroup(id: group.id, date: group.date, logs: filtered)
            }
        }
    }

    // MARK: - Filter Enum

    enum LogFilter: String, CaseIterable {
        case all = "All"
        case pendingFollowUp = "Pending Follow-up"
        case overdue = "Overdue"
        case resolved = "Resolved"
    }
}

// MARK: - New Log ViewModel

@MainActor
class NewCommunicationLogViewModel: ObservableObject {
    // MARK: - Published State

    @Published var selectedFacility: FacilitySelection?
    @Published var facilityName = ""
    @Published var contactName = ""
    @Published var contactRoles: Set<CommunicationLog.ContactRole> = []
    @Published var contactPhone = ""
    @Published var contactEmail = ""
    @Published var communicationType: CommunicationLog.CommunicationType = .call
    @Published var callType: CommunicationLog.CallType = .statusUpdate
    @Published var callDate = Date()
    @Published var durationMinutes: Int?
    @Published var summary = ""
    @Published var needsFollowUp = false
    @Published var followUpDate = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
    @Published var followUpReason = ""

    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var availableFacilities: [BinderItem] = []

    // MARK: - Dependencies

    private let service: CommunicationLogService
    private let binderService: BinderService
    private let circleId: String
    private let patientId: String

    // MARK: - Initialization

    init(
        service: CommunicationLogService,
        binderService: BinderService,
        circleId: String,
        patientId: String
    ) {
        self.service = service
        self.binderService = binderService
        self.circleId = circleId
        self.patientId = patientId
    }

    // MARK: - Computed Properties

    var isValid: Bool {
        !effectiveFacilityName.isEmpty && !contactName.isEmpty && !summary.isEmpty
    }

    var effectiveFacilityName: String {
        selectedFacility?.name ?? facilityName
    }

    var promptText: String {
        callType.promptText
    }

    // MARK: - Data Loading

    func loadFacilities() async {
        isLoading = true
        do {
            let items = try await binderService.fetchItems(
                circleId: circleId,
                type: .facility,
                patientId: patientId
            )
            availableFacilities = items
        } catch {
            // Non-blocking error - facilities are optional
        }
        isLoading = false
    }

    // MARK: - Save

    func save() async -> CommunicationLog? {
        guard isValid, !isSaving else { return nil } // Prevent double-submission

        isSaving = true
        errorMessage = nil

        do {
            let log = try await service.createLog(
                circleId: circleId,
                patientId: patientId,
                facilityName: effectiveFacilityName,
                facilityId: selectedFacility?.id,
                contactName: contactName,
                contactRole: Array(contactRoles),
                contactPhone: contactPhone.isEmpty ? nil : contactPhone,
                contactEmail: contactEmail.isEmpty ? nil : contactEmail,
                communicationType: communicationType,
                callType: callType,
                callDate: callDate,
                durationMinutes: durationMinutes,
                summary: summary,
                followUpDate: needsFollowUp ? followUpDate : nil,
                followUpReason: needsFollowUp && !followUpReason.isEmpty ? followUpReason : nil
            )
            isSaving = false
            return log
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
            return nil
        }
    }

    // MARK: - Helpers

    func selectFacility(_ facility: BinderItem?) {
        if let facility = facility {
            selectedFacility = FacilitySelection(
                id: facility.id,
                name: facility.title,
                phone: nil
            )
            facilityName = facility.title
        } else {
            selectedFacility = nil
        }
    }

    func updateFollowUpFromCallType() {
        if let days = callType.defaultFollowUpDays,
           let date = Calendar.current.date(byAdding: .day, value: days, to: Date()) {
            needsFollowUp = true
            followUpDate = date
        }
    }

    // MARK: - Facility Selection

    struct FacilitySelection: Identifiable {
        let id: String
        let name: String
        let phone: String?
    }
}

// MARK: - Log Detail ViewModel

@MainActor
class CommunicationLogDetailViewModel: ObservableObject {
    // MARK: - Published State

    @Published var log: CommunicationLog
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingEditSheet = false
    @Published var showingCreateTask = false
    @Published var showingCreateHandoff = false

    // MARK: - Dependencies

    private let service: CommunicationLogService

    // MARK: - Initialization

    init(log: CommunicationLog, service: CommunicationLogService) {
        self.log = log
        self.service = service
    }

    // MARK: - Feature Access

    var hasAISuggestionsAccess: Bool {
        service.hasAISuggestionsAccess
    }

    var hasSuggestions: Bool {
        guard let suggestions = log.aiSuggestedTasks else { return false }
        return !suggestions.isEmpty
    }

    var unacceptedSuggestions: [SuggestedTask] {
        log.aiSuggestedTasks?.filter { !$0.isAccepted } ?? []
    }

    // MARK: - Quick Actions

    var canCall: Bool {
        log.phoneURL != nil
    }

    var canEmail: Bool {
        log.emailURL != nil
    }

    func callContact() {
        guard let url = log.phoneURL else { return }
        UIApplication.shared.open(url)
    }

    func emailContact() {
        guard let url = log.emailURL else { return }
        UIApplication.shared.open(url)
    }

    func openInMaps() {
        guard let url = log.mapsURL else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Follow-up Actions

    func markFollowUpComplete() async {
        guard !isLoading else { return } // Prevent concurrent operations
        isLoading = true
        errorMessage = nil
        do {
            try await service.markFollowUpComplete(log)
            // Update local state only after successful service call
            var updated = log
            updated.followUpStatus = .complete
            updated.followUpCompletedAt = Date()
            updated.updatedAt = Date()
            log = updated
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func rescheduleFollowUp(to date: Date) async {
        guard !isLoading else { return } // Prevent concurrent operations
        isLoading = true
        errorMessage = nil
        do {
            try await service.rescheduleFollowUp(log, to: date)
            // Update local state only after successful service call
            var updated = log
            updated.followUpDate = date
            updated.updatedAt = Date()
            log = updated
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func createFollowUpTask() async {
        guard !isLoading else { return } // Prevent concurrent operations
        isLoading = true
        errorMessage = nil
        do {
            let taskId = try await service.createFollowUpTask(for: log)
            // Update local state only after successful service call
            var updated = log
            updated.followUpTaskId = taskId
            updated.followUpStatus = .pending
            updated.updatedAt = Date()
            log = updated
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - AI Suggestions

    func acceptSuggestion(_ task: SuggestedTask) async {
        guard !isLoading else { return } // Prevent concurrent operations
        isLoading = true
        errorMessage = nil
        do {
            try await service.acceptSuggestedTask(task, from: log)
            // Update local state only after successful service call
            var updated = log
            if var suggestions = updated.aiSuggestedTasks,
               let index = suggestions.firstIndex(where: { $0.id == task.id }) {
                suggestions[index].isAccepted = true
                updated.aiSuggestedTasks = suggestions
                updated.updatedAt = Date()
                log = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Resolution

    func markResolved() async {
        guard !isLoading else { return } // Prevent concurrent operations
        isLoading = true
        errorMessage = nil
        do {
            var updated = log
            updated.resolutionStatus = .resolved
            updated.updatedAt = Date()
            try await service.updateLog(updated)
            log = updated
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func escalate() async {
        guard !isLoading else { return } // Prevent concurrent operations
        isLoading = true
        errorMessage = nil
        do {
            var updated = log
            updated.resolutionStatus = .escalated
            updated.updatedAt = Date()
            try await service.updateLog(updated)
            log = updated
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
