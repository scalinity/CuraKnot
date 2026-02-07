import Foundation
import LocalAuthentication
import os

private let logger = Logger(subsystem: "com.curaknot.app", category: "LegalVaultViewModel")

// MARK: - Legal Vault ViewModel

@MainActor
final class LegalVaultViewModel: ObservableObject {
    // MARK: - Published State

    @Published var documents: [LegalDocument] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var showingUpgradePrompt = false

    // MARK: - Dependencies

    private let service: LegalVaultService

    // MARK: - Computed Properties

    var healthcareDocuments: [LegalDocument] {
        documents.filter { $0.category == .healthcare && $0.status == .active }
    }

    var financialDocuments: [LegalDocument] {
        documents.filter { $0.category == .financial && $0.status == .active }
    }

    var estateDocuments: [LegalDocument] {
        documents.filter { $0.category == .estate && $0.status == .active }
    }

    var otherDocuments: [LegalDocument] {
        documents.filter { $0.category == .other && $0.status == .active }
    }

    var expiringDocuments: [LegalDocument] {
        documents.filter { $0.isExpiringSoon && $0.status == .active }
    }

    var expiredDocuments: [LegalDocument] {
        documents.filter { $0.isExpired || $0.status == .expired }
    }

    var hasAccess: Bool {
        service.hasAccess
    }

    var canAddDocument: Bool {
        service.canAddDocument(currentCount: documents.count)
    }

    var documentLimitMessage: String? {
        guard let limit = service.documentLimit else { return nil }
        return "\(documents.count) of \(limit) documents used"
    }

    // MARK: - Initialization

    init(service: LegalVaultService) {
        self.service = service
    }

    // MARK: - Load Documents

    func loadDocuments(circleId: String, patientId: String) async {
        isLoading = true
        error = nil

        do {
            documents = try await service.fetchDocuments(circleId: circleId, patientId: patientId)
        } catch {
            logger.error("Failed to load documents: \(error.localizedDescription)")
            self.error = "Failed to load documents."
        }

        isLoading = false
    }

    // MARK: - Delete Document

    func deleteDocument(_ document: LegalDocument) async {
        do {
            try await service.deleteDocument(document)
            documents.removeAll { $0.id == document.id }
        } catch {
            logger.error("Failed to delete document: \(error.localizedDescription)")
            self.error = "Failed to delete document."
        }
    }

    // MARK: - Toggle Emergency Access

    func toggleEmergencyAccess(for document: LegalDocument) async {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }

        // Optimistic update
        let previousValue = documents[index].includeInEmergency
        documents[index].includeInEmergency.toggle()

        do {
            try await service.updateDocument(
                document,
                includeInEmergency: !previousValue
            )
        } catch {
            // Rollback on failure
            if let idx = documents.firstIndex(where: { $0.id == document.id }) {
                documents[idx].includeInEmergency = previousValue
            }
            logger.error("Failed to update emergency access: \(error.localizedDescription)")
            self.error = "Failed to update emergency setting."
        }
    }

    // MARK: - Biometric Authentication

    static func authenticateWithBiometrics() async -> Bool {
        let context = LAContext()
        var nsError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &nsError) else {
            // Fall back to device passcode
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &nsError) else {
                return false
            }
            return await withCheckedContinuation { continuation in
                context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "Authenticate to view legal documents"
                ) { success, _ in
                    continuation.resume(returning: success)
                }
            }
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Authenticate to view legal documents"
            ) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
