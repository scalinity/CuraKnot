import SwiftUI

// MARK: - Cached Journal Image

/// A SwiftUI view that loads and caches journal photos
/// Uses JournalImageCache for efficient memory management
struct CachedJournalImage: View {
    let storageKey: String
    let supabaseClient: SupabaseClient

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var loadError = false

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.1))
            } else if loadError {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                    Text("Failed to load")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.secondary.opacity(0.1))
            }
        }
        .task(id: storageKey) {
            await loadImage()
        }
    }

    private func loadImage() async {
        isLoading = true
        loadError = false

        // Check cache first
        if let cached = JournalImageCache.shared.image(forKey: storageKey) {
            image = cached
            isLoading = false
            return
        }

        do {
            // Get signed URL from Supabase
            let url = try await JournalPhotoUploader.getSignedURL(
                storageKey: storageKey,
                expiresIn: 3600,
                supabaseClient: supabaseClient
            )

            // Load with caching
            let loadedImage = try await JournalImageLoader.shared.loadImage(
                from: url,
                cacheKey: storageKey
            )

            await MainActor.run {
                image = loadedImage
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = true
                isLoading = false
            }
        }
    }
}

// MARK: - Journal Photo Grid (Cached)

/// A grid displaying journal photos with caching
struct CachedPhotoGrid: View {
    let storageKeys: [String]
    let supabaseClient: SupabaseClient
    var onTap: ((Int) -> Void)?

    private let spacing: CGFloat = 8

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: spacing
        ) {
            ForEach(Array(storageKeys.enumerated()), id: \.element) { index, key in
                Button {
                    onTap?(index)
                } label: {
                    CachedJournalImage(storageKey: key, supabaseClient: supabaseClient)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Photo Thumbnail Row (Cached)

/// A horizontal row of photo thumbnails with caching
struct CachedPhotoThumbnailRow: View {
    let storageKeys: [String]
    let supabaseClient: SupabaseClient
    let maxVisible: Int

    init(storageKeys: [String], supabaseClient: SupabaseClient, maxVisible: Int = 3) {
        self.storageKeys = storageKeys
        self.supabaseClient = supabaseClient
        self.maxVisible = maxVisible
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(storageKeys.prefix(maxVisible).enumerated()), id: \.element) { _, key in
                CachedJournalImage(storageKey: key, supabaseClient: supabaseClient)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if storageKeys.count > maxVisible {
                Text("+\(storageKeys.count - maxVisible)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
