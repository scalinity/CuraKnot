import Foundation

// MARK: - Condition Detail ViewModel

@MainActor
final class ConditionDetailViewModel: ObservableObject {

    // MARK: - Published State

    @Published var condition: TrackedCondition
    @Published var photos: [ConditionPhoto] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Photo viewing
    @Published var selectedPhoto: ConditionPhoto?
    @Published var selectedPhotoURL: URL?
    @Published var thumbnailURLs: [UUID: URL] = [:]

    // Actions
    @Published var showingCapture = false
    @Published var showingComparison = false
    @Published var showingShareSheet = false
    @Published var showingResolveSheet = false

    // Share
    @Published var shareURL: String?
    @Published var isCreatingShare = false

    // Task tracking
    private var loadTask: Task<Void, Never>?

    // MARK: - Dependencies

    private var conditionPhotoService: ConditionPhotoService?
    private var subscriptionManager: SubscriptionManager?
    private var biometricManager: BiometricSessionManager?

    // MARK: - Computed

    var canCompare: Bool {
        (subscriptionManager?.hasFeature(.conditionPhotoCompare) ?? false) && photos.count >= 2
    }

    var canShare: Bool {
        (subscriptionManager?.hasFeature(.conditionPhotoShare) ?? false) && !photos.isEmpty
    }

    var isActive: Bool {
        condition.status == .active
    }

    // MARK: - Initialization

    init(condition: TrackedCondition) {
        self.condition = condition
    }

    deinit {
        loadTask?.cancel()
    }

    func configure(
        conditionPhotoService: ConditionPhotoService,
        subscriptionManager: SubscriptionManager,
        biometricManager: BiometricSessionManager
    ) {
        self.conditionPhotoService = conditionPhotoService
        self.subscriptionManager = subscriptionManager
        self.biometricManager = biometricManager
    }

    // MARK: - Data Loading

    func loadPhotos() async {
        guard let conditionPhotoService else { return }

        loadTask?.cancel()

        let task = Task {
            isLoading = true
            errorMessage = nil

            do {
                let fetchedPhotos = try await conditionPhotoService.getPhotos(conditionId: condition.id)

                guard !Task.isCancelled else { return }
                photos = fetchedPhotos

                // Load all thumbnail URLs in parallel using TaskGroup
                let photoList = photos
                let urls = try await withTaskGroup(of: (UUID, URL?).self, returning: [UUID: URL].self) { group in
                    for photo in photoList {
                        group.addTask {
                            let url = try? await conditionPhotoService.getThumbnailURL(photo: photo)
                            return (photo.id, url)
                        }
                    }

                    var results: [UUID: URL] = [:]
                    for await (id, url) in group {
                        if let url {
                            results[id] = url
                        }
                    }
                    return results
                }

                guard !Task.isCancelled else { return }
                thumbnailURLs = urls
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }

            isLoading = false
        }
        loadTask = task
        await task.value
    }

    // MARK: - Photo Viewing (with biometric gate)

    func viewPhoto(_ photo: ConditionPhoto) async {
        guard let biometricManager, let conditionPhotoService else { return }

        let authenticated = await biometricManager.ensureAuthenticated(
            reason: "Authenticate to view condition photo"
        )
        guard authenticated else { return }

        do {
            let url = try await conditionPhotoService.getPhotoURL(photo: photo)
            selectedPhoto = photo
            selectedPhotoURL = url

            do {
                try await conditionPhotoService.logPhotoAccess(
                    circleId: photo.circleId,
                    photoId: photo.id,
                    accessType: "VIEW"
                )
            } catch {
                #if DEBUG
                print("[AuditLog] Failed to log VIEW access: \(error.localizedDescription)")
                #endif
            }
        } catch {
            errorMessage = "Failed to load photo."
        }
    }

    // MARK: - Photo Capture

    func onPhotoCaptured(imageData: Data, notes: String?, lightingQuality: LightingQuality?) async {
        guard let conditionPhotoService else { return }

        do {
            let photo = try await conditionPhotoService.capturePhoto(
                conditionId: condition.id,
                circleId: condition.circleId,
                patientId: condition.patientId,
                imageData: imageData,
                notes: notes,
                annotations: nil,
                lightingQuality: lightingQuality
            )
            photos.insert(photo, at: 0)

            if let url = try? await conditionPhotoService.getThumbnailURL(photo: photo) {
                thumbnailURLs[photo.id] = url
            }

            showingCapture = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Delete Photo

    func deletePhoto(_ photo: ConditionPhoto) async {
        guard let conditionPhotoService else { return }

        do {
            try await conditionPhotoService.deletePhoto(
                id: photo.id,
                circleId: photo.circleId,
                storageKey: photo.storageKey,
                thumbnailKey: photo.thumbnailKey
            )
            photos.removeAll { $0.id == photo.id }
            thumbnailURLs.removeValue(forKey: photo.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Condition Actions

    func resolveCondition(notes: String?) async {
        guard let conditionPhotoService else { return }

        do {
            try await conditionPhotoService.resolveCondition(id: condition.id, notes: notes)
            condition.status = .resolved
            condition.resolvedDate = Date()
            condition.resolutionNotes = notes
            showingResolveSheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func archiveCondition() async {
        guard let conditionPhotoService else { return }

        do {
            try await conditionPhotoService.archiveCondition(id: condition.id)
            condition.status = .archived
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sharing

    func createShareLink(photoIds: [UUID], expirationDays: Int, singleUse: Bool, recipient: String?) async {
        guard let conditionPhotoService else { return }

        // Validate inputs
        guard !photoIds.isEmpty else {
            errorMessage = "Select at least one photo to share."
            return
        }
        guard (1...7).contains(expirationDays) else {
            errorMessage = "Share link expiration must be between 1 and 7 days."
            return
        }

        isCreatingShare = true
        defer { isCreatingShare = false }

        do {
            let response = try await conditionPhotoService.createShareLink(
                conditionId: condition.id,
                photoIds: photoIds,
                expirationDays: expirationDays,
                singleUse: singleUse,
                recipient: recipient
            )
            shareURL = response.shareUrl
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
