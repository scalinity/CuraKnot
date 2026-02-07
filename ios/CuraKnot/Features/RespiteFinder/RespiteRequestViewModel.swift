import Foundation
import OSLog

// MARK: - Respite Request View Model

@MainActor
final class RespiteRequestViewModel: ObservableObject {
    let service: RespiteFinderService
    let provider: RespiteProvider

    private let logger = Logger(subsystem: "com.curaknot", category: "RespiteRequestVM")
    private var submitTask: Task<Void, Never>?

    // MARK: - Form State

    private static let oneDayInterval: TimeInterval = 24 * 60 * 60

    @Published var startDate = Date()
    @Published var endDate = Date().addingTimeInterval(RespiteRequestViewModel.oneDayInterval)
    @Published var specialConsiderations = ""
    @Published var shareMedications = false
    @Published var shareContacts = false
    @Published var shareDietary = false
    @Published var shareFullSummary = false
    @Published var contactMethod: RespiteRequest.ContactMethod = .phone
    @Published var contactValue = ""

    // MARK: - UI State

    @Published var isSubmitting = false
    @Published var errorMessage: String?
    @Published var submittedRequestId: String?
    @Published var showSuccess = false

    // MARK: - Init

    init(service: RespiteFinderService, provider: RespiteProvider) {
        self.service = service
        self.provider = provider
    }

    deinit {
        submitTask?.cancel()
    }

    // MARK: - Validation

    var isValid: Bool {
        !contactValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        endDate >= startDate
    }

    var startDateString: String {
        Self.dateFormatter.string(from: startDate)
    }

    var endDateString: String {
        Self.dateFormatter.string(from: endDate)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Submit

    func submit(circleId: String, patientId: String) {
        guard isValid else {
            errorMessage = String(localized: "Please fill in all required fields.")
            return
        }
        guard !isSubmitting else { return }

        submitTask?.cancel()
        submitTask = Task { [weak self] in
            guard let self else { return }
            self.isSubmitting = true
            self.errorMessage = nil
            defer { self.isSubmitting = false }

            do {
                let requestId = try await self.service.submitRequest(
                    circleId: circleId,
                    patientId: patientId,
                    providerId: self.provider.id,
                    startDate: self.startDateString,
                    endDate: self.endDateString,
                    specialConsiderations: self.specialConsiderations.isEmpty ? nil : self.specialConsiderations,
                    shareMedications: self.shareMedications,
                    shareContacts: self.shareContacts,
                    shareDietary: self.shareDietary,
                    shareFullSummary: self.shareFullSummary,
                    contactMethod: self.contactMethod,
                    contactValue: self.contactValue
                )
                try Task.checkCancellation()
                self.submittedRequestId = requestId
                self.showSuccess = true
            } catch is CancellationError {
                // Silently ignore cancellation
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
