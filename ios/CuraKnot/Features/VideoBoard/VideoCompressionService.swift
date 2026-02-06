import Foundation
import AVFoundation

// MARK: - Video Compression Service

/// Service for compressing video recordings to target specifications (720p HEVC @ 2Mbps)
actor VideoCompressionService {

    // MARK: - Types

    struct CompressionResult: Sendable {
        let url: URL
        let fileSizeBytes: Int64
        let durationSeconds: Double
        let resolution: CGSize
    }

    struct CompressionOptions: Sendable {
        let maxDuration: Double
        let maxWidth: Int
        let maxHeight: Int
        let targetBitrate: Int
        let useHEVC: Bool

        static let plus = CompressionOptions(
            maxDuration: 30,
            maxWidth: 1280,
            maxHeight: 720,
            targetBitrate: 2_000_000,
            useHEVC: true
        )

        static let family = CompressionOptions(
            maxDuration: 60,
            maxWidth: 1280,
            maxHeight: 720,
            targetBitrate: 2_000_000,
            useHEVC: true
        )
    }

    enum CompressionError: LocalizedError {
        case invalidInput
        case invalidFileType
        case exportFailed(Error)
        case fileTooLarge(Int64)
        case timeout
        case unsupportedCodec
        case cancelled

        var errorDescription: String? {
            switch self {
            case .invalidInput:
                return "The video file is invalid or cannot be read."
            case .invalidFileType:
                return "The file is not a valid video format."
            case .exportFailed(let error):
                return "Video compression failed: \(error.localizedDescription)"
            case .fileTooLarge(let size):
                let sizeMB = Double(size) / 1_048_576
                return String(format: "Compressed video is too large (%.1f MB). Try a shorter recording.", sizeMB)
            case .timeout:
                return "Video compression timed out. Please try again."
            case .unsupportedCodec:
                return "Your device doesn't support the required video format."
            case .cancelled:
                return "Video compression was cancelled."
            }
        }
    }

    // MARK: - File Validation
    
    /// Validate that file has valid video magic bytes
    private func validateVideoFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CompressionError.invalidInput
        }
        
        // Read first 12 bytes to check for common video container signatures
        guard let handle = FileHandle(forReadingAtPath: url.path) else {
            throw CompressionError.invalidInput
        }
        defer { try? handle.close() }
        
        let magicBytes = handle.readData(ofLength: 12)
        guard magicBytes.count >= 8 else {
            throw CompressionError.invalidFileType
        }
        
        // Check for valid video container formats
        let bytes = [UInt8](magicBytes)
        
        // MOV/MP4 (ftyp box) - common for iOS recordings
        // Offset 4: 'ftyp' (0x66 0x74 0x79 0x70)
        if bytes.count >= 8 {
            if bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70 {
                return // Valid MP4/MOV
            }
        }
        
        // QuickTime container (moov or free at start)
        if bytes.count >= 8 {
            // moov (0x6D 0x6F 0x6F 0x76)
            if bytes[4] == 0x6D && bytes[5] == 0x6F && bytes[6] == 0x6F && bytes[7] == 0x76 {
                return // Valid QuickTime
            }
            // free (0x66 0x72 0x65 0x65)
            if bytes[4] == 0x66 && bytes[5] == 0x72 && bytes[6] == 0x65 && bytes[7] == 0x65 {
                return // Valid QuickTime
            }
            // wide (0x77 0x69 0x64 0x65)
            if bytes[4] == 0x77 && bytes[5] == 0x69 && bytes[6] == 0x64 && bytes[7] == 0x65 {
                return // Valid QuickTime
            }
            // mdat (0x6D 0x64 0x61 0x74)
            if bytes[4] == 0x6D && bytes[5] == 0x64 && bytes[6] == 0x61 && bytes[7] == 0x74 {
                return // Valid QuickTime
            }
        }
        
        throw CompressionError.invalidFileType
    }

    // MARK: - Compression

    /// Compress a video to the specified options
    /// - Parameters:
    ///   - sourceURL: URL of the source video file
    ///   - options: Compression options (resolution, bitrate, duration)
    ///   - progressHandler: Called with progress (0.0-1.0)
    /// - Returns: CompressionResult with the compressed file URL and metadata
    func compress(
        sourceURL: URL,
        options: CompressionOptions,
        progressHandler: (@Sendable (Double) async -> Void)? = nil
    ) async throws -> CompressionResult {
        // Validate input file exists and is a valid video
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw CompressionError.invalidInput
        }
        
        // Validate file type using magic bytes
        try validateVideoFile(at: sourceURL)

        let asset = AVURLAsset(url: sourceURL)

        // Get video duration
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        guard durationSeconds > 0 else {
            throw CompressionError.invalidInput
        }

        // Calculate time range (limit to max duration)
        let effectiveDuration = min(durationSeconds, options.maxDuration)
        let timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: effectiveDuration, preferredTimescale: 600)
        )

        // Determine export preset based on device capabilities
        let preset = await determineExportPreset(options: options)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw CompressionError.unsupportedCodec
        }

        // Create output URL
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = timeRange
        exportSession.shouldOptimizeForNetworkUse = true

        // Apply video composition for resolution limiting if needed
        if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first {
            let naturalSize = try await videoTrack.load(.naturalSize)
            let transform = try await videoTrack.load(.preferredTransform)

            // Apply transform to get actual dimensions
            let transformedSize = naturalSize.applying(transform)
            let actualWidth = abs(transformedSize.width)
            let actualHeight = abs(transformedSize.height)

            // Only apply composition if source is larger than target
            if actualWidth > CGFloat(options.maxWidth) || actualHeight > CGFloat(options.maxHeight) {
                let composition = try await createResizedComposition(
                    asset: asset,
                    maxWidth: options.maxWidth,
                    maxHeight: options.maxHeight,
                    timeRange: timeRange
                )
                exportSession.videoComposition = composition
            }
        }

        // Start progress monitoring
        let progressTask = Task {
            while !Task.isCancelled {
                let progress = Double(exportSession.progress)
                await progressHandler?(progress)

                if exportSession.status == .completed || exportSession.status == .failed || exportSession.status == .cancelled {
                    break
                }

                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }

        // Export
        await exportSession.export()
        progressTask.cancel()

        // Check result
        switch exportSession.status {
        case .completed:
            // Get file size
            let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0

            // Get actual resolution
            let outputAsset = AVURLAsset(url: outputURL)
            var resolution = CGSize(width: options.maxWidth, height: options.maxHeight)
            if let outputTrack = try? await outputAsset.loadTracks(withMediaType: .video).first {
                let naturalSize = try await outputTrack.load(.naturalSize)
                let transform = try await outputTrack.load(.preferredTransform)
                let transformedSize = naturalSize.applying(transform)
                resolution = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
            }

            return CompressionResult(
                url: outputURL,
                fileSizeBytes: fileSize,
                durationSeconds: effectiveDuration,
                resolution: resolution
            )

        case .failed:
            throw CompressionError.exportFailed(exportSession.error ?? NSError(domain: "VideoCompression", code: -1))

        case .cancelled:
            throw CompressionError.cancelled

        default:
            throw CompressionError.exportFailed(NSError(domain: "VideoCompression", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Unknown export status: \(exportSession.status.rawValue)"
            ]))
        }
    }

    /// Extract duration from a video file
    func extractDuration(from url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }

    /// Estimate file size for a given duration and bitrate
    func estimateFileSize(durationSeconds: Double, bitrateBps: Int) -> Int64 {
        // Bitrate is in bits per second, convert to bytes
        let bytesPerSecond = Double(bitrateBps) / 8.0
        return Int64(durationSeconds * bytesPerSecond)
    }

    // MARK: - Private Helpers

    private func determineExportPreset(options: CompressionOptions) async -> String {
        let presets = AVAssetExportSession.allExportPresets()

        // Prefer HEVC if available and requested
        if options.useHEVC {
            if presets.contains(AVAssetExportPresetHEVC1920x1080) {
                return AVAssetExportPresetHEVC1920x1080
            }
            if presets.contains(AVAssetExportPresetHEVCHighestQuality) {
                return AVAssetExportPresetHEVCHighestQuality
            }
        }

        // Fallback to H.264
        if presets.contains(AVAssetExportPreset1920x1080) {
            return AVAssetExportPreset1920x1080
        }

        if presets.contains(AVAssetExportPreset1280x720) {
            return AVAssetExportPreset1280x720
        }

        // Ultimate fallback
        return AVAssetExportPresetMediumQuality
    }

    private func createResizedComposition(
        asset: AVAsset,
        maxWidth: Int,
        maxHeight: Int,
        timeRange: CMTimeRange
    ) async throws -> AVMutableVideoComposition {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw CompressionError.invalidInput
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let transformedSize = naturalSize.applying(transform)
        let actualWidth = abs(transformedSize.width)
        let actualHeight = abs(transformedSize.height)

        // Calculate scale factor to fit within max dimensions
        let widthScale = CGFloat(maxWidth) / actualWidth
        let heightScale = CGFloat(maxHeight) / actualHeight
        let scale = min(widthScale, heightScale, 1.0) // Never scale up

        let renderSize = CGSize(
            width: floor(actualWidth * scale),
            height: floor(actualHeight * scale)
        )

        // Create composition
        let composition = AVMutableVideoComposition()
        composition.frameDuration = CMTime(value: 1, timescale: 30) // 30 fps
        composition.renderSize = renderSize

        // Create instruction
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange

        // Create layer instruction
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)

        // Calculate transform to center and scale
        var finalTransform = CGAffineTransform.identity

        // Apply original transform first
        finalTransform = finalTransform.concatenating(transform)

        // Then scale
        if scale < 1.0 {
            finalTransform = finalTransform.scaledBy(x: scale, y: scale)
        }

        layerInstruction.setTransform(finalTransform, at: .zero)

        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]

        return composition
    }
}

// MARK: - Convenience Extension

extension VideoCompressionService.CompressionOptions {
    /// Create options based on subscription plan
    static func forPlan(_ plan: SubscriptionPlan) -> VideoCompressionService.CompressionOptions {
        switch plan {
        case .free:
            // Shouldn't happen - feature gated
            return .plus
        case .plus:
            return .plus
        case .family:
            return .family
        }
    }
}
