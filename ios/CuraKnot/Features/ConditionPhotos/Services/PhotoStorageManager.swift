import Foundation
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Photo Storage Manager

final class PhotoStorageManager: Sendable {

    // MARK: - Types

    enum PhotoStorageError: LocalizedError {
        case invalidImage
        case writeFailed
        case deleteFailed
        case blurFailed
        case directoryCreationFailed
        case compressionFailed

        var errorDescription: String? {
            switch self {
            case .invalidImage: return "Invalid image data"
            case .writeFailed: return "Failed to save photo locally"
            case .deleteFailed: return "Failed to delete photo"
            case .blurFailed: return "Failed to generate blurred thumbnail"
            case .directoryCreationFailed: return "Failed to create storage directory"
            case .compressionFailed: return "Failed to compress image to target size"
            }
        }
    }

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let ciContext = CIContext()
    private let storageDirectory: URL

    // MARK: - Initialization

    init() throws {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw PhotoStorageError.directoryCreationFailed
        }
        self.storageDirectory = appSupport.appendingPathComponent("ConditionPhotos", isDirectory: true)
        try ensureDirectoryExists()
    }

    // MARK: - Public API

    /// Save photo data locally with file protection and backup exclusion
    func saveLocally(imageData: Data, photoId: UUID) throws -> URL {
        guard !imageData.isEmpty else {
            throw PhotoStorageError.invalidImage
        }

        try ensureDirectoryExists()

        let fileURL = storageDirectory.appendingPathComponent("\(photoId.uuidString).jpg")

        guard fileManager.createFile(atPath: fileURL.path, contents: imageData) else {
            throw PhotoStorageError.writeFailed
        }

        // Set file protection
        try setFileProtection(for: fileURL)

        // Exclude from backups
        try setBackupExclusion(for: fileURL)

        return fileURL
    }

    /// Generate a Gaussian-blurred thumbnail from image data
    func generateBlurredThumbnail(from imageData: Data, blurRadius: CGFloat = 20, thumbnailSize: CGSize = CGSize(width: 200, height: 200)) throws -> Data {
        guard imageData.count > 0 else {
            throw PhotoStorageError.invalidImage
        }

        guard thumbnailSize.width > 0, thumbnailSize.height > 0,
              thumbnailSize.width <= 1000, thumbnailSize.height <= 1000 else {
            throw PhotoStorageError.invalidImage
        }

        guard let uiImage = UIImage(data: imageData) else {
            throw PhotoStorageError.invalidImage
        }

        // Resize to thumbnail dimensions
        let thumbnail = resizeImage(uiImage, to: thumbnailSize)

        guard let ciImage = CIImage(image: thumbnail) else {
            throw PhotoStorageError.blurFailed
        }

        // Apply Gaussian blur
        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = ciImage
        blurFilter.radius = Float(blurRadius)

        guard let outputImage = blurFilter.outputImage else {
            throw PhotoStorageError.blurFailed
        }

        // Render with extent matching original (blur expands the image)
        guard let cgImage = ciContext.createCGImage(outputImage, from: ciImage.extent) else {
            throw PhotoStorageError.blurFailed
        }

        let blurredImage = UIImage(cgImage: cgImage)
        guard let jpegData = blurredImage.jpegData(compressionQuality: 0.6) else {
            throw PhotoStorageError.blurFailed
        }

        return jpegData
    }

    /// Delete a locally stored photo
    func deleteLocal(photoId: UUID) throws {
        let fileURL = storageDirectory.appendingPathComponent("\(photoId.uuidString).jpg")

        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.removeItem(at: fileURL)
            } catch {
                throw PhotoStorageError.deleteFailed
            }
        }
    }

    /// Compress image data for upload (max 10MB target)
    func compressForUpload(_ imageData: Data, maxBytes: Int = 10_485_760) throws -> Data {
        guard let image = UIImage(data: imageData) else {
            throw PhotoStorageError.invalidImage
        }

        var quality: CGFloat = 0.9
        var compressed = image.jpegData(compressionQuality: quality) ?? imageData
        let maxIterations = 9 // quality goes from 0.9 to 0.1 in steps of 0.1

        var iteration = 0
        while compressed.count > maxBytes && quality > 0.1 && iteration < maxIterations {
            quality -= 0.1
            compressed = image.jpegData(compressionQuality: quality) ?? compressed
            iteration += 1
        }

        if compressed.count > maxBytes {
            throw PhotoStorageError.compressionFailed
        }

        return compressed
    }

    // MARK: - File Protection

    func setFileProtection(for url: URL) throws {
        try (url as NSURL).setResourceValue(
            URLFileProtection.complete,
            forKey: .fileProtectionKey
        )
    }

    func setBackupExclusion(for url: URL) throws {
        var mutableURL = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try mutableURL.setResourceValues(resourceValues)
    }

    // MARK: - Private Helpers

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: storageDirectory.path) {
            do {
                try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            } catch {
                throw PhotoStorageError.directoryCreationFailed
            }
        }

        // Exclude entire directory from backups
        try setBackupExclusion(for: storageDirectory)
    }

    private func resizeImage(_ image: UIImage, to targetSize: CGSize) -> UIImage {
        let widthRatio = targetSize.width / image.size.width
        let heightRatio = targetSize.height / image.size.height
        let ratio = min(widthRatio, heightRatio)
        let newSize = CGSize(
            width: image.size.width * ratio,
            height: image.size.height * ratio
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
