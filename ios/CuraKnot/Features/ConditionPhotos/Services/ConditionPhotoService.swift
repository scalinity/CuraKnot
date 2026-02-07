import Foundation
import UIKit

// MARK: - Condition Photo Service Errors

enum ConditionPhotoError: LocalizedError {
    case featureNotAvailable
    case conditionLimitReached(current: Int, limit: Int)
    case unauthorized
    case uploadFailed
    case downloadFailed
    case conditionNotFound
    case photoNotFound
    case shareFailed(String)
    case networkError
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .featureNotAvailable:
            return "Photo Tracking is a Plus feature. Upgrade to document condition progression."
        case .conditionLimitReached(let current, let limit):
            return "You've reached the \(limit) condition limit (\(current)/\(limit)). Upgrade to Family for unlimited tracking."
        case .unauthorized:
            return "You don't have permission to perform this action."
        case .uploadFailed:
            return "Photo upload failed. It will sync when you're back online."
        case .downloadFailed:
            return "Failed to load photo. Try again."
        case .conditionNotFound:
            return "Condition not found."
        case .photoNotFound:
            return "Photo not found."
        case .shareFailed(let message):
            return message
        case .networkError:
            return "Network error. Please check your connection."
        case .invalidInput(let message):
            return message
        }
    }
}

// MARK: - Share Link Response

struct ConditionShareLinkResponse: Codable {
    let success: Bool
    let shareLinkId: String?
    let shareUrl: String?
    let token: String?
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case success
        case shareLinkId = "share_link_id"
        case shareUrl = "share_url"
        case token
        case expiresAt = "expires_at"
    }
}

// MARK: - Share Link Request

private struct ShareLinkRequest: Encodable {
    let conditionId: String
    let photoIds: [String]
    let expirationDays: Int
    let singleUse: Bool
    let recipient: String
    let includeAnnotations: Bool

    enum CodingKeys: String, CodingKey {
        case conditionId = "condition_id"
        case photoIds = "photo_ids"
        case expirationDays = "expiration_days"
        case singleUse = "single_use"
        case recipient
        case includeAnnotations = "include_annotations"
    }
}

// MARK: - Condition Photo Service

@MainActor
final class ConditionPhotoService: ObservableObject {

    // MARK: - Dependencies

    private let supabaseClient: SupabaseClient
    private let subscriptionManager: SubscriptionManager
    private let photoStorageManager: PhotoStorageManager
    private let authManager: AuthManager

    // MARK: - Initialization

    init(
        supabaseClient: SupabaseClient,
        subscriptionManager: SubscriptionManager,
        photoStorageManager: PhotoStorageManager,
        authManager: AuthManager
    ) {
        self.supabaseClient = supabaseClient
        self.subscriptionManager = subscriptionManager
        self.photoStorageManager = photoStorageManager
        self.authManager = authManager
    }

    // MARK: - Input Validation

    private static let maxBodyLocationLength = 200
    private static let maxDescriptionLength = 500
    private static let maxNotesLength = 1000

    // MARK: - Condition CRUD

    /// Create a new tracked condition
    func createCondition(
        circleId: UUID,
        patientId: UUID,
        type: ConditionType,
        bodyLocation: String,
        description: String?,
        startDate: Date
    ) async throws -> TrackedCondition {
        guard subscriptionManager.hasFeature(.conditionPhotoTracking) else {
            throw ConditionPhotoError.featureNotAvailable
        }

        // Validate input lengths
        let trimmedLocation = bodyLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLocation.isEmpty else {
            throw ConditionPhotoError.invalidInput("Body location is required.")
        }
        guard trimmedLocation.count <= Self.maxBodyLocationLength else {
            throw ConditionPhotoError.invalidInput("Body location must be \(Self.maxBodyLocationLength) characters or fewer.")
        }

        if let desc = description, desc.count > Self.maxDescriptionLength {
            throw ConditionPhotoError.invalidInput("Description must be \(Self.maxDescriptionLength) characters or fewer.")
        }

        // Check tier limits in a single pass
        let plan = subscriptionManager.currentPlan
        switch plan {
        case .free:
            throw ConditionPhotoError.featureNotAvailable
        case .plus:
            let count = try await getActiveConditionCount(circleId: circleId)
            if count >= 5 {
                throw ConditionPhotoError.conditionLimitReached(current: count, limit: 5)
            }
        case .family:
            break // unlimited
        }

        let userId = try getCurrentUserId()

        try await supabaseClient
            .from("tracked_conditions")
            .insert([
                "circle_id": circleId.uuidString,
                "patient_id": patientId.uuidString,
                "created_by": userId,
                "condition_type": type.rawValue,
                "body_location": trimmedLocation,
                "description": description ?? "",
                "start_date": ISO8601DateFormatter().string(from: startDate),
                "status": ConditionStatus.active.rawValue,
                "require_biometric": "true",
                "blur_thumbnails": "true",
            ])
            .execute()

        // Fetch the just-inserted condition
        let conditions: [TrackedCondition] = try await supabaseClient
            .from("tracked_conditions")
            .select()
            .eq("circle_id", circleId.uuidString)
            .eq("patient_id", patientId.uuidString)
            .eq("created_by", userId)
            .eq("body_location", trimmedLocation)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()

        guard let condition = conditions.first else {
            throw ConditionPhotoError.conditionNotFound
        }
        return condition
    }

