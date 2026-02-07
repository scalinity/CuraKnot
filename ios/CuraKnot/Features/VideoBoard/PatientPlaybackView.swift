import SwiftUI
import AVKit

// MARK: - Patient Playback View

/// Patient-friendly video playback interface with large touch targets (60pt)
/// Designed for elderly/cognitively impaired patients
struct PatientPlaybackView: View {
    let videos: [VideoMessageWithDetails]
    let patientName: String
    let videoService: VideoService
    let onDismiss: () -> Void
    
    @State private var currentIndex = 0
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var isMuted = true // Start muted
    @State private var isLoadingVideo = false
    @State private var showReactionAnimation = false
    @State private var playerEndObserver: NSObjectProtocol?
    @State private var loadVideoTask: Task<Void, Never>?
    
    // Minimum touch target size for accessibility
    private let touchTargetSize: CGFloat = 60
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black
                    .ignoresSafeArea()
                
                // Video player
                VStack(spacing: 0) {
                    // Top bar with close button
                    topBar
                    
                    // Video area
                    videoPlayerArea(geometry: geometry)
                    
                    // Caption area
                    captionArea
                    
                    // Controls
                    controlsArea
                }
                
                // Loading overlay
                if isLoadingVideo {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(2)
                }
                
                // Reaction animation
                if showReactionAnimation {
                    reactionAnimation
                }
            }
        }
        .task {
            await loadCurrentVideo()
        }
        .onDisappear {
            cleanupPlayer()
        }
    }
    
    // MARK: - Player Cleanup (prevents memory leaks and observer accumulation)
    
    private func cleanupPlayer() {
        // Cancel any pending load task
        loadVideoTask?.cancel()
        loadVideoTask = nil
        
        // Remove observer first
        if let observer = playerEndObserver {
            NotificationCenter.default.removeObserver(observer)
            playerEndObserver = nil
        }
        
        // Stop and release player
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        isPlaying = false
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            // Close button - large touch target
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(width: touchTargetSize, height: touchTargetSize)
            .accessibilityLabel("Close video player")
            .accessibilityHint("Double tap to close and return to previous screen")
            
            Spacer()
            
            // Patient greeting
            Text("Videos for \(patientName)")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            
            Spacer()
            
            // Video counter
            Text("\(currentIndex + 1) of \(videos.count)")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: touchTargetSize + 20)
                .accessibilityLabel("Video \(currentIndex + 1) of \(videos.count)")
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
    
    // MARK: - Video Player Area
    
    private func videoPlayerArea(geometry: GeometryProxy) -> some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(9/16, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .onTapGesture {
                        togglePlayback()
                    }
                    .accessibilityLabel("Video from \(currentVideo?.authorName ?? "Unknown")")
                    .accessibilityHint(isPlaying ? "Double tap to pause" : "Double tap to play")
                    .accessibilityAddTraits(.startsMediaSession)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(9/16, contentMode: .fit)
                    .overlay {
                        Image(systemName: "video.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.white.opacity(0.5))
                    }
            }
            
            // Play/Pause overlay indicator
            if !isPlaying && player != nil {
                SwiftUI.Circle()
                    .fill(.black.opacity(0.5))
                    .frame(width: 100, height: 100)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.white)
                    }
            }
            
            // Author badge
            VStack {
                HStack {
                    authorBadge
                    Spacer()
                }
                Spacer()
            }
            .padding(16)
        }
        .frame(maxHeight: geometry.size.height * 0.55)
        .padding(.horizontal, 20)
    }
    
    private var authorBadge: some View {
        HStack(spacing: 8) {
            Text(currentVideo?.authorInitials ?? "?")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.blue)
                .clipShape(SwiftUI.Circle())
            
            Text("From \(currentVideo?.authorName ?? "Unknown")")
                .font(.headline)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
    
    // MARK: - Caption Area
    
    private var captionArea: some View {
        Group {
            if let caption = currentVideo?.video.caption, !caption.isEmpty {
                Text(caption)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
        }
    }
    
    // MARK: - Controls Area
    
    private var controlsArea: some View {
        HStack(spacing: 30) {
            // Previous button
            largeButton(
                icon: "backward.fill",
                label: "Previous",
                disabled: currentIndex == 0
            ) {
                goToPrevious()
            }
            
            // Play/Pause button
            largeButton(
                icon: isPlaying ? "pause.fill" : "play.fill",
                label: isPlaying ? "Pause" : "Play",
                isPrimary: true
            ) {
                togglePlayback()
            }
            
            // Sound button
            largeButton(
                icon: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                label: isMuted ? "Unmute" : "Mute"
            ) {
                toggleSound()
            }
            
            // Next button
            largeButton(
                icon: "forward.fill",
                label: "Next",
                disabled: currentIndex >= videos.count - 1
            ) {
                goToNext()
            }
            
            // Love button
            loveButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 30)
    }
    
    // MARK: - Large Button Helper
    
    @ViewBuilder
    private func largeButton(
        icon: String,
        label: String,
        isPrimary: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: isPrimary ? 36 : 28))
                    .foregroundStyle(disabled ? .white.opacity(0.3) : .white)
                
                Text(label)
                    .font(.caption)
                    .foregroundStyle(disabled ? .white.opacity(0.3) : .white.opacity(0.7))
            }
            .frame(width: touchTargetSize, height: touchTargetSize + 20)
            .background(
                isPrimary ?
                    Color.blue.opacity(disabled ? 0.3 : 1) :
                    Color.white.opacity(disabled ? 0.05 : 0.15)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(disabled)
        .accessibilityLabel(label)
        .accessibilityHint(disabled ? "Button disabled" : "Double tap to \(label.lowercased())")
        .accessibilityAddTraits(disabled ? .isStaticText : [])
    }
    
    // MARK: - Love Button
    
    private var loveButton: some View {
        let hasReacted = currentVideo?.hasUserReacted ?? false
        
        return Button {
            sendLove()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: hasReacted ? "heart.fill" : "heart")
                    .font(.system(size: 28))
                    .foregroundStyle(hasReacted ? .red : .white)
                
                Text("Love")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(width: touchTargetSize, height: touchTargetSize + 20)
            .background(hasReacted ? Color.red.opacity(0.3) : Color.white.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel(hasReacted ? "Remove love reaction" : "Send love reaction")
        .accessibilityHint(hasReacted ? "Double tap to remove your love reaction" : "Double tap to send a love reaction to this video")
        .accessibilityAddTraits(.isButton)
    }
    
    // MARK: - Reaction Animation
    
    private var reactionAnimation: some View {
        VStack {
            Spacer()
            Image(systemName: "heart.fill")
                .font(.system(size: 100))
                .foregroundStyle(.red)
                .shadow(color: .red.opacity(0.5), radius: 20)
            Spacer()
        }
        .transition(.scale.combined(with: .opacity))
    }
    
    // MARK: - Current Video
    
    private var currentVideo: VideoMessageWithDetails? {
        guard currentIndex < videos.count else { return nil }
        return videos[currentIndex]
    }
    
    // MARK: - Actions
    
    private func loadCurrentVideo() async {
        guard let video = currentVideo else { return }
        
        // Cancel any previous load task to prevent race conditions
        loadVideoTask?.cancel()
        
        // Clean up previous player before loading new one
        cleanupPlayer()
        
        isLoadingVideo = true
        
        // Create a new task for loading
        loadVideoTask = Task {
            do {
                let url = try await videoService.getVideoURL(storageKey: video.video.storageKey)
                
                // Check if cancelled before updating UI
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    
                    let newPlayer = AVPlayer(url: url)
                    newPlayer.isMuted = isMuted
                    
                    // Setup loop observer for the new player's item
                    playerEndObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: newPlayer.currentItem,
                        queue: .main
                    ) { [weak newPlayer] _ in
                        newPlayer?.seek(to: .zero)
                        newPlayer?.play()
                    }
                    
                    player = newPlayer
                    newPlayer.play()
                    isPlaying = true
                    isLoadingVideo = false
                }
                
                // Record view (fire and forget, don't block UI)
                Task {
                    try? await videoService.recordView(videoId: video.video.id)
                }
                
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isLoadingVideo = false
                }
                #if DEBUG
                print("Failed to load video: \(error)")
                #endif
            }
        }
        
        await loadVideoTask?.value
    }
    
    private func togglePlayback() {
        guard let player else { return }
        
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }
    
    private func toggleSound() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }
    
    private func goToPrevious() {
        guard currentIndex > 0, !isLoadingVideo else { return }
        currentIndex -= 1
        Task {
            await loadCurrentVideo()
        }
    }
    
    private func goToNext() {
        guard currentIndex < videos.count - 1, !isLoadingVideo else { return }
        currentIndex += 1
        Task {
            await loadCurrentVideo()
        }
    }
    
    private func sendLove() {
        guard let video = currentVideo else { return }
        
        // Show animation
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            showReactionAnimation = true
        }
        
        // Hide after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                showReactionAnimation = false
            }
        }
        
        // Toggle reaction
        Task {
            try? await videoService.toggleReaction(videoId: video.video.id)
        }
    }
}

// Preview disabled - requires DependencyContainer.preview which is not yet implemented
// To preview, use the app with DependencyContainer
