import Foundation
import os

private let logger = Logger(subsystem: "com.curaknot.app", category: "LegalVaultService")

// MARK: - Legal Vault Service

@MainActor
final class LegalVaultService: ObservableObject {
    // MARK: - Dependencies

    private let databaseManager: DatabaseManager
    private let supabaseClient: SupabaseClient
    private let subscriptionManager: SubscriptionManager
    private let authManager: AuthManager

    // MARK: - Initialization

    init(
        databaseManager: DatabaseManager,
        supabaseClient: SupabaseClient,
        subscriptionManager: SubscriptionManager,
        authManager: AuthManager
    ) {
        self.databaseManager = databaseManager
        self.supabaseClient = supabaseClient
        self.subscriptionManager = subscriptionManager
        self.authManager = authManager
    }

    // MARK: - Feature Access

    var hasAccess: Bool {
        subscriptionManager.hasFeature(.legalVault)
    }

    var hasUnlimitedDocuments: Bool {
        subscriptionManager.currentPlan == .family
    }

    var documentLimit: Int? {
        switch subscriptionManager.currentPlan {
        case .free: return 0
        case .plus: return 5
        case .family: return nil // unlimited
        }
    }

    func canAddDocument(currentCount: Int) -> Bool {
        guard let limit = documentLimit else { return true }
        return currentCount < limit
    }

    var hasExpirationReminders: Bool {
        subscriptionManager.currentPlan == .family
    }

    // MARK: - CRUD Operations

    func fetchDocuments(circleId: String, patientId: String) async throws -> [LegalDocument] {
        let docs: [LegalDocument] = try await supabaseClient
            .from("legal_documents")
            .select()
            .eq("circle_id", circleId)
            .eq("patient_id", patientId)
            .order("created_at", ascending: false)
            .execute()
        return docs
    }

    func fetchDocumentAccess(documentId: String) async throws -> [LegalDocumentAccess] {
        let access: [LegalDocumentAccess] = try await supabaseClient
            .from("legal_document_access")
            .select()
            .eq("document_id", documentId)
            .execute()
        return access
    }

    func fetchAuditLog(documentId: String) async throws -> [LegalDocumentAuditEntry] {
        let entries: [LegalDocumentAuditEntry] = try await supabaseClient
            .from("legal_document_audit")
            .select()
            .eq("document_id", documentId)
            .order("created_at", ascending: false)
            .limit(50)
            .execute()
        return entries
    }

    // MARK: - Upload Document

    func uploadDocument(
        circleId: String,
        patientId: String,
        documentType: LegalDocumentType,
        title: String,
        description: String?,
        fileData: Data,
        fileType: String,
        mimeType: String,
        executionDate: Date?,
        expirationDate: Date?,
        principalName: String?,
        agentName: String?,
        alternateAgentName: String?,
        notarized: Bool,
        notarizedDate: Date?,
        witnessNames: [String],
        includeInEmergency: Bool,
        accessUserIds: [String]
    ) async throws -> LegalDocument {
        // Validate file size (max 50 MB)
        let maxFileSize = 50 * 1024 * 1024
        guard fileData.count <= maxFileSize else {
            throw LegalVaultError.fileTooLarge(maxMB: 50)
        }

        // Validate file type
        let allowedMimeTypes = ["application/pdf", "image/jpeg", "image/png", "image/heic"]
        guard allowedMimeTypes.contains(mimeType.lowercased()) else {
            throw LegalVaultError.unsupportedFileType(mimeType)
        }

        let userId = try await requireUserId()
        let documentId = UUID().uuidString

        // Upload file to storage
        let ext: String
        switch mimeType.lowercased() {
        case "application/pdf": ext = "pdf"
        case "image/png": ext = "png"
        case "image/heic": ext = "heic"
        default: ext = "jpg" // image/jpeg and fallback
        }
        let storageKey = "\(circleId)/\(patientId)/\(documentId).\(ext)"

        _ = try await supabaseClient
            .storage("legal-documents")
            .upload(path: storageKey, data: fileData, contentType: mimeType)

        // Create document record
        var params: [String: Any?] = [
            "id": documentId,
            "circle_id": circleId,
            "patient_id": patientId,
            "created_by": userId,
            "document_type": documentType.rawValue,
            "title": title,
            "description": description,
            "storage_key": storageKey,
            "file_type": fileType,
            "file_size_bytes": fileData.count,
            "notarized": notarized,
            "include_in_emergency": includeInEmergency,
            "status": LegalDocumentStatus.active.rawValue,
        ]

        if let executionDate {
            params["execution_date"] = dateString(from: executionDate)
        }
        if let expirationDate {
            params["expiration_date"] = dateString(from: expirationDate)
        }
        if let principalName { params["principal_name"] = principalName }
        if let agentName { params["agent_name"] = agentName }
        if let alternateAgentName { params["alternate_agent_name"] = alternateAgentName }
        if let notarizedDate {
            params["notarized_date"] = dateString(from: notarizedDate)
        }
        if !witnessNames.isEmpty {
            params["witness_names"] = witnessNames
        }

        try await supabaseClient
            .from("legal_documents")
            .insert(params)
            .execute()

        // Grant access to specified users (creator always has implicit access)
        for accessUserId in accessUserIds where accessUserId != userId {
            try await supabaseClient
                .from("legal_document_access")
                .insert([
                    "document_id": documentId,
                    "user_id": accessUserId,
                    "can_view": true,
                    "can_share": false,
                    "can_edit": false,
                    "granted_by": userId,
                ] as [String: Any?])
                .execute()
        }

        // Log audit
        try await logAudit(documentId: documentId, action: "UPLOADED", details: [
            "file_type": fileType,
            "file_size": fileData.count,
            "access_granted_to": accessUserIds,
        ])

        // Fetch and return the created document
        let docs = try await fetchDocuments(circleId: circleId, patientId: patientId)
        guard let doc = docs.first(where: { $0.id == documentId }) else {
            throw LegalVaultError.documentNotFound
        }
        return doc
    }

