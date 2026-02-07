import Foundation
import GRDB

// MARK: - Document Scan Model

/// Represents a scanned document with OCR, AI classification, and routing metadata.
struct DocumentScan: Codable, Identifiable, Equatable {
    let id: String
    let circleId: String
    var patientId: String?
    let createdBy: String

    // Storage
    var storageKeys: [String]
    var pageCount: Int

    // OCR Results
    var ocrText: String?
    var ocrConfidence: Double?
    var ocrProvider: OCRProvider?

    // Classification
    var documentType: DocumentType?
    var classificationConfidence: Double?
    var classificationSource: ClassificationSource?

    // Extraction (FAMILY tier only)
    var extractedFieldsJson: String?
    var extractionConfidence: Double?

    // Routing
    var routedToType: RoutingTarget?
    var routedToId: String?
    var routedAt: Date?
    var routedBy: String?

    // Status tracking
    var status: ScanStatus
    var errorMessage: String?

    let createdAt: Date
    var updatedAt: Date

    // MARK: - Enums

    enum ScanStatus: String, Codable, CaseIterable {
        case pending = "PENDING"
        case processing = "PROCESSING"
        case ready = "READY"
        case routed = "ROUTED"
        case failed = "FAILED"

        var displayName: String {
            switch self {
            case .pending: return "Uploading"
            case .processing: return "Analyzing"
            case .ready: return "Ready"
            case .routed: return "Saved"
            case .failed: return "Failed"
            }
        }

        var icon: String {
            switch self {
            case .pending: return "arrow.up.circle"
            case .processing: return "gearshape.2"
            case .ready: return "checkmark.circle"
            case .routed: return "checkmark.seal.fill"
            case .failed: return "exclamationmark.circle"
            }
        }
    }

    enum OCRProvider: String, Codable {
        case vision = "VISION"
        case cloud = "CLOUD"
    }

    enum ClassificationSource: String, Codable {
        case ai = "AI"
        case userOverride = "USER_OVERRIDE"

        var displayName: String {
            switch self {
            case .ai: return "AI Detected"
            case .userOverride: return "Manual"
            }
        }
    }

    // MARK: - Computed Properties

    var isClassified: Bool {
        documentType != nil
    }

    var hasExtractedData: Bool {
        extractedFieldsJson != nil && !extractedFieldsJson!.isEmpty
    }

    var isRouted: Bool {
        status == .routed && routedToId != nil
    }

    var confidencePercentage: Int? {
        guard let confidence = classificationConfidence else { return nil }
        return Int(confidence * 100)
    }

    var extractedFields: [String: Any]? {
        guard let json = extractedFieldsJson,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

// MARK: - Document Type

enum DocumentType: String, Codable, CaseIterable, Identifiable {
    case prescription = "PRESCRIPTION"
    case labResult = "LAB_RESULT"
    case discharge = "DISCHARGE"
    case appointment = "APPOINTMENT"
    case medicationList = "MEDICATION_LIST"
    case bill = "BILL"
    case eob = "EOB"
    case insuranceCard = "INSURANCE_CARD"
    case other = "OTHER"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .prescription: return "Prescription"
        case .labResult: return "Lab Results"
        case .discharge: return "Discharge Summary"
        case .appointment: return "Appointment"
        case .medicationList: return "Medication List"
        case .bill: return "Bill / Invoice"
        case .eob: return "Insurance EOB"
        case .insuranceCard: return "Insurance Card"
        case .other: return "Other Document"
        }
    }

    var icon: String {
        switch self {
        case .prescription: return "pills.fill"
        case .labResult: return "flask.fill"
        case .discharge: return "building.2.fill"
        case .appointment: return "calendar"
        case .medicationList: return "list.bullet.clipboard.fill"
        case .bill: return "dollarsign.circle.fill"
        case .eob: return "shield.fill"
        case .insuranceCard: return "creditcard.fill"
        case .other: return "doc.fill"
        }
    }

    var defaultRoutingTarget: RoutingTarget {
        switch self {
        case .prescription, .medicationList: return .binder
        case .labResult, .discharge: return .handoff
        case .bill, .eob: return .billing
        case .insuranceCard: return .binder
        case .appointment: return .binder // Routes to CONTACT binder item
        case .other: return .inbox
        }
    }

    var binderItemType: String? {
        switch self {
        case .prescription, .medicationList: return "MED"
        case .insuranceCard: return "INSURANCE"
        case .appointment: return "CONTACT"
        default: return nil
        }
    }

    /// Categories grouped for UI display
    static var medicalDocuments: [DocumentType] {
        [.prescription, .labResult, .discharge, .medicationList]
    }

    static var financialDocuments: [DocumentType] {
        [.bill, .eob]
    }

    static var otherDocuments: [DocumentType] {
        [.insuranceCard, .appointment, .other]
    }
}

// MARK: - Routing Target

enum RoutingTarget: String, Codable, CaseIterable {
    case binder = "BINDER"
    case billing = "BILLING"
    case handoff = "HANDOFF"
    case inbox = "INBOX"

    var displayName: String {
        switch self {
        case .binder: return "Care Binder"
        case .billing: return "Billing"
        case .handoff: return "Timeline"
        case .inbox: return "Care Inbox"
        }
    }

    var icon: String {
        switch self {
        case .binder: return "folder.fill"
        case .billing: return "dollarsign.circle.fill"
        case .handoff: return "clock.fill"
        case .inbox: return "tray.fill"
        }
    }
}

// MARK: - GRDB Conformance

extension DocumentScan: FetchableRecord, PersistableRecord {
    static let databaseTableName = "documentScans"

