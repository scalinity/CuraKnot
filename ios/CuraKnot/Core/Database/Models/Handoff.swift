import Foundation
import GRDB

// MARK: - Handoff Model

struct Handoff: Codable, Identifiable, Equatable {
    let id: String
    let circleId: String
    let patientId: String
    let createdBy: String
    var type: HandoffType
    var title: String
    var summary: String?
    var keywordsJson: String?
    var status: Status
    var publishedAt: Date?
    var currentRevision: Int
    var rawTranscript: String?
    var audioStorageKey: String?
    var confidenceJson: String?
    var source: Source
    var siriRawText: String?
    let createdAt: Date
    var updatedAt: Date
    var sourceLanguage: String?

    // MARK: - Handoff Type
    
    enum HandoffType: String, Codable, CaseIterable {
        case visit = "VISIT"
        case call = "CALL"
        case appointment = "APPOINTMENT"
        case facilityUpdate = "FACILITY_UPDATE"
        case other = "OTHER"
        
        var displayName: String {
            switch self {
            case .visit: return "Visit"
            case .call: return "Phone Call"
            case .appointment: return "Appointment"
            case .facilityUpdate: return "Facility Update"
            case .other: return "Other"
            }
        }
        
        var icon: String {
            switch self {
            case .visit: return "person.fill"
            case .call: return "phone.fill"
            case .appointment: return "calendar"
            case .facilityUpdate: return "building.2.fill"
            case .other: return "doc.text.fill"
            }
        }
    }
    
    // MARK: - Status
    
    enum Status: String, Codable {
        case draft = "DRAFT"
        case siriDraft = "SIRI_DRAFT"
        case published = "PUBLISHED"
        
        var displayName: String {
            switch self {
            case .draft: return "Draft"
            case .siriDraft: return "Siri Draft"
            case .published: return "Published"
            }
        }
        
        var isPending: Bool {
            self == .draft || self == .siriDraft
        }
    }
    
    // MARK: - Source
    
    enum Source: String, Codable {
        case app = "APP"
        case siri = "SIRI"
        case watch = "WATCH"
        case shortcut = "SHORTCUT"
        case helperPortal = "HELPER_PORTAL"
        
        var displayName: String {
            switch self {
            case .app: return "App"
            case .siri: return "Siri"
            case .watch: return "Apple Watch"
            case .shortcut: return "Shortcut"
            case .helperPortal: return "Helper Portal"
            }
        }
    }
    
    // MARK: - Init

    init(
        id: String, circleId: String, patientId: String, createdBy: String,
        type: HandoffType, title: String, summary: String? = nil,
        keywordsJson: String? = nil, status: Status, publishedAt: Date? = nil,
        currentRevision: Int, rawTranscript: String? = nil,
        audioStorageKey: String? = nil, confidenceJson: String? = nil,
        source: Source, siriRawText: String? = nil,
        createdAt: Date, updatedAt: Date, sourceLanguage: String? = nil
    ) {
        self.id = id
        self.circleId = circleId
        self.patientId = patientId
        self.createdBy = createdBy
        self.type = type
        self.title = title
        self.summary = summary
        self.keywordsJson = keywordsJson
        self.status = status
        self.publishedAt = publishedAt
        self.currentRevision = currentRevision
        self.rawTranscript = rawTranscript
        self.audioStorageKey = audioStorageKey
        self.confidenceJson = confidenceJson
        self.source = source
        self.siriRawText = siriRawText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceLanguage = sourceLanguage
    }

    // MARK: - Computed Properties

    // Cache for parsed keywords to avoid re-parsing JSON on every access
    private var _cachedKeywords: [String]?
    private var _cachedKeywordsJson: String?

