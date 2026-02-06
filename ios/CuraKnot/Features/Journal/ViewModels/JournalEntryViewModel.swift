import Foundation
import UIKit
import PhotosUI
import SwiftUI

// MARK: - Journal Entry ViewModel

/// ViewModel for creating and editing journal entries
@MainActor
final class JournalEntryViewModel: ObservableObject {

    // MARK: - Entry State

    @Published var entryType: JournalEntryType = .goodMoment
    @Published var title: String = ""
    @Published var content: String = ""
    @Published var milestoneType: MilestoneType?
    @Published var visibility: EntryVisibility = .circle
    @Published var entryDate: Date = Date()
    @Published var selectedPhotos: [UIImage] = []

    // MARK: - UI State

    @Published var isLoading = false
    @Published var isSaving = false
    @Published var error: JournalValidationError?
    @Published var showingPhotoPicker = false
    @Published var showingUpgradePrompt = false
    @Published var upgradePromptFeature: String?

    // MARK: - Feature Access

    @Published var canAttachPhotos = false

    // MARK: - Properties

    let circleId: String
    let patientId: String
    private let journalService: JournalService
    private var existingEntry: JournalEntry?

    // MARK: - Initialization

    init(
        circleId: String,
        patientId: String,
        journalService: JournalService,
        existingEntry: JournalEntry? = nil
    ) {
        self.circleId = circleId
        self.patientId = patientId
        self.journalService = journalService
        self.existingEntry = existingEntry

        // Populate fields if editing
        if let entry = existingEntry {
            entryType = entry.entryType
            title = entry.title ?? ""
            content = entry.content
            milestoneType = entry.milestoneType
            visibility = entry.visibility
            entryDate = entry.entryDate
            // Note: Photos are not re-editable in MVP
        }
    }

    // MARK: - Lifecycle

    func onAppear() async {
        canAttachPhotos = await journalService.canAttachPhotos()
    }

    // MARK: - Validation

    /// Content character count
    var contentCharacterCount: Int {
        content.count
    }

    /// Check if content length is valid
    var isContentLengthValid: Bool {
        content.count >= 1 && content.count <= 2000
    }

    /// Check if the form is valid for submission
    var isValid: Bool {
        // Content is required and within limits
        guard isContentLengthValid else { return false }

        // Milestones require title and type
        if entryType == .milestone {
            guard !title.isEmpty, milestoneType != nil else { return false }
        }

        return true
    }

    /// Validation errors for display
    var validationErrors: [String] {
        var errors: [String] = []

        if content.isEmpty {
            errors.append("Please enter your thoughts")
        } else if content.count > 2000 {
            errors.append("Entry is too long (\(content.count)/2000)")
        }

        if entryType == .milestone {
            if title.isEmpty {
                errors.append("Milestones need a title")
            }
            if milestoneType == nil {
                errors.append("Please select a milestone type")
            }
        }

        return errors
    }

    // MARK: - Photo Management

    /// Add photos (with tier check)
    func addPhotos(_ images: [UIImage]) {
        guard canAttachPhotos else {
            upgradePromptFeature = "Photo attachments"
            showingUpgradePrompt = true
            return
        }

        let remaining = 3 - selectedPhotos.count
        let toAdd = Array(images.prefix(remaining))
        selectedPhotos.append(contentsOf: toAdd)
    }

    /// Remove a photo
    func removePhoto(at index: Int) {
        guard index >= 0, index < selectedPhotos.count else { return }
        selectedPhotos.remove(at: index)
    }

    /// Clear all photos
    func clearPhotos() {
        selectedPhotos.removeAll()
    }

    /// Check if more photos can be added
    var canAddMorePhotos: Bool {
        canAttachPhotos && selectedPhotos.count < 3
    }

    /// Handle photo picker button tap
    func onPhotoButtonTapped() {
        if canAttachPhotos {
            showingPhotoPicker = true
        } else {
            upgradePromptFeature = "Photo attachments"
            showingUpgradePrompt = true
        }
    }

    // MARK: - Entry Type Switching

    /// Switch entry type with appropriate cleanup
    func switchEntryType(to type: JournalEntryType) {
        entryType = type

        // Clear milestone-specific fields when switching to good moment
        if type == .goodMoment {
            title = ""
            milestoneType = nil
        }
    }

    // MARK: - Save Entry

    /// Save the journal entry
    func save() async throws -> JournalEntry {
        guard isValid else {
            throw JournalValidationError.invalidContentLength
        }

        isSaving = true
        error = nil

        defer { isSaving = false }

        do {
            if let existing = existingEntry {
                // Update existing entry using the new API
                let updated = try await journalService.updateEntry(
                    id: existing.id,
                    content: content,
                    title: entryType == .milestone ? title : nil,
                    visibility: visibility,
                    milestoneType: milestoneType
                )
                return updated
            } else {
                // Create new entry
                let entry = try await journalService.createEntry(
                    circleId: circleId,
                    patientId: patientId,
                    entryType: entryType,
                    title: entryType == .milestone ? title : nil,
                    content: content,
                    milestoneType: milestoneType,
                    visibility: visibility,
                    entryDate: entryDate,
                    photos: selectedPhotos
                )
                return entry
            }
        } catch let validationError as JournalValidationError {
            error = validationError
            throw validationError
        } catch let serviceError as JournalServiceError {
            // Convert service errors to validation errors for display
            switch serviceError {
            case .usageLimitReached(let current, let limit):
                error = .usageLimitReached(current: current, limit: limit)
            case .featureNotAvailable(let feature):
                error = .featureNotAvailable(feature)
            default:
                throw serviceError
            }
            throw serviceError
        }
    }

    // MARK: - Prompts

    /// Fetch random prompts for inspiration
    func fetchPrompts() async -> [String] {
        do {
            let prompts = try await journalService.fetchPrompts(type: entryType)
            return prompts.map { $0.promptText }
        } catch {
            return []
        }
    }

    /// Apply a prompt to the content
    func applyPrompt(_ prompt: String) {
        // Set as placeholder or append
        if content.isEmpty {
            // Could set as placeholder behavior
        }
    }

    // MARK: - Reset

    /// Reset form to initial state
    func reset() {
        entryType = .goodMoment
        title = ""
        content = ""
        milestoneType = nil
        visibility = .circle
        entryDate = Date()
        selectedPhotos = []
        error = nil
    }
}

// MARK: - Character Count Display

extension JournalEntryViewModel {

    /// Formatted character count for display
    var characterCountText: String {
        "\(contentCharacterCount)/2000"
    }

    /// Character count color based on remaining
    var characterCountColor: String {
        if contentCharacterCount > 2000 {
            return "red"
        } else if contentCharacterCount > 1800 {
            return "orange"
        }
        return "secondary"
    }
}
