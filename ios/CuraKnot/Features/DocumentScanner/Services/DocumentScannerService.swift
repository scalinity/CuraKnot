import Foundation
import UIKit
import Vision
import GRDB

// MARK: - Document Scanner Service

/// Service for orchestrating document scanning workflow:
/// capture → upload → classify → extract → route
@MainActor
final class DocumentScannerService: ObservableObject {

    // MARK: - Published State

    @Published var isProcessing = false
    @Published var currentScan: DocumentScan?
    @Published var recentScans: [DocumentScan] = []
    @Published var usageInfo: ScanUsageInfo?
    @Published var error: DocumentScanError?

    // MARK: - Dependencies

    private let databaseManager: DatabaseManager
    private let supabaseClient: SupabaseClient
    private let syncCoordinator: SyncCoordinator
    private let authManager: AuthManager

    // MARK: - Initialization

    init(
        databaseManager: DatabaseManager,
        supabaseClient: SupabaseClient,
        syncCoordinator: SyncCoordinator,
        authManager: AuthManager
    ) {
        self.databaseManager = databaseManager
        self.supabaseClient = supabaseClient
        self.syncCoordinator = syncCoordinator
        self.authManager = authManager
    }

    /// Current user ID from auth manager
    private var currentUserId: String? {
        authManager.currentUser?.id
    }

    // MARK: - Usage Tracking

    /// Check if user can scan more documents (tier-gated)
    func checkUsageLimit(circleId: String) async throws -> ScanUsageInfo {
        let usage: ScanUsageInfo = try await supabaseClient.rpc("check_document_scan_limit", params: [
                "p_user_id": currentUserId ?? "",
                "p_circle_id": circleId
            ])
        self.usageInfo = usage
        return usage
    }

    // MARK: - Document Capture