    // MARK: - Update Document

    func updateDocument(
        _ document: LegalDocument,
        title: String? = nil,
        description: String? = nil,
        executionDate: Date? = nil,
        expirationDate: Date? = nil,
        agentName: String? = nil,
        alternateAgentName: String? = nil,
        notarized: Bool? = nil,
        includeInEmergency: Bool? = nil,
        status: LegalDocumentStatus? = nil
    ) async throws {
        var updates: [String: Any?] = [:]
        if let title { updates["title"] = title }
        if let description { updates["description"] = description }
        if let executionDate {
            updates["execution_date"] = dateString(from: executionDate)
        }
        if let expirationDate {
            updates["expiration_date"] = dateString(from: expirationDate)
        }
        if let agentName { updates["agent_name"] = agentName }
        if let alternateAgentName { updates["alternate_agent_name"] = alternateAgentName }
        if let notarized { updates["notarized"] = notarized }
        if let includeInEmergency { updates["include_in_emergency"] = includeInEmergency }
        if let status { updates["status"] = status.rawValue }

        guard !updates.isEmpty else { return }

        try await supabaseClient
            .from("legal_documents")
            .update(updates)
            .eq("id", document.id)
            .execute()

        try await logAudit(documentId: document.id, action: "UPDATED", details: [
            "fields_updated": Array(updates.keys),
        ])
    }

    // MARK: - Delete Document

    func deleteDocument(_ document: LegalDocument) async throws {
        // Delete DB record first (cascades to access, shares, audit).
        // If DB delete fails, storage file remains accessible (recoverable).
        // If we deleted storage first and DB failed, we'd have an orphaned DB record.
        try await supabaseClient
            .from("legal_documents")
            .eq("id", document.id)
            .delete()

        // Remove from storage (best-effort after DB delete succeeds)
        do {
            try await supabaseClient
                .storage("legal-documents")
                .remove(path: document.storageKey)
        } catch {
            // Storage cleanup failed — log but don't throw since the DB record is gone.
            // Orphaned storage files can be cleaned up by a periodic maintenance job.
            logger.warning("Storage cleanup failed for \(document.storageKey): \(error.localizedDescription)")
        }

        logger.info("Deleted legal document: \(document.id) (\(document.title))")
    }

    // MARK: - Access Management

    func grantAccess(
        documentId: String,
        userId: String,
        canView: Bool = true,
        canShare: Bool = false,
        canEdit: Bool = false
    ) async throws {
        let grantedBy = try await requireUserId()
        try await supabaseClient
            .from("legal_document_access")
            .upsert([
                "document_id": documentId,
                "user_id": userId,
                "can_view": canView,
                "can_share": canShare,
                "can_edit": canEdit,
                "granted_by": grantedBy,
            ] as [String: Any?])
            .execute()

        try await logAudit(documentId: documentId, action: "ACCESS_GRANTED", details: [
            "target_user_id": userId,
            "can_view": canView,
            "can_share": canShare,
            "can_edit": canEdit,
        ])
    }

