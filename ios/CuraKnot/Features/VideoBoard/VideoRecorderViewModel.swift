import Foundation
@preconcurrency import AVFoundation
import Combine
import os

// MARK: - Video Recorder ViewModel

@MainActor
final class VideoRecorderViewModel: NSObject, ObservableObject {

    // MARK: - Types

    enum RecordingState: Equatable {
        case idle
        case preparing
        case recording
        case stopping
        case stopped(URL)
        case failed(Error)
        
        static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.preparing, .preparing), (.recording, .recording), (.stopping, .stopping):
                return true
            case (.stopped(let lhsURL), .stopped(let rhsURL)):
                return lhsURL == rhsURL
            case (.failed, .failed):
                return true
            default:
                return false
            }
        }
    }

    enum CameraPosition {
        case front
        case back

        var avPosition: AVCaptureDevice.Position {
            switch self {
            case .front: return .front
            case .back: return .back
            }
        }
    }

    enum RecorderError: LocalizedError {
        case cameraAccessDenied
        case microphoneAccessDenied
        case cameraUnavailable
        case setupFailed(Error)
        case recordingFailed(Error)

        var errorDescription: String? {
            switch self {
            case .cameraAccessDenied:
                return "Camera access required. Please enable in Settings > CuraKnot > Camera."
            case .microphoneAccessDenied:
                return "Microphone access required. Please enable in Settings > CuraKnot > Microphone."
            case .cameraUnavailable:
                return "Camera unavailable. Please try again later."
            case .setupFailed(let error):
                return "Camera setup failed: \(error.localizedDescription)"
            case .recordingFailed(let error):
                return "Recording failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Published Properties

    @Published var recordingState: RecordingState = .idle
    @Published var recordingDuration: TimeInterval = 0
    @Published var currentCamera: CameraPosition = .front
    @Published var isPreviewReady = false

    // MARK: - Properties
    
    // Use nonisolated(unsafe) for AVCaptureSession since it's internally thread-safe
    // and we need to access it from both main actor and session queue
    nonisolated(unsafe) let captureSession = AVCaptureSession()
    let maxDuration: TimeInterval

    private var movieOutput: AVCaptureMovieFileOutput?
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var recordingTimer: Timer?
    private var outputURL: URL?
    private var isCancelled = false

    nonisolated(unsafe) private let sessionQueue = DispatchQueue(label: "com.curaknot.videocapture")

    // MARK: - Initialization

    init(maxDuration: TimeInterval) {
        self.maxDuration = maxDuration
        super.init()
    }

    deinit {
        recordingTimer?.invalidate()
        let session = captureSession
        let queue = sessionQueue
        queue.async {
            session.stopRunning()
        }
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        // Check camera permission
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                recordingState = .failed(RecorderError.cameraAccessDenied)
                return false
            }
        } else if cameraStatus != .authorized {
            recordingState = .failed(RecorderError.cameraAccessDenied)
            return false
        }

        // Check microphone permission
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                recordingState = .failed(RecorderError.microphoneAccessDenied)
                return false
            }
        } else if micStatus != .authorized {
            recordingState = .failed(RecorderError.microphoneAccessDenied)
            return false
        }

        return true
    }

    // MARK: - Session Setup

    func setupSession() async throws {
        recordingState = .preparing

        // Request permissions first
        guard await requestPermissions() else {
            return
        }

        // Setup on session queue
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: RecorderError.setupFailed(NSError(domain: "VideoRecorder", code: -1)))
                    return
                }

                do {
                    self.captureSession.beginConfiguration()
                    self.captureSession.sessionPreset = .high

                    // Add video input
                    try self.addVideoInput(position: self.currentCamera.avPosition)

                    // Add audio input
                    try self.addAudioInput()

                    // Add movie output
                    let movieOutput = AVCaptureMovieFileOutput()
                    if self.captureSession.canAddOutput(movieOutput) {
                        self.captureSession.addOutput(movieOutput)
                        self.movieOutput = movieOutput

                        // Configure video connection
                        if let connection = movieOutput.connection(with: .video) {
                            if connection.isVideoStabilizationSupported {
                                connection.preferredVideoStabilizationMode = .auto
                            }
                        }
                    }

                    self.captureSession.commitConfiguration()

                    // Start session
                    self.captureSession.startRunning()

                    DispatchQueue.main.async {
                        self.recordingState = .idle
                        self.isPreviewReady = true
                    }

                    continuation.resume()

                } catch {
                    self.captureSession.commitConfiguration()
                    DispatchQueue.main.async {
                        self.recordingState = .failed(RecorderError.setupFailed(error))
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func addVideoInput(position: AVCaptureDevice.Position) throws {
        // Remove existing video input
        if let existingInput = videoDeviceInput {
            captureSession.removeInput(existingInput)
        }

        // Find video device
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw RecorderError.cameraUnavailable
        }

        let videoInput = try AVCaptureDeviceInput(device: videoDevice)

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
            videoDeviceInput = videoInput
        } else {
            throw RecorderError.cameraUnavailable
        }
    }

    private func addAudioInput() throws {
        // Remove existing audio input
        if let existingInput = audioDeviceInput {
            captureSession.removeInput(existingInput)
        }

        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            throw RecorderError.microphoneAccessDenied
        }

        let audioInput = try AVCaptureDeviceInput(device: audioDevice)

        if captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
            audioDeviceInput = audioInput
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard case .idle = recordingState else { return }
        guard let movieOutput = movieOutput else { return }

        isCancelled = false

        // Create output URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let timestamp = Int(Date().timeIntervalSince1970)
        let url = documentsPath.appendingPathComponent("video_\(timestamp).mp4")
        outputURL = url

        // Start recording - capture self strongly since we're the delegate
        // and need to exist for the callback
        sessionQueue.async { [self] in
            movieOutput.startRecording(to: url, recordingDelegate: self)
        }

        recordingState = .recording
        recordingDuration = 0

        // Start timer
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.recordingDuration += 0.1

                // Auto-stop at max duration
                if self.recordingDuration >= self.maxDuration {
                    self.stopRecording()
                }
            }
        }
    }

    func stopRecording() {
        guard case .recording = recordingState else { return }

        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingState = .stopping

        sessionQueue.async { [weak self] in
            self?.movieOutput?.stopRecording()
        }
    }

    func cancelRecording() {
        isCancelled = true
        recordingTimer?.invalidate()
        recordingTimer = nil

        let urlToDelete = outputURL

        if case .recording = recordingState {
            // Stop recording - delegate callback will check isCancelled and clean up
            recordingState = .idle
            sessionQueue.async { [weak self] in
                self?.movieOutput?.stopRecording()
                // Delete file after recording stops (on session queue to avoid race)
                if let url = urlToDelete {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        } else {
            // Not recording - safe to delete immediately
            if let url = urlToDelete {
                try? FileManager.default.removeItem(at: url)
            }
        }

        recordingDuration = 0
        outputURL = nil
    }

    // MARK: - Camera Control

    func flipCamera() {
        guard case .idle = recordingState else { return }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            self.captureSession.beginConfiguration()

            let newPosition: CameraPosition = self.currentCamera == .front ? .back : .front

            do {
                try self.addVideoInput(position: newPosition.avPosition)
                DispatchQueue.main.async {
                    self.currentCamera = newPosition
                }
            } catch {
                // Revert on failure
                Logger(subsystem: "com.curaknot.app", category: "VideoRecorder").error("Failed to flip camera: \(error.localizedDescription)")
            }

            self.captureSession.commitConfiguration()
        }
    }

    // MARK: - Session Control

    func stopSession() {
        recordingTimer?.invalidate()
        recordingTimer = nil

        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }

    // MARK: - Helpers

    var durationFormatted: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        let tenths = Int((recordingDuration * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }

    var remainingDuration: TimeInterval {
        max(0, maxDuration - recordingDuration)
    }

    var progress: Double {
        recordingDuration / maxDuration
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension VideoRecorderViewModel: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in
            // If recording was cancelled, don't transition to .stopped state
            guard !self.isCancelled else {
                return
            }

            if let error = error {
                // Check if it's just the user stopping (not a real error)
                let nsError = error as NSError
                if nsError.domain == AVFoundationErrorDomain && nsError.code == -11818 {
                    // Recording was stopped, this is normal
                    self.recordingState = .stopped(outputFileURL)
                } else {
                    self.recordingState = .failed(RecorderError.recordingFailed(error))
                }
            } else {
                self.recordingState = .stopped(outputFileURL)
            }
        }
    }
}
