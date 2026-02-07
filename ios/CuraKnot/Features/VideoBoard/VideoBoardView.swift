import SwiftUI
import AVKit

// MARK: - Video Board View

struct VideoBoardView: View {
    let circleId: String
    let patientId: String
    let patientName: String
    
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var viewModel: VideoBoardViewModel
    
    @State private var showRecorder = false
    @State private var showReviewSheet = false
    @State private var recordedVideoURL: URL?
    @State private var selectedVideo: VideoMessageWithDetails?
    @State private var showPatientPlayback = false
    
    init(circleId: String, patientId: String, patientName: String) {
        self.circleId = circleId
        self.patientId = patientId
        self.patientName = patientName
        _viewModel = StateObject(wrappedValue: VideoBoardViewModel())
    }
    
    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.videos.isEmpty {
                loadingView
            } else if let error = viewModel.error {
                errorView(error)
            } else if !viewModel.hasFeatureAccess {
                featureLockedView
            } else if viewModel.videos.isEmpty {
                emptyStateView
            } else {
                videoGrid
            }
        }
        .navigationTitle("Video Messages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if viewModel.hasFeatureAccess {
                    recordButton
                }
            }
            
            ToolbarItem(placement: .topBarLeading) {
                patientPlaybackButton
            }
        }
        .task {
            viewModel.configure(
                videoService: container.videoService,
                subscriptionManager: container.subscriptionManager,
                circleId: circleId,
                patientId: patientId
            )
            await viewModel.loadVideos()
        }
        .refreshable {
            await viewModel.loadVideos(forceSync: true)
        }
        .fullScreenCover(isPresented: $showRecorder) {
            VideoRecorderView(
                maxDuration: viewModel.maxDuration,
                onRecordingComplete: { url in
                    recordedVideoURL = url
                    showRecorder = false
                    showReviewSheet = true
                },
                onCancel: {
                    showRecorder = false
                }
            )
        }
        .sheet(isPresented: $showReviewSheet) {
            if let url = recordedVideoURL {
                VideoReviewSheet(
                    videoURL: url,
                    circleId: circleId,
                    patientId: patientId,
                    onUploadComplete: {
                        showReviewSheet = false
                        recordedVideoURL = nil
                        Task {
                            await viewModel.loadVideos(forceSync: true)
                        }
                    },
                    onCancel: {
                        showReviewSheet = false
                        recordedVideoURL = nil
                    }
                )
                .environmentObject(container)
            }
        }
        .sheet(item: $selectedVideo) { video in
            VideoDetailSheet(
                video: video,
                videoService: container.videoService,
                onDismiss: {
                    selectedVideo = nil
                    Task {
                        await viewModel.loadVideos()
                    }
                }
            )
        }
        .fullScreenCover(isPresented: $showPatientPlayback) {
            PatientPlaybackView(
                videos: viewModel.videos,
                patientName: patientName,
                videoService: container.videoService,
                onDismiss: {
                    showPatientPlayback = false
                }
            )
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading videos...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Error View
    
    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView {
            Label("Error Loading Videos", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Try Again") {
                Task {
                    await viewModel.loadVideos(forceSync: true)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - Feature Locked View
    
    private var featureLockedView: some View {
        ContentUnavailableView {
            Label("Video Messages", systemImage: "video.fill")
        } description: {
            Text("Send heartfelt video messages to \(patientName). Upgrade to Plus or Family to unlock this feature.")
        } actions: {
            Button("View Plans") {
                // Navigate to subscription settings
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Videos Yet", systemImage: "video.badge.plus")
        } description: {
            Text("Be the first to send a video message to \(patientName). Tap the camera button to record.")
        } actions: {
            Button {
                showRecorder = true
            } label: {
                Label("Record Video", systemImage: "video.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - Video Grid
    
    private var videoGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(viewModel.videos, id: \.video.id) { videoWithDetails in
                    VideoThumbnailCard(
                        video: videoWithDetails,
                        videoService: container.videoService
                    )
                    .onTapGesture {
                        selectedVideo = videoWithDetails
                    }
                    .accessibilityLabel("Video from \(videoWithDetails.authorName)")
                    .accessibilityHint("Double tap to view video")
                    .accessibilityAddTraits(.isButton)
                }
            }
            .padding()
            
            // Quota indicator
            if let quota = viewModel.quotaStatus {
                quotaIndicator(quota)
            }
        }
    }
    
    // MARK: - Quota Indicator
    
    private func quotaIndicator(_ quota: VideoService.VideoQuotaStatus) -> some View {
        VStack(spacing: 8) {
            ProgressView(value: quota.usagePercent / 100)
                .tint(quota.usagePercent > 80 ? .orange : .blue)
            
            Text(String(format: "%.0f MB / %.0f MB used", quota.usedMB, quota.limitMB))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Storage usage: \(Int(quota.usedMB)) megabytes of \(Int(quota.limitMB)) megabytes used, \(Int(quota.usagePercent)) percent")
    }
    
    // MARK: - Toolbar Buttons
    
    private var recordButton: some View {
        Button {
            showRecorder = true
        } label: {
            Image(systemName: "video.fill.badge.plus")
        }
        .disabled(!viewModel.canUpload)
        .accessibilityLabel("Record new video")
        .accessibilityHint(viewModel.canUpload ? "Double tap to record a video message" : "Video recording unavailable, quota exceeded")
    }
    
    private var patientPlaybackButton: some View {
        Button {
            showPatientPlayback = true
        } label: {
            Image(systemName: "play.circle")
        }
        .disabled(viewModel.videos.isEmpty)
        .accessibilityLabel("Patient playback mode")
        .accessibilityHint(viewModel.videos.isEmpty ? "No videos available for playback" : "Double tap to start patient-friendly playback mode")
    }
}

// MARK: - Video Board ViewModel

@MainActor
final class VideoBoardViewModel: ObservableObject {
    @Published var videos: [VideoMessageWithDetails] = []
    @Published var quotaStatus: VideoService.VideoQuotaStatus?
    @Published var isLoading = false
    @Published var error: Error?
    @Published var hasFeatureAccess = false
    
    private var videoService: VideoService?
    private var subscriptionManager: SubscriptionManager?
    private var circleId: String?
    private var patientId: String?
    
    var maxDuration: TimeInterval {
        TimeInterval(quotaStatus?.maxDuration ?? 30)
    }
    
    var canUpload: Bool {
        quotaStatus?.allowed == true
    }
    
    func configure(
        videoService: VideoService,
        subscriptionManager: SubscriptionManager,
        circleId: String,
        patientId: String
    ) {
        self.videoService = videoService
        self.subscriptionManager = subscriptionManager
        self.circleId = circleId
        self.patientId = patientId
        self.hasFeatureAccess = videoService.hasFeatureAccess()
    }
    
    func loadVideos(forceSync: Bool = false) async {
        guard let videoService, let circleId, let patientId else { return }
        
        isLoading = true
        error = nil
        
        do {
            // Check quota
            quotaStatus = try await videoService.checkQuota(circleId: circleId)
            
            // Sync from server if needed
            if forceSync {
                try await videoService.syncVideos(circleId: circleId)
            }
            
            // Load from local database
            videos = try await videoService.fetchVideosWithDetails(
                patientId: patientId,
                circleId: circleId
            )
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
}

// MARK: - Video Thumbnail Card

struct VideoThumbnailCard: View {
    let video: VideoMessageWithDetails
    let videoService: VideoService
    
    @State private var thumbnailURL: URL?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                if let thumbnailURL {
                    AsyncImage(url: thumbnailURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(16/9, contentMode: .fill)
                        case .failure:
                            thumbnailPlaceholder
                        case .empty:
                            thumbnailPlaceholder
                                .overlay {
                                    ProgressView()
                                        .tint(.white)
                                }
                        @unknown default:
                            thumbnailPlaceholder
                        }
                    }
                } else {
                    thumbnailPlaceholder
                }
                
                // Duration badge
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(video.video.durationFormatted)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.7))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(6)
                    }
                }
                
                // Play icon
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 4)
            }
            .aspectRatio(16/9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    // Author initials
                    Text(video.authorInitials)
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(width: 24, height: 24)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(SwiftUI.Circle())
                    
                    Text(video.authorName)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Reaction count
                    if video.reactionCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                            Text("\(video.reactionCount)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Text(video.video.relativeTimeAgo)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                if let caption = video.video.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .task {
            if let key = video.video.thumbnailKey {
                thumbnailURL = try? await videoService.getThumbnailURL(thumbnailKey: key)
            }
        }
    }
    
    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .overlay {
                Image(systemName: "video.fill")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
    }
}

// MARK: - Video Detail Sheet

struct VideoDetailSheet: View {
    let video: VideoMessageWithDetails
    let videoService: VideoService
    let onDismiss: () -> Void
    
    @State private var player: AVPlayer?
    @State private var videoURL: URL?
    @State private var isLoadingVideo = true
    @State private var showDeleteConfirmation = false
    @State private var showFlagConfirmation = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Video player
                Group {
                    if let player {
                        VideoPlayer(player: player)
                    } else {
                        Rectangle()
                            .fill(.black)
                            .overlay {
                                if isLoadingVideo {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.largeTitle)
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                }
                .aspectRatio(9/16, contentMode: .fit)
                .frame(maxHeight: 400)
                
                // Info section
                List {
                    Section {
                        LabeledContent("From", value: video.authorName)
                        LabeledContent("Duration", value: video.video.durationFormatted)
                        LabeledContent("Sent", value: video.video.relativeTimeAgo)
                        
                        if video.video.saveForever {
                            LabeledContent("Expires", value: "Never (saved forever)")
                        } else if let days = video.video.expiresInDays {
                            LabeledContent("Expires", value: "in \(days) days")
                        }
                    }
                    
                    if let caption = video.video.caption, !caption.isEmpty {
                        Section("Caption") {
                            Text(caption)
                        }
                    }
                    
                    Section {
                        // React button
                        Button {
                            Task {
                                try? await videoService.toggleReaction(videoId: video.video.id)
                            }
                        } label: {
                            Label(
                                video.hasUserReacted ? "Remove Love" : "Send Love",
                                systemImage: video.hasUserReacted ? "heart.fill" : "heart"
                            )
                            .foregroundStyle(video.hasUserReacted ? .red : .primary)
                        }
                        
                        // Save forever toggle
                        Button {
                            Task {
                                try? await videoService.toggleSaveForever(id: video.video.id)
                            }
                        } label: {
                            Label(
                                video.video.saveForever ? "Remove from Saved" : "Save Forever",
                                systemImage: video.video.saveForever ? "bookmark.fill" : "bookmark"
                            )
                        }
                    }
                    
                    Section {
                        // Flag button
                        Button(role: .destructive) {
                            showFlagConfirmation = true
                        } label: {
                            Label("Report Video", systemImage: "flag")
                        }
                        
                        // Delete button (only for own videos or admins)
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete Video", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Video Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
            .confirmationDialog("Delete Video", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    Task {
                        try? await videoService.deleteVideo(id: video.video.id)
                        onDismiss()
                    }
                }
            } message: {
                Text("Are you sure you want to delete this video? This cannot be undone.")
            }
            .confirmationDialog("Report Video", isPresented: $showFlagConfirmation) {
                Button("Report", role: .destructive) {
                    Task {
                        try? await videoService.flagVideo(id: video.video.id)
                        onDismiss()
                    }
                }
            } message: {
                Text("Report this video as inappropriate? An admin will review it.")
            }
        }
        .task {
            await loadVideo()
        }
        .onDisappear {
            // Properly release AVPlayer resources to prevent memory leak
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = nil
        }
    }
    
    private func loadVideo() async {
        isLoadingVideo = true
        defer { isLoadingVideo = false }
        
        do {
            videoURL = try await videoService.getVideoURL(storageKey: video.video.storageKey)
            if let url = videoURL {
                player = AVPlayer(url: url)
                
                // Record view
                try? await videoService.recordView(videoId: video.video.id)
            }
        } catch {
            #if DEBUG
            print("Failed to load video: \(error)")
            #endif
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        VideoBoardView(
            circleId: "test-circle",
            patientId: "test-patient",
            patientName: "Mom"
        )
    }
}
