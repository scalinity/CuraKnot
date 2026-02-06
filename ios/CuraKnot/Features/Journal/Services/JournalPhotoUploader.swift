import Foundation
import UIKit

// MARK: - Journal Photo Uploader

/// Handles photo upload to Supabase Storage for journal entries
/// Photos are stored at: journal/{circle_id}/{entry_id}/photo_{index}.jpg
struct JournalPhotoUploader {

    // MARK: - Constants

    static let maxPhotoSizeBytes = 5 * 1024 * 1024  // 5MB
    static let maxPhotosPerEntry = 3
    static let compressionQuality: CGFloat = 0.8
    static let lowerCompressionQuality: CGFloat = 0.5
    static let maxDimension: CGFloat = 1920

    /// Storage bucket name - centralized to avoid hardcoding
    static let storageBucket = "handoff-attachments"

    /// Storage path prefix for journal photos
    static let journalPathPrefix = "journal"

    // MARK: - Upload Methods

    /// Upload a single photo to Supabase Storage
    /// - Parameters:
    ///   - image: The UIImage to upload
    ///   - circleId: The circle ID for the path
    ///   - entryId: The entry ID for the path
    ///   - index: The photo index (0-2)
    ///   - supabaseClient: The Supabase client for uploads
    /// - Returns: The storage key path
    static func upload(
        image: UIImage,
        circleId: String,
        entryId: String,
        index: Int,
        supabaseClient: SupabaseClient
    ) async throws -> String {
        // Resize if needed
        let resizedImage = resizeIfNeeded(image, maxDimension: maxDimension)

        // Compress to JPEG
        guard var imageData = resizedImage.jpegData(compressionQuality: compressionQuality) else {
            throw JournalPhotoError.compressionFailed
        }

        // If still too large, try lower quality
        if imageData.count > maxPhotoSizeBytes {
            guard let lowerQualityData = resizedImage.jpegData(compressionQuality: lowerCompressionQuality) else {
                throw JournalPhotoError.compressionFailed
            }
            guard lowerQualityData.count <= maxPhotoSizeBytes else {
                throw JournalPhotoError.photoTooLarge
            }
            imageData = lowerQualityData
        }

        // Upload to Supabase Storage
        let storagePath = "\(journalPathPrefix)/\(circleId)/\(entryId)/photo_\(index).jpg"

        _ = try await supabaseClient.storage(storageBucket)
            .upload(path: storagePath, data: imageData, contentType: "image/jpeg")

        return storagePath
    }

    /// Upload multiple photos for an entry (parallel for performance)
    /// - Parameters:
    ///   - images: Array of UIImages (max 3)
    ///   - circleId: The circle ID
    ///   - entryId: The entry ID
    ///   - supabaseClient: The Supabase client
    /// - Returns: Array of storage key paths
    static func uploadMultiple(
        images: [UIImage],
        circleId: String,
        entryId: String,
        supabaseClient: SupabaseClient
    ) async throws -> [String] {
        guard images.count <= maxPhotosPerEntry else {
            throw JournalPhotoError.tooManyPhotos
        }

        // Track results with their indices to maintain order
        var results: [(index: Int, path: String)] = []
        
        do {
            // Upload all photos in parallel using TaskGroup
            try await withThrowingTaskGroup(of: (Int, String).self) { group in
                for (index, image) in images.enumerated() {
                    group.addTask {
                        let path = try await upload(
                            image: image,
                            circleId: circleId,
                            entryId: entryId,
                            index: index,
                            supabaseClient: supabaseClient
                        )
                        return (index, path)
                    }
                }
                
                // Collect results
                for try await result in group {
                    results.append(result)
                }
            }
            
            // Sort by index to maintain original order
            let storageKeys = results.sorted { $0.index < $1.index }.map { $0.path }
            return storageKeys
            
        } catch {
            // Rollback: delete any successfully uploaded photos
            for result in results {
                try? await supabaseClient.storage(storageBucket).remove(path: result.path)
            }
            throw error
        }
    }

    /// Delete photos for an entry
    static func deletePhotos(
        storageKeys: [String],
        supabaseClient: SupabaseClient
    ) async {
        for key in storageKeys {
            try? await supabaseClient.storage(storageBucket).remove(path: key)
        }
    }

    /// Get a signed URL for a photo
    static func getSignedURL(
        storageKey: String,
        expiresIn: Int = 3600,
        supabaseClient: SupabaseClient
    ) async throws -> URL {
        return try await supabaseClient.storage(storageBucket)
            .createSignedURL(path: storageKey, expiresIn: expiresIn)
    }

    // MARK: - Image Processing

    /// Resize image if it exceeds max dimension while maintaining aspect ratio
    private static func resizeIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSize = max(size.width, size.height)

        guard maxSize > maxDimension else {
            return image
        }

        let scale = maxDimension / maxSize
        let newSize = CGSize(
            width: size.width * scale,
            height: size.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Photo Errors

enum JournalPhotoError: LocalizedError {
    case compressionFailed
    case photoTooLarge
    case tooManyPhotos
    case uploadFailed(String)
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "Failed to compress photo. Please try a different image."
        case .photoTooLarge:
            return "Photo is too large. Maximum size is 5MB."
        case .tooManyPhotos:
            return "Maximum 3 photos per journal entry."
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .downloadFailed:
            return "Failed to load photo. Please try again."
        }
    }
}