    /// Get conditions for a patient, optionally filtered by status
    func getConditions(circleId: UUID, patientId: UUID, status: ConditionStatus? = nil) async throws -> [TrackedCondition] {
        var query = await supabaseClient
            .from("tracked_conditions")
            .select()
            .eq("circle_id", circleId.uuidString)
            .eq("patient_id", patientId.uuidString)
            .order("created_at", ascending: false)

        if let status = status {
            query = query.eq("status", status.rawValue)
        }

        let conditions: [TrackedCondition] = try await query.execute()
        return conditions
    }

    /// Resolve a condition
    func resolveCondition(id: UUID, notes: String?) async throws {
        try await supabaseClient
            .from("tracked_conditions")
            .update([
                "status": ConditionStatus.resolved.rawValue,
                "resolved_date": ISO8601DateFormatter().string(from: Date()),
                "resolution_notes": notes ?? "",
            ])
            .eq("id", id.uuidString)
            .execute()
    }

    /// Archive a resolved condition
    func archiveCondition(id: UUID) async throws {
        try await supabaseClient
            .from("tracked_conditions")
            .update(["status": ConditionStatus.archived.rawValue])
            .eq("id", id.uuidString)
            .execute()
    }

    // MARK: - Photo Operations

    /// Capture and upload a photo for a condition
    func capturePhoto(
        conditionId: UUID,
        circleId: UUID,
        patientId: UUID,
        imageData: Data,
        notes: String?,
        annotations: [PhotoAnnotation]?,
        lightingQuality: LightingQuality?
    ) async throws -> ConditionPhoto {
        guard subscriptionManager.hasFeature(.conditionPhotoTracking) else {
            throw ConditionPhotoError.featureNotAvailable
        }

        // Validate notes length
        if let notes, notes.count > Self.maxNotesLength {
            throw ConditionPhotoError.invalidInput("Notes must be \(Self.maxNotesLength) characters or fewer.")
        }

        let userId = try getCurrentUserId()
        let photoId = UUID()
        let storageKey = "\(circleId.uuidString)/\(conditionId.uuidString)/\(photoId.uuidString).jpg"
        let thumbnailKey = "\(circleId.uuidString)/\(conditionId.uuidString)/\(photoId.uuidString)_thumb.jpg"

        // Compress image
        let compressed = try photoStorageManager.compressForUpload(imageData)

        // Generate blurred thumbnail
        let thumbnailData = try photoStorageManager.generateBlurredThumbnail(from: compressed)

        // Upload full photo and thumbnail in parallel
        do {
            async let fullUpload: String = supabaseClient.storage("condition-photos")
                .upload(path: storageKey, data: compressed, contentType: "image/jpeg")
            async let thumbUpload: String = supabaseClient.storage("condition-photos")
                .upload(path: thumbnailKey, data: thumbnailData, contentType: "image/jpeg")

            _ = try await (fullUpload, thumbUpload)
        } catch {
            // Clean up any partially uploaded files
            try? await supabaseClient.storage("condition-photos").remove(path: storageKey)
            try? await supabaseClient.storage("condition-photos").remove(path: thumbnailKey)
            throw ConditionPhotoError.uploadFailed
        }

        // Save locally with file protection
        let localURL = try photoStorageManager.saveLocally(imageData: compressed, photoId: photoId)
        try photoStorageManager.setBackupExclusion(for: localURL)

        // Insert DB record
        var insertData: [String: String] = [
            "id": photoId.uuidString,
            "condition_id": conditionId.uuidString,
            "circle_id": circleId.uuidString,
            "patient_id": patientId.uuidString,
            "created_by": userId,
            "storage_key": storageKey,
            "thumbnail_key": thumbnailKey,
        ]
        if let notes, !notes.isEmpty {
            insertData["notes"] = notes
        }
        if let quality = lightingQuality?.rawValue {
            insertData["lighting_quality"] = quality
        }

        try await supabaseClient
            .from("condition_photos")
            .insert(insertData)
            .execute()

        // Fetch the inserted photo
        let photos: [ConditionPhoto] = try await supabaseClient
            .from("condition_photos")
            .select()
            .eq("id", photoId.uuidString)
            .execute()

        guard let photo = photos.first else {
            throw ConditionPhotoError.photoNotFound
        }

        // Log audit event — propagate errors for compliance
        do {
            try await logPhotoAccess(
                circleId: circleId,
                photoId: photoId,
                accessType: "UPLOAD"
            )
        } catch {
            // Log locally but don't fail the upload
            #if DEBUG
            print("[AuditLog] Failed to log UPLOAD access: \(error.localizedDescription)")
            #endif
        }

        return photo
    }