    // Column names matching local GRDB schema (camelCase)
    enum Columns: String, ColumnExpression {
        case id
        case circleId
        case patientId
        case createdBy
        case storageKeysJson
        case pageCount
        case ocrText
        case ocrConfidence
        case ocrProvider
        case documentType
        case classificationConfidence
        case classificationSource
        case extractedFieldsJson
        case extractionConfidence
        case routedToType
        case routedToId
        case routedAt
        case routedBy
        case status
        case errorMessage
        case createdAt
        case updatedAt
    }

    // Custom encoding to handle storageKeys -> storageKeysJson
    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.circleId] = circleId
        container[Columns.patientId] = patientId
        container[Columns.createdBy] = createdBy
        container[Columns.storageKeysJson] = (try? JSONEncoder().encode(storageKeys))
            .flatMap { String(data: $0, encoding: .utf8) }
        container[Columns.pageCount] = pageCount
        container[Columns.ocrText] = ocrText
        container[Columns.ocrConfidence] = ocrConfidence
        container[Columns.ocrProvider] = ocrProvider?.rawValue
        container[Columns.documentType] = documentType?.rawValue
        container[Columns.classificationConfidence] = classificationConfidence
        container[Columns.classificationSource] = classificationSource?.rawValue
        container[Columns.extractedFieldsJson] = extractedFieldsJson
        container[Columns.extractionConfidence] = extractionConfidence
        container[Columns.routedToType] = routedToType?.rawValue
        container[Columns.routedToId] = routedToId
        container[Columns.routedAt] = routedAt
        container[Columns.routedBy] = routedBy
        container[Columns.status] = status.rawValue
        container[Columns.errorMessage] = errorMessage
        container[Columns.createdAt] = createdAt
        container[Columns.updatedAt] = updatedAt
    }

    // Custom decoding to handle storageKeysJson -> storageKeys
    init(row: Row) throws {
        id = row[Columns.id]
        circleId = row[Columns.circleId]
        patientId = row[Columns.patientId]
        createdBy = row[Columns.createdBy]

        // Decode storageKeys from JSON
        if let jsonString: String = row[Columns.storageKeysJson],
           let data = jsonString.data(using: .utf8),
           let keys = try? JSONDecoder().decode([String].self, from: data) {
            storageKeys = keys
        } else {
            storageKeys = []
        }

        pageCount = row[Columns.pageCount]
        ocrText = row[Columns.ocrText]
        ocrConfidence = row[Columns.ocrConfidence]

        if let providerString: String = row[Columns.ocrProvider] {
            ocrProvider = OCRProvider(rawValue: providerString)
        } else {
            ocrProvider = nil
        }

        if let typeString: String = row[Columns.documentType] {
            documentType = DocumentType(rawValue: typeString)
        } else {
            documentType = nil
        }

        classificationConfidence = row[Columns.classificationConfidence]

        if let sourceString: String = row[Columns.classificationSource] {
            classificationSource = ClassificationSource(rawValue: sourceString)
        } else {
            classificationSource = nil
        }

        extractedFieldsJson = row[Columns.extractedFieldsJson]
        extractionConfidence = row[Columns.extractionConfidence]

        if let targetString: String = row[Columns.routedToType] {
            routedToType = RoutingTarget(rawValue: targetString)
        } else {
            routedToType = nil
        }

        routedToId = row[Columns.routedToId]
        routedAt = row[Columns.routedAt]
        routedBy = row[Columns.routedBy]

        if let statusString: String = row[Columns.status] {
            status = ScanStatus(rawValue: statusString) ?? .pending
        } else {
            status = .pending
        }

        errorMessage = row[Columns.errorMessage]
        createdAt = row[Columns.createdAt]
        updatedAt = row[Columns.updatedAt]
    }
}

// MARK: - Classification Result

struct ClassificationResult: Codable {
    let documentType: DocumentType
    let confidence: Double
    let source: DocumentScan.ClassificationSource
    let alternates: [AlternateClassification]?

    struct AlternateClassification: Codable {
        let type: DocumentType
        let confidence: Double
    }

    var isHighConfidence: Bool { confidence >= 0.8 }
    var isMediumConfidence: Bool { confidence >= 0.5 && confidence < 0.8 }
    var isLowConfidence: Bool { confidence < 0.5 }
}

// MARK: - Extraction Result

struct ExtractionResult: Codable {
    let fields: [String: AnyCodableValue]
    let confidence: Double

    func value<T>(for key: String) -> T? {
        fields[key]?.value as? T
    }

    func stringValue(for key: String) -> String? {
        guard let anyValue = fields[key] else { return nil }
        switch anyValue {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        default: return nil
        }
    }
}

// MARK: - AnyCodable Helper

enum AnyCodableValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    var value: Any? {
        switch self {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .array(let a): return a.map { $0.value }
        case .dictionary(let d): return d.mapValues { $0.value }
        case .null: return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodableValue].self) {
            self = .array(array)
        } else if let dict = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(dict)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .array(let a): try container.encode(a)
        case .dictionary(let d): try container.encode(d)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - Routing Result

struct RoutingResult: Codable {
    let targetId: String
    let targetType: String
    let attachmentIds: [String]
}

// MARK: - Usage Info

struct ScanUsageInfo: Codable {
    let allowed: Bool
    let current: Int?
    let limit: Int?
    let tier: String
    let unlimited: Bool?

    var remaining: Int? {
        guard let limit = limit, let current = current else { return nil }
        return max(0, limit - current)
    }

    var isNearLimit: Bool {
        guard let remaining = remaining else { return false }
        return remaining <= 1
    }

    var usageDescription: String {
        if unlimited == true {
            return "Unlimited scans"
        } else if let current = current, let limit = limit {
            return "\(current)/\(limit) scans used this month"
        } else {
            return "Usage unavailable"
        }
    }
}
