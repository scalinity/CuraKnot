import SwiftUI
import WatchKit
import OSLog

// MARK: - Handoff Capture View

private let logger = Logger(subsystem: "com.curaknot.app.watchos", category: "HandoffCaptureView")

struct HandoffCaptureView: View {
    @EnvironmentObject var dataManager: WatchDataManager
    @StateObject private var audioRecorder = WatchAudioRecorder()
    @Environment(\.dismiss) private var dismiss
    @State private var showingError = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            if audioRecorder.isRecording {
                RecordingView(
                    duration: audioRecorder.duration,
                    progress: audioRecorder.progress,
                    formattedDuration: audioRecorder.formattedDuration
                )
            } else {
                IdleView()
            }

            Spacer()

            // Action Buttons
            HStack(spacing: 20) {
                if audioRecorder.isRecording {
                    // Cancel Button
                    Button {
                        audioRecorder.cancelRecording()
                        WKInterfaceDevice.current().play(.failure)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("CancelRecordingButton")

                    // Stop Button
                    Button {
                        stopAndQueue()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.green, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("StopRecordingButton")
                } else {
                    // Start Recording Button
                    Button {
                        startRecording()
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 60, height: 60)
                            .background(Color.green, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("StartRecordingButton")
                }
            }

            // Hint Text
            Text(audioRecorder.isRecording ? "Tap stop when done" : "Tap to start recording")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("New Handoff")
        .alert("Recording Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(audioRecorder.error?.localizedDescription ?? "An error occurred")
        }
        .onChange(of: audioRecorder.error) { _, newError in
            showingError = newError != nil
        }
        // Handle auto-stop at max duration (DB1-Bug1)
        .onReceive(NotificationCenter.default.publisher(for: .watchRecordingAutoStopped)) { notification in
            guard let url = notification.userInfo?["url"] as? URL else {
                WKInterfaceDevice.current().play(.failure)
                return
            }
            transferAndDismiss(url: url)
        }
    }

    /// Transfer recording to iPhone and dismiss view
    private func transferAndDismiss(url: URL) {
        guard let patient = dataManager.currentPatient else {
            logger.warning("No patient selected")
            WKInterfaceDevice.current().play(.failure)
            return
        }

        let metadata = WatchDraftMetadata(
            patientId: patient.id,
            circleId: "", // Will be filled by iPhone
            createdAt: Date(),
            duration: audioRecorder.duration
        )

        WatchConnectivityHandler.shared.transferVoiceRecording(url: url, metadata: metadata)
        WKInterfaceDevice.current().play(.success)
        dismiss()
    }

    private func startRecording() {
        Task {
            do {
                try await audioRecorder.startRecording()
                WKInterfaceDevice.current().play(.start)
            } catch let recorderError as WatchAudioRecorderError {
                audioRecorder.error = recorderError
                WKInterfaceDevice.current().play(.failure)
            } catch {
                // Wrap unexpected errors instead of silently discarding (DB1-Bug3)
                audioRecorder.error = .sessionError(error)
                WKInterfaceDevice.current().play(.failure)
            }
        }
    }

    private func stopAndQueue() {
        guard let url = audioRecorder.stopRecording() else {
            WKInterfaceDevice.current().play(.failure)
            return
        }
        transferAndDismiss(url: url)
    }
}

// MARK: - Recording View

private struct RecordingView: View {
    let duration: TimeInterval
    let progress: Double
    let formattedDuration: String

    var body: some View {
        VStack(spacing: 12) {
            // Waveform animation
            Image(systemName: "waveform")
                .font(.system(size: 50))
                .foregroundStyle(.green)
                .symbolEffect(.variableColor.iterative)

            // Duration
            Text(formattedDuration)
                .font(.title2.monospacedDigit())

            // Progress Ring (shows approach to 60s limit)
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 4)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        progress > 0.8 ? Color.red : Color.green,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 60, height: 60)

            if progress > 0.8 {
                Text("Max 60 seconds")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Idle View

private struct IdleView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.circle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Voice Handoff")
                .font(.headline)

            Text("Record up to 60 seconds")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    HandoffCaptureView()
        .environmentObject(WatchDataManager.shared)
}
