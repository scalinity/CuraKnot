import Foundation
import UIKit

// MARK: - Journal Image Cache

/// Thread-safe in-memory cache for journal photos
/// Uses NSCache for automatic memory management
final class JournalImageCache: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = JournalImageCache()

    // MARK: - Cache

    private let cache: NSCache<NSString, UIImage>
    private let urlCache: URLCache

    // MARK: - Initialization

    private init() {
        cache = NSCache<NSString, UIImage>()
        cache.countLimit = 50  // Max 50 images in memory
        cache.totalCostLimit = 50 * 1024 * 1024  // 50MB limit

        // URL cache for network responses
        urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,  // 20MB memory
            diskCapacity: 100 * 1024 * 1024,    // 100MB disk
            diskPath: "JournalPhotoCache"
        )
    }

    // MARK: - Cache Operations

    /// Get image from cache
    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    /// Store image in cache
    func setImage(_ image: UIImage, forKey key: String) {
        let cost = Int(image.size.width * image.size.height * 4) // Approximate bytes
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    /// Remove image from cache
    func removeImage(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    /// Clear all cached images
    func clearAll() {
        cache.removeAllObjects()
    }

    // MARK: - URL Cache

    /// Get cached response for URL
    func cachedResponse(for request: URLRequest) -> CachedURLResponse? {
        urlCache.cachedResponse(for: request)
    }

    /// Store response in URL cache
    func storeCachedResponse(_ response: CachedURLResponse, for request: URLRequest) {
        urlCache.storeCachedResponse(response, for: request)
    }
}

// MARK: - Image Loader

/// Async image loader with caching support
actor JournalImageLoader {

    // MARK: - Singleton

    static let shared = JournalImageLoader()

    // MARK: - State

    private var loadingTasks: [String: Task<UIImage, Error>] = [:]

    // MARK: - Load Image

    /// Load image from URL with caching
    /// - Parameters:
    ///   - url: The URL to load from
    ///   - cacheKey: Optional cache key (defaults to URL string)
    /// - Returns: The loaded UIImage
    func loadImage(from url: URL, cacheKey: String? = nil) async throws -> UIImage {
        let key = cacheKey ?? url.absoluteString

        // Check memory cache first
        if let cached = JournalImageCache.shared.image(forKey: key) {
            return cached
        }

        // Check if already loading
        if let existingTask = loadingTasks[key] {
            return try await existingTask.value
        }

        // Start new load task
        let task = Task<UIImage, Error> {
            let request = URLRequest(url: url)

            // Check URL cache
            if let cachedResponse = JournalImageCache.shared.cachedResponse(for: request),
               let image = UIImage(data: cachedResponse.data) {
                JournalImageCache.shared.setImage(image, forKey: key)
                return image
            }

            // Fetch from network
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let image = UIImage(data: data) else {
                throw JournalPhotoError.downloadFailed
            }

            // Cache the response
            let cachedResponse = CachedURLResponse(response: response, data: data)
            JournalImageCache.shared.storeCachedResponse(cachedResponse, for: request)
            JournalImageCache.shared.setImage(image, forKey: key)

            return image
        }

        loadingTasks[key] = task

        defer {
            loadingTasks[key] = nil
        }

        return try await task.value
    }

    /// Cancel loading for a specific key
    func cancelLoad(for key: String) {
        loadingTasks[key]?.cancel()
        loadingTasks[key] = nil
    }

    /// Clear all loading tasks
    func cancelAll() {
        for task in loadingTasks.values {
            task.cancel()
        }
        loadingTasks.removeAll()
    }
}