    func revokeAccess(documentId: String, userId: String) async throws {
        try await supabaseClient
            .from("legal_document_access")
            .eq("document_id", documentId)
            .eq("user_id", userId)
            .delete()

        try await logAudit(documentId: documentId, action: "ACCESS_REVOKED", details: [
            "target_user_id": userId,
        ])
    }

    // MARK: - Share Management

    struct ShareResult {
        let shareUrl: String
        let shareToken: String
        let accessCode: String?
        let expiresAt: Date
    }

    func generateShareLink(
        documentId: String,
        expirationHours: Int,
        requireAccessCode: Bool,
        maxViews: Int? = nil
    ) async throws -> ShareResult {
        struct ShareRequest: Encodable {
            let documentId: String
            let expirationHours: Int
            let requireAccessCode: Bool
            let maxViews: Int?
        }

        struct ShareResponse: Decodable {
            let success: Bool
            let shareUrl: String?
            let shareToken: String?
            let accessCode: String?
            let expiresAt: String?
            let error: ErrorDetail?

            struct ErrorDetail: Decodable {
                let code: String
                let message: String
            }
        }

        let request = ShareRequest(
            documentId: documentId,
            expirationHours: expirationHours,
            requireAccessCode: requireAccessCode,
            maxViews: maxViews
        )

        let response: ShareResponse = try await supabaseClient
            .functions("generate-document-share")
            .invoke(body: request)

        guard response.success,
              let shareUrl = response.shareUrl,
              let shareToken = response.shareToken,
              let expiresAtStr = response.expiresAt else {
            throw LegalVaultError.shareGenerationFailed(
                response.error?.message ?? "Unknown error"
            )
        }

        let formatter = ISO8601DateFormatter()
        guard let expiresAt = formatter.date(from: expiresAtStr) else {
            throw LegalVaultError.shareGenerationFailed("Invalid expiration date from server")
        }

        return ShareResult(
            shareUrl: shareUrl,
            shareToken: shareToken,
            accessCode: response.accessCode,
            expiresAt: expiresAt
        )
    }

    // MARK: - Document Download URL

    func getDocumentURL(storageKey: String) async throws -> URL {
        let url = try await supabaseClient
            .storage("legal-documents")
            .createSignedURL(path: storageKey, expiresIn: 900)
        return url
    }

    // MARK: - Audit Logging

    func logView(documentId: String) async throws {
        try await logAudit(documentId: documentId, action: "VIEWED", details: nil)
    }

    private func logAudit(documentId: String, action: String, details: [String: Any]?) async throws {
        let userId = try await requireUserId()
        var params: [String: Any?] = [
            "document_id": documentId,
            "user_id": userId,
            "action": action,
        ]
        if let details {
            // Only serialize if the dictionary is valid JSON (all values must be JSON-serializable)
            if JSONSerialization.isValidJSONObject(details) {
                let data = try JSONSerialization.data(withJSONObject: details)
                if let json = String(data: data, encoding: .utf8) {
                    params["details_json"] = json
                }
            } else {
                logger.warning("Audit details for \(action) on \(documentId) contain non-JSON-serializable values, skipping details")
            }
        }
        do {
            try await supabaseClient
                .from("legal_document_audit")
                .insert(params)
                .execute()
        } catch {
            logger.error("Audit log insert failed for \(action) on document \(documentId): \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Helpers

    /// Format a Date to ISO 8601 date-only string (YYYY-MM-DD) for Supabase date columns.
    /// Uses UTC explicitly to avoid off-by-one day errors from local timezone conversion.
    private func dateString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private func requireUserId() async throws -> String {
        guard let user = try await authManager.getCurrentUser() else {
            throw LegalVaultError.notAuthenticated
        }
        return user.id
    }
}

// MARK: - Errors

enum LegalVaultError: LocalizedError {
    case notAuthenticated
    case documentNotFound
    case shareGenerationFailed(String)
    case documentLimitReached
    case featureNotAvailable
    case fileTooLarge(maxMB: Int)
    case unsupportedFileType(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to access the legal vault."
        case .documentNotFound:
            return "Document not found."
        case .shareGenerationFailed(let message):
            return "Failed to generate share link: \(message)"
        case .documentLimitReached:
            return "You've reached the document limit for your plan. Upgrade to add more."
        case .featureNotAvailable:
            return "The Legal Vault requires a Plus or Family subscription."
        case .fileTooLarge(let maxMB):
            return "File is too large. Maximum size is \(maxMB) MB."
        case .unsupportedFileType(let mimeType):
            return "Unsupported file type: \(mimeType). Please use PDF, JPEG, PNG, or HEIC."
        }
    }
}
