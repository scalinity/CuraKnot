import SwiftUI

// MARK: - New Handoff View

struct NewHandoffView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var mode: CaptureMode = .voice
    @State private var selectedPatient: Patient?
    @State private var selectedType: Handoff.HandoffType = .visit
    
    enum CaptureMode {
        case voice
        case text
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Patient and Type Selection
                VStack(spacing: 16) {
                    // Patient Picker
                    Menu {
                        ForEach(appState.patients) { patient in
                            Button {
                                selectedPatient = patient
                            } label: {
                                HStack {
                                    Text(patient.displayName)
                                    if patient.id == selectedPatient?.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(selectedPatient?.displayInitials ?? "?")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.accentColor, in: SwiftUI.Circle())
                            
                            VStack(alignment: .leading) {
                                Text(selectedPatient?.displayName ?? "Select Patient")
                                    .font(.headline)
                                Text("Tap to change")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    
                    // Type Picker
                    Picker("Type", selection: $selectedType) {
                        ForEach(Handoff.HandoffType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding()
                
                Divider()
                
                // Mode Picker
                Picker("Capture Mode", selection: $mode) {
                    Label("Voice", systemImage: "waveform")
                        .tag(CaptureMode.voice)
                    Label("Text", systemImage: "keyboard")
                        .tag(CaptureMode.text)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Capture Area
                Group {
                    switch mode {
                    case .voice:
                        AudioRecorderView(
                            patient: selectedPatient,
                            handoffType: selectedType
                        )
                    case .text:
                        TextHandoffView(
                            patient: selectedPatient,
                            handoffType: selectedType
                        )
                    }
                }
            }
            .navigationTitle("New Handoff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // Default to first patient
            if selectedPatient == nil {
                selectedPatient = appState.patients.first
            }
        }
    }
}

// MARK: - Audio Recorder View

struct AudioRecorderView: View {
    let patient: Patient?
    let handoffType: Handoff.HandoffType
    
    @StateObject private var recorder = AudioRecorder()
    @State private var showDraftReview = false
    @State private var recordingURL: URL?
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Real-time Waveform
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
                .frame(height: 100)
                .overlay {
                    if recorder.isRecording {
                        AudioWaveformView(levels: recorder.audioLevels)
                    } else if recordingURL != nil {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Recording complete")
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Tap to start recording")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
            
            // Duration
            Text(formatDuration(recorder.recordingDuration))
                .font(.system(size: 48, weight: .light, design: .monospaced))
            
            // Record Button
            Button {
                Task {
                    await toggleRecording()
                }
            } label: {
                ZStack {
                    SwiftUI.Circle()
                        .fill(recorder.isRecording ? Color.red : Color.accentColor)
                        .frame(width: 80, height: 80)
                    
                    if recorder.isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white)
                            .frame(width: 24, height: 24)
                    } else {
                        SwiftUI.Circle()
                            .fill(.white)
                            .frame(width: 24, height: 24)
                    }
                }
            }
            .sensoryFeedback(.impact, trigger: recorder.isRecording)
            
            Text(recorder.isRecording ? "Tap to stop" : "Tap to record")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // Tips or Continue button
            if let _ = recordingURL, !recorder.isRecording {
                Button {
                    showDraftReview = true
                } label: {
                    Text("Continue to Review")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            } else if !recorder.isRecording {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tips for a good handoff:")
                        .font(.headline)
                    Text("• Describe what happened and when")
                    Text("• Note any changes to medications or care")
                    Text("• Mention follow-up actions needed")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .padding()
            }
        }
        .alert("Recording Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .fullScreenCover(isPresented: $showDraftReview) {
            if let url = recordingURL {
                ProcessingView(
                    audioURL: url,
                    patient: patient,
                    handoffType: handoffType
                )
            }
        }
    }
    
    private func toggleRecording() async {
        if recorder.isRecording {
            // Stop recording
            recordingURL = recorder.stopRecording()
        } else {
            // Start recording
            do {
                try await recorder.startRecording()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Audio Waveform View

struct AudioWaveformView: View {
    let levels: [Float]
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(displayLevels(for: geometry.size.width), id: \.offset) { item in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: 3, height: barHeight(for: item.element, maxHeight: geometry.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 8)
    }
    
    private func displayLevels(for width: CGFloat) -> [(offset: Int, element: Float)] {
        let barCount = Int(width / 5) // 3pt bar + 2pt spacing
        let recentLevels = Array(levels.suffix(barCount))
        
        // Pad with zeros if not enough levels yet
        let paddedLevels: [Float]
        if recentLevels.count < barCount {
            paddedLevels = Array(repeating: Float(0), count: barCount - recentLevels.count) + recentLevels
        } else {
            paddedLevels = recentLevels
        }
        
        return Array(paddedLevels.enumerated())
    }
    
    private func barHeight(for level: Float, maxHeight: CGFloat) -> CGFloat {
        let minHeight: CGFloat = 4
        let availableHeight = maxHeight - 16 // padding
        // Level is already normalized 0-1 by AudioRecorder
        let normalizedLevel = CGFloat(max(0, min(1, level)))
        return minHeight + availableHeight * normalizedLevel
    }
}

// MARK: - Processing View

struct ProcessingView: View {
    @Environment(\.dismiss) private var dismiss
    
    let audioURL: URL
    let patient: Patient?
    let handoffType: Handoff.HandoffType
    
    @State private var isProcessing = true
    @State private var draft: StructuredBrief?
    @State private var error: Error?
    
    var body: some View {
        NavigationStack {
            Group {
                if isProcessing {
                    VStack(spacing: 24) {
                        ProgressView()
                            .scaleEffect(1.5)
                        
                        Text("Processing your recording...")
                            .font(.headline)
                        
                        Text("Transcribing and extracting key information")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let draft = draft {
                    DraftReviewView(handoffId: draft.handoffId, draft: draft)
                } else if let error = error {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)
                        
                        Text("Processing Failed")
                            .font(.headline)
                        
                        Text(error.localizedDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button("Try Again") {
                            Task {
                                await processRecording()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
            .navigationTitle("Processing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await processRecording()
        }
    }
    
    private func processRecording() async {
        isProcessing = true
        error = nil
        
        // TODO: Actually upload and process via Supabase edge function
        // For now, create a mock draft after a delay
        try? await Task.sleep(for: .seconds(2))
        
        // Create mock draft for testing
        let handoffId = UUID().uuidString
        draft = StructuredBrief(
            handoffId: handoffId,
            circleId: patient?.circleId ?? UUID().uuidString,
            patientId: patient?.id ?? UUID().uuidString,
            createdBy: UUID().uuidString, // Would be current user
            createdAt: Date(),
            type: handoffType,
            title: "\(handoffType.displayName) - \(Date().formatted(date: .abbreviated, time: .shortened))",
            summary: "Recording processed. Edit this summary to describe what happened during the \(handoffType.displayName.lowercased()).",
            status: StructuredBrief.BriefStatus(
                moodEnergy: "Good",
                pain: nil,
                appetite: nil,
                sleep: nil,
                mobility: nil
            ),
            changes: nil,
            questionsForClinician: nil,
            nextSteps: nil,
            attachments: nil,
            keywords: nil,
            confidence: nil,
            revision: 1
        )
        
        isProcessing = false
    }
}

// MARK: - Text Handoff View

struct TextHandoffView: View {
    let patient: Patient?
    let handoffType: Handoff.HandoffType
    
    @State private var text = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            TextEditor(text: $text)
                .focused($isFocused)
                .frame(maxHeight: .infinity)
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .padding()
            
            // Character count
            HStack {
                Spacer()
                Text("\(text.count) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            
            // Continue button
            Button {
                // TODO: Navigate to draft review
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        text.isEmpty ? Color.gray : Color.accentColor,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
            }
            .disabled(text.isEmpty)
            .padding()
        }
        .onAppear {
            isFocused = true
        }
    }
}

#Preview {
    NewHandoffView()
        .environmentObject(AppState())
}
