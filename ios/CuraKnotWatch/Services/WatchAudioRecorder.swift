import Foundation
import AVFoundation
import OSLog

// MARK: - Watch Audio Recorder

private let logger = Logger(subsystem: "com.curaknot.app.watchos", category: "WatchAudioRecorder")

@MainActor
final class WatchAudioRecorder: NSObject, ObservableObject {
    // MARK: - Published Properties

    @Published var isRecording = false
    @Published var duration: TimeInterval = 0
    @Published var error: WatchAudioRecorderError?

    // MARK: - Private Properties

    private var audioRecorder: AVAudioRecorder?
    private var audioSession: AVAudioSession { AVAudioSession.sharedInstance() }
    private var timer: Timer?
    private var recordingURL: URL?

    // MARK: - Configuration

    private let maxDuration: TimeInterval = 60  // 60 second max

    // Watch-optimized settings (smaller files)
    private var recordingSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22050,                           // Lower sample rate for Watch
            AVNumberOfChannelsKey: 1,                         // Mono
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            AVEncoderBitRateKey: 64000,                       // Lower bitrate
        ]
    }

    // MARK: - Computed Properties

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var progress: Double {
        duration / maxDuration
    }

    var canRecord: Bool {
        !isRecording && error == nil
    }

    // MARK: - Recording Control

    func startRecording() async throws {
        // Reset state
        error = nil
        duration = 0

        // Configure audio session
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
        } catch {
            throw WatchAudioRecorderError.sessionError(error)
        }

        // Create recording URL in temp directory
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        recordingURL = tempDir.appendingPathComponent("handoff_\(timestamp).m4a")

        guard let url = recordingURL else {
            // Cleanup audio session on failure (CA2 fix)
            try? audioSession.setActive(false)
            throw WatchAudioRecorderError.invalidURL
        }

        // Create recorder
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: recordingSettings)
            audioRecorder?.delegate = self
            audioRecorder?.prepareToRecord()
        } catch {
            // Cleanup audio session and URL on failure (CA2 fix)
            try? audioSession.setActive(false)
            recordingURL = nil
            throw WatchAudioRecorderError.recorderError(error)
        }

        // Start recording
        guard audioRecorder?.record() == true else {
            // Clean up on failure
            audioRecorder?.stop()
            audioRecorder = nil
            recordingURL = nil
            try? audioSession.setActive(false)
            throw WatchAudioRecorderError.recordingFailed
        }

        isRecording = true
        startTimer()
    }

    func stopRecording() -> URL? {
        stopTimer()
        audioRecorder?.stop()
        audioRecorder = nil  // Clear reference for clean restart (CA1 fix)
        isRecording = false

        let url = recordingURL
        // Note: Don't nil recordingURL here - caller needs it

        do {
            try audioSession.setActive(false)
        } catch {
            logger.error("Failed to deactivate audio session: \(error.localizedDescription)")
        }

        return url
    }

    func cancelRecording() {
        stopTimer()
        audioRecorder?.stop()
        isRecording = false
        duration = 0

        // Delete recording file
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil

        do {
            try audioSession.setActive(false)
        } catch {
            logger.error("Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - Timer

    private func startTimer() {
        // Invalidate any existing timer first (CA2 fix)
        stopTimer()

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else {
                    timer.invalidate()
                    return
                }

                // Check isRecording state first to avoid race conditions (CA2 fix)
                guard self.isRecording,
                      let recorder = self.audioRecorder,
                      recorder.isRecording else {
                    timer.invalidate()
                    self.timer = nil
                    return
                }

                // Use actual recorder time to avoid drift
                self.duration = recorder.currentTime

                // Auto-stop at max duration - notify observers so the file can be transferred (DB1-Bug1)
                if self.duration >= self.maxDuration {
                    let url = self.stopRecording()
                    NotificationCenter.default.post(
                        name: .watchRecordingAutoStopped,
                        object: nil,
                        userInfo: url != nil ? ["url": url!] : nil
                    )
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - AVAudioRecorderDelegate

extension WatchAudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag {
                self.error = .recordingFailed
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.error = .encodingError(error)

            // Clean up resources on encoding error (CA2 fix)
            self.stopTimer()
            self.isRecording = false
            if let url = self.recordingURL {
                try? FileManager.default.removeItem(at: url)
            }
            self.recordingURL = nil
            try? self.audioSession.setActive(false)
        }
    }
}

// MARK: - Watch Audio Recorder Error

// MARK: - Notification Names

extension Notification.Name {
    static let watchRecordingAutoStopped = Notification.Name("watchRecordingAutoStopped")
}

enum WatchAudioRecorderError: Error, LocalizedError {
    case sessionError(Error)
    case invalidURL
    case recorderError(Error)
    case recordingFailed
    case encodingError(Error?)

    var errorDescription: String? {
        switch self {
        case .sessionError(let error):
            return "Audio session error: \(error.localizedDescription)"
        case .invalidURL:
            return "Could not create recording file"
        case .recorderError(let error):
            return "Recorder error: \(error.localizedDescription)"
        case .recordingFailed:
            return "Recording failed"
        case .encodingError(let error):
            return "Encoding error: \(error?.localizedDescription ?? "Unknown")"
        }
    }
}
