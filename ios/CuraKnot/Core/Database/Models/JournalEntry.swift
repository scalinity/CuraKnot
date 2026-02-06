import Foundation
import GRDB

// MARK: - Journal Entry Model

/// Represents a gratitude or milestone journal entry
struct JournalEntry: Codable, Identifiable, Equatable {
    let id: String
    let circleId: String
    let patientId: String
    let createdBy: String

    // Entry content
    var entryType: JournalEntryType
    var title: String?
    var content: String
    var milestoneType: MilestoneType?

    // Photos (stored in Supabase Storage: journal/{circle_id}/{entry_id}/)
    var photoStorageKeys: [String]

    // Privacy
    var visibility: EntryVisibility

    // Entry date (can be backdated for remembering past moments)
    var entryDate: Date

    // Timestamps
    let createdAt: Date
    var updatedAt: Date

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case patientId = "patient_id"
        case createdBy = "created_by"
        case entryType = "entry_type"
        case title
        case content
        case milestoneType = "milestone_type"
        case photoStorageKeys = "photo_storage_keys"
        case visibility
        case entryDate = "entry_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // MARK: - Computed Properties

    var isMilestone: Bool {
        entryType == .milestone
    }

    var isPrivate: Bool {
        visibility == .private
    }

    var hasPhotos: Bool {
        !photoStorageKeys.isEmpty
    }

    var photoCount: Int {
        photoStorageKeys.count
    }

    /// Summary for display in lists (truncated content)
    var displaySummary: String {
        if content.count > 150 {
            return String(content.prefix(147)) + "..."
        }
        return content
    }

    /// Formatted entry date for display
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: entryDate)
    }

    /// Relative date for display
    var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: entryDate, relativeTo: Date())
    }

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        circleId: String,
        patientId: String,
        createdBy: String,
        entryType: JournalEntryType,
        title: String? = nil,
        content: String,
        milestoneType: MilestoneType? = nil,
        photoStorageKeys: [String] = [],
        visibility: EntryVisibility = .circle,
        entryDate: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.circleId = circleId
        self.patientId = patientId
        self.createdBy = createdBy
        self.entryType = entryType
        self.title = title
        self.content = content
        self.milestoneType = milestoneType
        self.photoStorageKeys = photoStorageKeys
        self.visibility = visibility
        self.entryDate = entryDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Validation

    /// Validate entry before saving
    func validate() throws {
        // Content must be 1-2000 characters
        guard content.count >= 1, content.count <= 2000 else {
            throw JournalValidationError.invalidContentLength
        }

        // Milestones require title and type
        if entryType == .milestone {
            guard let title = title, !title.isEmpty else {
                throw JournalValidationError.milestoneRequiresTitle
            }
            guard milestoneType != nil else {
                throw JournalValidationError.milestoneRequiresType
            }
        }

        // Maximum 3 photos
        guard photoStorageKeys.count <= 3 else {
            throw JournalValidationError.tooManyPhotos
        }
    }
}

// MARK: - GRDB Conformance

extension JournalEntry: FetchableRecord, PersistableRecord {
    static let databaseTableName = "journal_entries"
}

// MARK: - Input Sanitization

extension JournalEntry {

    /// Sanitized content for safe display and PDF export
    /// Removes control characters and normalizes Unicode
    var sanitizedContent: String {
        content.sanitizedForDisplay
    }

    /// Sanitized title for safe display and PDF export
    var sanitizedTitle: String? {
        title?.sanitizedForDisplay
    }

    /// Create a sanitized copy of the entry
    func sanitized() -> JournalEntry {
        var copy = self
        copy.content = content.sanitizedForDisplay
        if let title = title {
            copy.title = title.sanitizedForDisplay
        }
        return copy
    }
}

// MARK: - String Sanitization

extension String {

    /// Sanitize string for safe display and PDF rendering
    /// - Removes control characters (except newlines and tabs)
    /// - Normalizes Unicode to NFC form
    /// - Strips zero-width characters that could be used for obfuscation
    /// - Limits consecutive newlines to prevent layout abuse
    var sanitizedForDisplay: String {
        var result = self

        // Normalize Unicode to NFC (canonical decomposition, then canonical composition)
        result = result.precomposedStringWithCanonicalMapping

        // Remove control characters except newline (\n) and tab (\t)
        let controlCharacters = CharacterSet.controlCharacters
            .subtracting(CharacterSet(charactersIn: "\n\t"))
        result = result.unicodeScalars
            .filter { !controlCharacters.contains($0) }
            .map { String($0) }
            .joined()

        // Remove zero-width characters (potential obfuscation)
        let zeroWidthChars = CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{FEFF}\u{2060}")
        result = result.unicodeScalars
            .filter { !zeroWidthChars.contains($0) }
            .map { String($0) }
            .joined()

        // Limit consecutive newlines to 2 (prevent layout abuse)
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        // Trim leading/trailing whitespace
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }
}

// MARK: - Validation Errors

enum JournalValidationError: LocalizedError, Equatable {
    case invalidContentLength
    case milestoneRequiresTitle
    case milestoneRequiresType
    case tooManyPhotos
    case photoTooLarge
    case featureNotAvailable(String)
    case usageLimitReached(current: Int, limit: Int)

    var errorDescription: String? {
        switch self {
        case .invalidContentLength:
            return "Entry must be between 1 and 2000 characters."
        case .milestoneRequiresTitle:
            return "Milestones require a title."
        case .milestoneRequiresType:
            return "Please select a milestone type."
        case .tooManyPhotos:
            return "Maximum 3 photos per entry."
        case .photoTooLarge:
            return "Photo must be under 5MB."
        case .featureNotAvailable(let feature):
            return "\(feature) requires a Plus or Family subscription."
        case .usageLimitReached(let current, let limit):
            return "You've used \(current)/\(limit) journal entries this month."
        }
    }
}

// MARK: - Journal Prompt

/// System prompts for gentle encouragement (no guilt!)
struct JournalPrompt: Codable, Identifiable {
    let id: String
    let promptText: String
    let promptType: JournalEntryType
    let isActive: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case promptText = "prompt_text"
        case promptType = "prompt_type"
        case isActive = "is_active"
        case createdAt = "created_at"
    }
}

extension JournalPrompt: FetchableRecord, PersistableRecord {
    static let databaseTableName = "journal_prompts"
}

// MARK: - Usage Check Result

/// Result of checking journal usage limits
struct JournalUsageCheck: Codable {
    let allowed: Bool
    let current: Int
    let limit: Int?
    let unlimited: Bool
    let plan: String

    var remaining: Int? {
        guard let limit = limit else { return nil }
        return max(0, limit - current)
    }

    var isAtLimit: Bool {
        guard let limit = limit else { return false }
        return current >= limit
    }

    var isNearLimit: Bool {
        guard let limit = limit else { return false }
        return current >= limit - 1
    }
}