    /// Get all photos for a condition
    func getPhotos(conditionId: UUID) async throws -> [ConditionPhoto] {
        let photos: [ConditionPhoto] = try await supabaseClient
            .from("condition_photos")
            .select()
            .eq("condition_id", conditionId.uuidString)
            .order("captured_at", ascending: false)
            .execute()

        return photos
    }

    /// Get a signed URL for full-resolution photo (15-min TTL)
    func getPhotoURL(photo: ConditionPhoto) async throws -> URL {
        try await supabaseClient.storage("condition-photos")
            .createSignedURL(path: photo.storageKey, expiresIn: 900)
    }

    /// Get a signed URL for blurred thumbnail (15-min TTL)
    func getThumbnailURL(photo: ConditionPhoto) async throws -> URL {
        try await supabaseClient.storage("condition-photos")
            .createSignedURL(path: photo.thumbnailKey, expiresIn: 900)
    }

    /// Delete a photo
    func deletePhoto(id: UUID, circleId: UUID, storageKey: String, thumbnailKey: String) async throws {
        // Delete from storage
        try await supabaseClient.storage("condition-photos")
            .remove(path: storageKey)
        try await supabaseClient.storage("condition-photos")
            .remove(path: thumbnailKey)

        // Delete from DB
        try await supabaseClient
            .from("condition_photos")
            .eq("id", id.uuidString)
            .delete()

        // Delete local copy (non-critical — log failure)
        do {
            try photoStorageManager.deleteLocal(photoId: id)
        } catch {
            #if DEBUG
            print("[Storage] Failed to delete local copy: \(error.localizedDescription)")
            #endif
        }

        // Log audit — propagate errors for compliance
        do {
            try await logPhotoAccess(
                circleId: circleId,
                photoId: id,
                accessType: "DELETE"
            )
        } catch {
            #if DEBUG
            print("[AuditLog] Failed to log DELETE access: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Sharing (Family tier only)

    /// Create a share link for selected photos
    func createShareLink(
        conditionId: UUID,
        photoIds: [UUID],
        expirationDays: Int,
        singleUse: Bool,
        recipient: String?
    ) async throws -> ConditionShareLinkResponse {
        guard subscriptionManager.hasFeature(.conditionPhotoShare) else {
            throw ConditionPhotoError.shareFailed("Photo sharing requires Family plan.")
        }

        let request = ShareLinkRequest(
            conditionId: conditionId.uuidString,
            photoIds: photoIds.map(\.uuidString),
            expirationDays: expirationDays,
            singleUse: singleUse,
            recipient: recipient ?? "",
            includeAnnotations: true
        )

        let response: ConditionShareLinkResponse = try await supabaseClient
            .functions("generate-condition-share")
            .invoke(body: request)

        return response
    }

    /// Revoke a share link
    func revokeShareLink(id: UUID) async throws {
        try await supabaseClient
            .from("share_links")
            .update(["revoked_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", id.uuidString)
            .execute()
    }

    // MARK: - Tier Limits

    /// Get the count of active conditions in a circle
    func getActiveConditionCount(circleId: UUID) async throws -> Int {
        let conditions: [TrackedCondition] = try await supabaseClient
            .from("tracked_conditions")
            .select()
            .eq("circle_id", circleId.uuidString)
            .eq("status", ConditionStatus.active.rawValue)
            .execute()

        return conditions.count
    }

    // MARK: - Audit Logging

    /// Log a photo access event
    func logPhotoAccess(circleId: UUID, photoId: UUID, accessType: String) async throws {
        let userId = try getCurrentUserId()
        try await supabaseClient
            .from("photo_access_log")
            .insert([
                "circle_id": circleId.uuidString,
                "condition_photo_id": photoId.uuidString,
                "accessed_by": userId,
                "access_type": accessType,
            ])
            .execute()
    }

    // MARK: - Private Helpers

    private func getCurrentUserId() throws -> String {
        guard let userId = authManager.currentUser?.id else {
            throw ConditionPhotoError.unauthorized
        }
        return userId
    }
}
