import Foundation
import AVFoundation
import os

// MARK: - Audio Recorder

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    // MARK: - Published Properties
    
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevels: [Float] = []
    @Published var error: AudioRecorderError?
    
    // MARK: - Private Properties
    
    private var audioRecorder: AVAudioRecorder?
    private var audioSession: AVAudioSession { AVAudioSession.sharedInstance() }
    private var timer: Timer?
    private var levelTimer: Timer?
    private var recordingURL: URL?
    
    private let sampleRate: Double = 44100
    private let numberOfChannels: Int = 1
    private let bitRate: Int = 128000
    
    // MARK: - Recording Settings
    
    private var recordingSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: numberOfChannels,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: bitRate,
        ]
    }
    
    // MARK: - Public Methods
    
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            audioSession.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    func startRecording() async throws {
        // Check permission
        guard await requestPermission() else {
            throw AudioRecorderError.permissionDenied
        }
        
        // Configure audio session
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            throw AudioRecorderError.sessionError(error)
        }
        
        // Create recording URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let timestamp = Date().timeIntervalSince1970
        recordingURL = documentsPath.appendingPathComponent("recording_\(Int(timestamp)).m4a")
        
        guard let url = recordingURL else {
            throw AudioRecorderError.invalidURL
        }
        
        // Create recorder
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: recordingSettings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
        } catch {
            throw AudioRecorderError.recorderError(error)
        }
        
        // Start recording
        guard audioRecorder?.record() == true else {
            throw AudioRecorderError.recordingFailed
        }
        
        isRecording = true
        isPaused = false
        recordingDuration = 0
        audioLevels = []
        
        startTimers()
    }
    
    func pauseRecording() {
        audioRecorder?.pause()
        isPaused = true
        stopTimers()
    }
    
    func resumeRecording() {
        audioRecorder?.record()
        isPaused = false
        startTimers()
    }
    
    func stopRecording() -> URL? {
        stopTimers()
        audioRecorder?.stop()
        isRecording = false
        isPaused = false
        
        do {
            try audioSession.setActive(false)
        } catch {
            #if DEBUG
            Logger(subsystem: "com.curaknot.app", category: "AudioRecorder").warning("Failed to deactivate audio session: \(error.localizedDescription)")
            #endif
        }

        return recordingURL
    }

    func cancelRecording() {
        stopTimers()
        audioRecorder?.stop()
        isRecording = false
        isPaused = false

        // Delete recording file
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil

        do {
            try audioSession.setActive(false)
        } catch {
            #if DEBUG
            Logger(subsystem: "com.curaknot.app", category: "AudioRecorder").warning("Failed to deactivate audio session: \(error.localizedDescription)")
            #endif
        }
    }
    
    // MARK: - Private Methods
    
    private func startTimers() {
        // Duration timer
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordingDuration += 1
            }
        }
        
        // Level metering timer
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateAudioLevels()
            }
        }
    }
    
    private func stopTimers() {
        timer?.invalidate()
        timer = nil
        levelTimer?.invalidate()
        levelTimer = nil
    }
    
    private func updateAudioLevels() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        
        recorder.updateMeters()
        let level = recorder.averagePower(forChannel: 0)
        
        // Normalize level from dB to 0-1 range
        // Typical range is -160 to 0 dB
        let normalizedLevel = max(0, (level + 50) / 50)
        
        audioLevels.append(normalizedLevel)
        
        // Keep last 100 samples for visualization
        if audioLevels.count > 100 {
            audioLevels.removeFirst()
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag {
                error = .recordingFailed
            }
        }
    }
    
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.error = .encodingError(error)
        }
    }
}

// MARK: - Audio Recorder Error

enum AudioRecorderError: Error, LocalizedError {
    case permissionDenied
    case sessionError(Error)
    case invalidURL
    case recorderError(Error)
    case recordingFailed
    case encodingError(Error?)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access denied. Please enable in Settings."
        case .sessionError(let error):
            return "Audio session error: \(error.localizedDescription)"
        case .invalidURL:
            return "Could not create recording file"
        case .recorderError(let error):
            return "Recorder error: \(error.localizedDescription)"
        case .recordingFailed:
            return "Recording failed to start"
        case .encodingError(let error):
            return "Encoding error: \(error?.localizedDescription ?? "Unknown")"
        }
    }
}
