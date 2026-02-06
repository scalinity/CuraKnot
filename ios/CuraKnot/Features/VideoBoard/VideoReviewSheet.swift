import SwiftUI
import AVKit

// MARK: - Video Review Sheet

struct VideoReviewSheet: View {
    let videoURL: URL
    let circleId: String
    let patientId: String
    let onUploadComplete: () -> Void
    let onCancel: () -> Void
    
    @EnvironmentObject private var container: DependencyContainer
    @State private var player: AVPlayer?
    @State private var caption = ""
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0
    @State private var uploadPhase: UploadPhase = .idle
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var playerEndObserver: NSObjectProtocol?
    
    enum UploadPhase: Equatable {
        case idle
        case compressing
        case uploading
        case processing
        case complete
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Video preview
                videoPreview
                
                // Caption input
                captionInput
                
                // Upload progress or button
                if isUploading {
                    uploadProgressView
                } else {
                    uploadButton
                }
            }
            .navigationTitle("Review Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cleanup()
                        onCancel()
                    }
                    .disabled(isUploading)
                }
            }
            .alert("Upload Failed", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            if let observer = playerEndObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            playerEndObserver = nil
        }
    }
    
    // MARK: - Video Preview
    
    private var videoPreview: some View {
        GeometryReader { geometry in
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(9/16, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: geometry.size.height)
                    .background(Color.black)
                    .accessibilityLabel("Video preview")
                    .accessibilityHint("Your recorded video is playing. Review before sending.")
            } else {
                Rectangle()
                    .fill(Color.black)
                    .overlay {
                        ProgressView()
                            .tint(.white)
                    }
                    .accessibilityLabel("Loading video preview")
            }
        }
        .frame(maxHeight: 400)
    }
    
    // MARK: - Caption Input
    
    private var captionInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add a caption (optional)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            TextField("Say something to your loved one...", text: $caption, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...5)
                .disabled(isUploading)
                .accessibilityLabel("Caption")
                .accessibilityHint("Enter an optional message to accompany your video")
        }
        .padding()
    }
    
    // MARK: - Upload Progress
    
    private var uploadProgressView: some View {
        VStack(spacing: 16) {
            ProgressView(value: uploadProgress)
                .progressViewStyle(.linear)
                .accessibilityLabel("Upload progress: \(Int(uploadProgress * 100)) percent")
            
            HStack {
                phaseIcon
                
                Text(phaseText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(phaseText)
        }
        .padding()
        .padding(.bottom, 20)
    }
    
    @ViewBuilder
    private var phaseIcon: some View {
        switch uploadPhase {
        case .idle:
            EmptyView()
        case .compressing:
            Image(systemName: "film")
                .foregroundStyle(.blue)
        case .uploading:
            Image(systemName: "arrow.up.circle")
                .foregroundStyle(.blue)
        case .processing:
            Image(systemName: "gearshape.2")
                .foregroundStyle(.blue)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
    
    private var phaseText: String {
        switch uploadPhase {
        case .idle:
            return ""
        case .compressing:
            return "Compressing video..."
        case .uploading:
            return "Uploading..."
        case .processing:
            return "Processing..."
        case .complete:
            return "Complete!"
        }
    }
    
    // MARK: - Upload Button
    
    private var uploadButton: some View {
        Button {
            Task {
                await uploadVideo()
            }
        } label: {
            Label("Send Video", systemImage: "paperplane.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .buttonStyle(.borderedProminent)
        .padding()
        .padding(.bottom, 20)
        .accessibilityLabel("Send video")
        .accessibilityHint("Double tap to upload and send your video message")
    }
    
    // MARK: - Actions
    
    private func setupPlayer() {
        // Verify file exists before attempting to play
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            errorMessage = "Video file not found"
            showError = true
            return
        }
        
        // Remove previous observer if exists
        if let observer = playerEndObserver {
            NotificationCenter.default.removeObserver(observer)
            playerEndObserver = nil
        }
        
        player?.pause()
        player = AVPlayer(url: videoURL)
        player?.isMuted = false
        
        // Store observer reference for cleanup
        playerEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
        
        player?.play()
    }
    
    private func uploadVideo() async {
        isUploading = true
        uploadProgress = 0
        uploadPhase = .compressing
        
        do {
            // Get subscription options
            let options = VideoCompressionService.CompressionOptions.forPlan(
                container.subscriptionManager.currentPlan
            )
            
            // Compress video
            let compressionResult = try await container.videoCompressionService.compress(
                sourceURL: videoURL,
                options: options
            )
            
            // Upload phase
            uploadPhase = .uploading
            uploadProgress = 0.4
            
            // Upload video (progress tracking disabled due to struct limitations)
            let videoMessage = try await container.videoService.uploadVideo(
                url: compressionResult.url,
                circleId: circleId,
                patientId: patientId,
                caption: caption.isEmpty ? nil : caption,
                durationSeconds: compressionResult.durationSeconds,
                progressHandler: { _ in }
            )
            
            // Processing phase (server-side thumbnail generation)
            uploadPhase = .processing
            uploadProgress = 0.9
            
            // Wait a moment for processing indication
            try await Task.sleep(nanoseconds: 500_000_000)
            
            uploadPhase = .complete
            uploadProgress = 1.0
            
            // Clean up local files
            cleanup()
            try? FileManager.default.removeItem(at: compressionResult.url)
            
            // Notify completion
            try await Task.sleep(nanoseconds: 300_000_000)
            onUploadComplete()
            
        } catch {
            isUploading = false
            uploadPhase = .idle
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func cleanup() {
        // Properly release AVPlayer resources to prevent memory leak
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        
        // Clean up original recording
        try? FileManager.default.removeItem(at: videoURL)
    }
}

// MARK: - Preview

#Preview {
    VideoReviewSheet(
        videoURL: URL(fileURLWithPath: "/tmp/test.mp4"),
        circleId: "test-circle",
        patientId: "test-patient",
        onUploadComplete: { },
        onCancel: { }
    )
}