    var keywords: [String] {
        get {
            // Return cached value if keywordsJson hasn't changed
            if let cached = _cachedKeywords, _cachedKeywordsJson == keywordsJson {
                return cached
            }
            guard let json = keywordsJson,
                  let data = json.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            // Cannot assign to self in a struct getter, so callers should use keywordsParsed()
            return array
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                keywordsJson = json
                _cachedKeywords = newValue
                _cachedKeywordsJson = json
            }
        }
    }

    /// Parse and cache keywords. Call this instead of repeated .keywords access.
    mutating func keywordsParsed() -> [String] {
        if let cached = _cachedKeywords, _cachedKeywordsJson == keywordsJson {
            return cached
        }
        let result = keywords
        _cachedKeywords = result
        _cachedKeywordsJson = keywordsJson
        return result
    }
    
    var confidence: ConfidenceScores? {
        get {
            guard let json = confidenceJson,
                  let data = json.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode(ConfidenceScores.self, from: data)
        }
        set {
            if let newValue = newValue,
               let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                confidenceJson = json
            } else {
                confidenceJson = nil
            }
        }
    }
    
    var isPublished: Bool {
        status == .published
    }
    
    /// Duration after publishing during which edits are still allowed
    static let editWindowDuration: TimeInterval = 15 * 60 // 15 minutes

    var canEdit: Bool {
        guard let publishedAt = publishedAt else { return true }
        return Date().timeIntervalSince(publishedAt) < Self.editWindowDuration
    }
}

// MARK: - GRDB Conformance

extension Handoff: FetchableRecord, PersistableRecord {
    static let databaseTableName = "handoffs"
}

// MARK: - Confidence Scores

struct ConfidenceScores: Codable, Equatable {
    var overall: Double
    var fields: FieldConfidence
    
    struct FieldConfidence: Codable, Equatable {
        var summary: Double?
        var medChanges: Double?
        var nextSteps: Double?
    }
    
    var needsReview: Bool {
        overall < 0.7 ||
        (fields.medChanges ?? 1.0) < 0.7 ||
        (fields.nextSteps ?? 1.0) < 0.7
    }
}

// MARK: - Structured Brief

struct StructuredBrief: Codable, Equatable {
    var handoffId: String
    var circleId: String
    var patientId: String
    var createdBy: String
    var createdAt: Date
    var type: Handoff.HandoffType
    var title: String
    var summary: String
    var status: BriefStatus?
    var changes: BriefChanges?
    var questionsForClinician: [ClinicalQuestion]?
    var nextSteps: [NextStep]?
    var attachments: [AttachmentRef]?
    var keywords: [String]?
    var confidence: ConfidenceScores?
    var revision: Int
    
    struct BriefStatus: Codable, Equatable {
        var moodEnergy: String?
        var pain: Int?
        var appetite: String?
        var sleep: String?
        var mobility: String?
        var safetyFlags: [String]?
    }
    
    struct BriefChanges: Codable, Equatable {
        var medChanges: [MedChange]?
        var symptomChanges: [SymptomChange]?
        var carePlanChanges: [CarePlanChange]?
    }
    
    struct MedChange: Codable, Equatable {
        var name: String
        var change: String  // START, STOP, DOSE, SCHEDULE, OTHER
        var details: String?
        var effective: Date?
    }
    
    struct SymptomChange: Codable, Equatable {
        var symptom: String
        var details: String?
    }
    
    struct CarePlanChange: Codable, Equatable {
        var area: String  // PT, OT, DIET, WOUND, OTHER
        var details: String?
    }
    
    struct ClinicalQuestion: Codable, Equatable {
        var question: String
        var priority: Priority?
    }
    
    struct NextStep: Codable, Equatable {
        var action: String
        var suggestedOwner: String?
        var due: Date?
        var priority: Priority?
    }
    
    struct AttachmentRef: Codable, Equatable {
        var attachmentId: String
        var type: String  // PHOTO, PDF, AUDIO
        var url: String?
        var sha256: String?
    }
    
    enum Priority: String, Codable {
        case low = "LOW"
        case med = "MED"
        case high = "HIGH"
    }
}