    /// Process scanned images: upload to storage, create local record
    func processScan(
        images: [UIImage],
        circleId: String,
        patientId: String?
    ) async throws -> DocumentScan {
        guard !images.isEmpty else {
            throw DocumentScanError.noImagesProvided
        }

        isProcessing = true
        error = nil

        defer { isProcessing = false }

        // Check usage limit
        let usage = try await checkUsageLimit(circleId: circleId)
        guard usage.allowed else {
            throw DocumentScanError.usageLimitReached(
                current: usage.current ?? 0,
                limit: usage.limit ?? 5
            )
        }

        guard let userId = currentUserId else {
            throw DocumentScanError.notAuthenticated
        }

        // Perform on-device OCR
        let ocrTexts = await performOCR(on: images)
        let combinedOCR = ocrTexts.joined(separator: "\n---\n")

        // Create scan ID first so upload path matches record
        let scanId = UUID().uuidString

        // Upload images to Supabase Storage
        let storageKeys = try await uploadImages(images, circleId: circleId, scanId: scanId)
        let scan = DocumentScan(
            id: scanId,
            circleId: circleId,
            patientId: patientId,
            createdBy: userId,
            storageKeys: storageKeys,
            pageCount: images.count,
            ocrText: combinedOCR.isEmpty ? nil : combinedOCR,
            ocrConfidence: nil,
            ocrProvider: .vision,
            documentType: nil,
            classificationConfidence: nil,
            classificationSource: nil,
            extractedFieldsJson: nil,
            extractionConfidence: nil,
            routedToType: nil,
            routedToId: nil,
            routedAt: nil,
            routedBy: nil,
            status: .pending,
            errorMessage: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Save to local database
        try databaseManager.write { db in
            try scan.save(db)
        }

        // Increment usage
        try await supabaseClient.rpc("increment_document_scan_usage", params: [
                "p_user_id": userId,
                "p_circle_id": circleId,
                "p_scan_id": scanId
            ])

        // Sync to remote
        try await syncDocumentScan(scan)

        currentScan = scan
        return scan
    }

    // MARK: - On-Device OCR

    /// Perform OCR using Vision framework on device
    private func performOCR(on images: [UIImage]) async -> [String] {
        var results: [String] = []

        for image in images {
            guard let cgImage = image.cgImage else { continue }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])

                let text = request.results?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""

                results.append(text)
            } catch {
                #if DEBUG
                print("OCR failed for image: \(error)")
                #endif
                results.append("")
            }
        }

        return results
    }

    // MARK: - Image Upload

    /// Upload images to Supabase Storage with rollback on failure
    private func uploadImages(_ images: [UIImage], circleId: String, scanId: String) async throws -> [String] {
        var keys: [String] = []

        do {
            for (index, image) in images.enumerated() {
                // Compress image
                guard var imageData = image.jpegData(compressionQuality: 0.8) else {
                    throw DocumentScanError.imageCompressionFailed
                }

                // Check size limit (10MB max), retry with lower quality if needed
                if imageData.count > 10_000_000 {
                    guard let smallerData = image.jpegData(compressionQuality: 0.5) else {
                        throw DocumentScanError.imageTooLarge
                    }
                    guard smallerData.count <= 10_000_000 else {
                        throw DocumentScanError.imageTooLarge
                    }
                    imageData = smallerData
                }

                let filename = "\(circleId)/\(scanId)/page_\(index + 1).jpg"

                _ = try await supabaseClient.storage("scanned-documents")
                    .upload(path: filename, data: imageData, contentType: "image/jpeg")

                keys.append(filename)
            }

            return keys
        } catch {
            // Rollback: delete any successfully uploaded files
            for key in keys {
                try? await supabaseClient.storage("scanned-documents").remove(path: key)
            }
            throw DocumentScanError.uploadFailed(error.localizedDescription)
        }
    }

    // MARK: - Classification

    /// Classify document using AI (requires PLUS or FAMILY tier)
    func classifyDocument(
        scanId: String,
        overrideType: DocumentType? = nil
    ) async throws -> ClassificationResult {
        isProcessing = true
        error = nil

        defer { isProcessing = false }

        struct ClassifyRequest: Encodable {
            let scanId: String
            let overrideType: String?
        }

        struct ClassifyResponse: Decodable {
            let success: Bool
            let documentType: String?
            let confidence: Double?
            let source: String?
            let alternates: [AlternateResponse]?
            let error: ErrorResponse?

            struct AlternateResponse: Decodable {
                let type: String
                let confidence: Double
            }

            struct ErrorResponse: Decodable {
                let code: String
                let message: String
            }
        }

        let requestBody = ClassifyRequest(
            scanId: scanId,
            overrideType: overrideType?.rawValue
        )

        let result: ClassifyResponse = try await supabaseClient.functions("classify-document")
            .invoke(body: requestBody)

        if !result.success {
            if result.error?.code == "TIER_GATE" {
                throw DocumentScanError.tierGate(
                    feature: "AI classification",
                    requiredTier: "Plus"
                )
            }
            throw DocumentScanError.classificationFailed(
                result.error?.message ?? "Unknown error"
            )
        }

        guard let typeString = result.documentType,
              let docType = DocumentType(rawValue: typeString),
              let confidence = result.confidence else {
            throw DocumentScanError.classificationFailed("Invalid response")
        }

        let sourceString = result.source ?? "AI"
        let source: DocumentScan.ClassificationSource = sourceString == "USER_OVERRIDE" ? .userOverride : .ai

        let alternates = result.alternates?.compactMap { alt -> ClassificationResult.AlternateClassification? in
            guard let type = DocumentType(rawValue: alt.type) else { return nil }
            return ClassificationResult.AlternateClassification(type: type, confidence: alt.confidence)
        }

        // Update local record
        try databaseManager.write { db in
            guard var scan = try DocumentScan.fetchOne(db, key: scanId) else {
                throw DocumentScanError.scanNotFound
            }
            scan.documentType = docType
            scan.classificationConfidence = confidence
            scan.classificationSource = source
            scan.status = .ready
            scan.updatedAt = Date()
            try scan.update(db)
            self.currentScan = scan
        }

        return ClassificationResult(
            documentType: docType,
            confidence: confidence,
            source: source,
            alternates: alternates
        )
    }

    // MARK: - Extraction

    /// Extract structured fields from document (requires FAMILY tier)
    func extractFields(scanId: String) async throws -> ExtractionResult {
        isProcessing = true
        error = nil

        defer { isProcessing = false }

        struct ExtractRequest: Encodable {
            let scanId: String
        }

        struct ExtractResponse: Decodable {
            let success: Bool
            let fields: [String: AnyCodableValue]?
            let confidence: Double?
            let error: ErrorResponse?

            struct ErrorResponse: Decodable {
                let code: String
                let message: String
            }
        }

        let requestBody = ExtractRequest(scanId: scanId)

        let result: ExtractResponse = try await supabaseClient.functions("extract-document-data")
            .invoke(body: requestBody)

        if !result.success {
            if result.error?.code == "TIER_GATE" {
                throw DocumentScanError.tierGate(
                    feature: "field extraction",
                    requiredTier: "Family"
                )
            }
            throw DocumentScanError.extractionFailed(
                result.error?.message ?? "Unknown error"
            )
        }

        guard let fields = result.fields,
              let confidence = result.confidence else {
            throw DocumentScanError.extractionFailed("Invalid response")
        }

        // Update local record with extracted fields
        let fieldsJson = try JSONEncoder().encode(fields)
        let fieldsJsonString = String(data: fieldsJson, encoding: .utf8)

        try databaseManager.write { db in
            guard var scan = try DocumentScan.fetchOne(db, key: scanId) else {
                throw DocumentScanError.scanNotFound
            }
            scan.extractedFieldsJson = fieldsJsonString
            scan.extractionConfidence = confidence
            scan.updatedAt = Date()
            try scan.update(db)
            self.currentScan = scan
        }

        return ExtractionResult(fields: fields, confidence: confidence)
    }

    // MARK: - Routing

    /// Route document to target destination (Binder, Billing, Handoff, Inbox)
    func routeDocument(
        scanId: String,
        targetType: RoutingTarget,
        binderItemType: String? = nil,
        overrideFields: [String: Any]? = nil
    ) async throws -> RoutingResult {
        isProcessing = true
        error = nil

        defer { isProcessing = false }

        struct RouteRequest: Encodable {
            let scanId: String
            let targetType: String
            let binderItemType: String?
            let overrideFields: [String: AnyCodableValue]?
        }

        struct RouteResponse: Decodable {
            let success: Bool
            let targetId: String?
            let targetType: String?
            let attachmentIds: [String]?
            let error: ErrorResponse?

            struct ErrorResponse: Decodable {
                let code: String
                let message: String
            }
        }

        // Convert override fields to AnyCodableValue
        var encodableOverrides: [String: AnyCodableValue]?
        if let overrides = overrideFields {
            encodableOverrides = [:]
            for (key, value) in overrides {
                if let str = value as? String {
                    encodableOverrides?[key] = .string(str)
                } else if let int = value as? Int {
                    encodableOverrides?[key] = .int(int)
                } else if let double = value as? Double {
                    encodableOverrides?[key] = .double(double)
                } else if let bool = value as? Bool {
                    encodableOverrides?[key] = .bool(bool)
                }
            }
        }

        let requestBody = RouteRequest(
            scanId: scanId,
            targetType: targetType.rawValue,
            binderItemType: binderItemType,
            overrideFields: encodableOverrides
        )

        let result: RouteResponse = try await supabaseClient.functions("route-document")
            .invoke(body: requestBody)

        if !result.success {
            throw DocumentScanError.routingFailed(
                result.error?.message ?? "Unknown error"
            )
        }

        guard let targetId = result.targetId,
              let targetTypeStr = result.targetType else {
            throw DocumentScanError.routingFailed("Invalid response")
        }

        // Update local record
        try databaseManager.write { db in
            guard var scan = try DocumentScan.fetchOne(db, key: scanId) else {
                throw DocumentScanError.scanNotFound
            }
            scan.routedToType = targetType
            scan.routedToId = targetId
            scan.routedAt = Date()
            scan.routedBy = currentUserId
            scan.status = .routed
            scan.updatedAt = Date()
            try scan.update(db)
            self.currentScan = scan
        }

        return RoutingResult(
            targetId: targetId,
            targetType: targetTypeStr,
            attachmentIds: result.attachmentIds ?? []
        )
    }

    // MARK: - History

    /// Fetch recent scans for a circle
    func fetchRecentScans(circleId: String, limit: Int = 20) async throws -> [DocumentScan] {
        let scans = try databaseManager.read { db in
            try DocumentScan
                .filter(Column("circleId") == circleId)
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }

        self.recentScans = scans
        return scans
    }

    /// Get a single scan by ID
    func getScan(id: String) async throws -> DocumentScan? {
        return try databaseManager.read { db in
            try DocumentScan.fetchOne(db, key: id)
        }
    }

    /// Retry a failed scan (re-upload and re-classify)
    func retryScan(_ scanId: String) async throws {
        guard var scan = try await getScan(id: scanId) else {
            throw DocumentScanError.scanNotFound
        }

        guard scan.status == .failed else {
            throw DocumentScanError.invalidState("Scan is not in failed state")
        }

        // Reset status to pending
        scan.status = .pending
        scan.errorMessage = nil
        scan.updatedAt = Date()

        try databaseManager.write { db in
            try scan.update(db)
        }

        // Re-sync to trigger processing
        try await syncDocumentScan(scan)
    }

    // MARK: - Sync

    private func syncDocumentScan(_ scan: DocumentScan) async throws {
        // Convert to Supabase format (snake_case)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        let payload = try encoder.encode(scan)
        let payloadString = String(data: payload, encoding: .utf8) ?? "{}"

        try await syncCoordinator.enqueue(operation: OfflineOperation(
            id: nil,
            operationType: "INSERT",
            entityType: "document_scans",
            entityId: scan.id,
            payloadJson: payloadString,
            attempts: 0,
            lastAttemptAt: nil,
            createdAt: Date()
        ))
    }
}

// MARK: - Document Scan Error

enum DocumentScanError: LocalizedError {
    case notAuthenticated
    case noImagesProvided
    case imageCompressionFailed
    case imageTooLarge
    case uploadFailed(String)
    case usageLimitReached(current: Int, limit: Int)
    case tierGate(feature: String, requiredTier: String)
    case classificationFailed(String)
    case extractionFailed(String)
    case routingFailed(String)
    case scanNotFound
    case invalidState(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to scan documents"
        case .noImagesProvided:
            return "No images were captured"
        case .imageCompressionFailed:
            return "Failed to process scanned images"
        case .imageTooLarge:
            return "Image is too large. Please scan at a lower resolution."
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .usageLimitReached(let current, let limit):
            return "You've used \(current)/\(limit) scans this month. Upgrade to Plus for unlimited scanning."
        case .tierGate(let feature, let requiredTier):
            return "\(feature) requires \(requiredTier) plan"
        case .classificationFailed(let message):
            return "Classification failed: \(message)"
        case .extractionFailed(let message):
            return "Data extraction failed: \(message)"
        case .routingFailed(let message):
            return "Failed to save document: \(message)"
        case .scanNotFound:
            return "Scan not found"
        case .invalidState(let message):
            return message
        }
    }
}
