import SwiftUI

// MARK: - Photo Comparison View

struct PhotoComparisonView: View {
    let photos: [ConditionPhoto]
    let conditionPhotoService: ConditionPhotoService
    @ObservedObject var biometricManager: BiometricSessionManager

    @Environment(\.dismiss) private var dismiss
    @State private var leftIndex = 0
    @State private var rightIndex = 1
    @State private var leftURL: URL?
    @State private var rightURL: URL?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var leftZoomScale: CGFloat = 1.0
    @State private var rightZoomScale: CGFloat = 1.0
    @State private var loadTask: Task<Void, Never>?
    @State private var cachedSortedPhotos: [ConditionPhoto] = []
    @State private var screenshotDetected = false

    var body: some View {
        VStack(spacing: 0) {
            if cachedSortedPhotos.count < 2 {
                placeholderView(icon: "photo.on.rectangle", text: "Need at least 2 photos to compare")
            } else if isLoading {
                Spacer()
                ProgressView("Loading photos...")
                Spacer()
            } else if let error = errorMessage {
                errorView(error)
            } else {
                comparisonContent
            }
        }
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task {
            cachedSortedPhotos = photos.sorted { $0.capturedAt < $1.capturedAt }
            await loadComparisonPhotos()
        }
        .onDisappear {
            loadTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            screenshotDetected = true
            // Log screenshot attempt for audit
            if cachedSortedPhotos.count >= 2,
               leftIndex < cachedSortedPhotos.count {
                let photo = cachedSortedPhotos[leftIndex]
                Task {
                    do {
                        try await conditionPhotoService.logPhotoAccess(
                            circleId: photo.circleId,
                            photoId: photo.id,
                            accessType: "SCREENSHOT_DETECTED"
                        )
                    } catch {
                        #if DEBUG
                        print("[AuditLog] Failed to log screenshot detection")
                        #endif
                    }
                }
            }
        }
        .alert("Screenshot Detected", isPresented: $screenshotDetected) {
            Button("OK") { screenshotDetected = false }
        } message: {
            Text("This content contains sensitive medical photos. Please be mindful of patient privacy.")
        }
    }

    // MARK: - Comparison Content

    private var comparisonContent: some View {
        let sorted = cachedSortedPhotos
        return VStack(spacing: 0) {
            // Date labels
            HStack {
                if leftIndex < sorted.count {
                    Text(sorted[leftIndex].capturedAt, style: .date)
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                }

                Divider().frame(height: 20)

                if rightIndex < sorted.count {
                    Text(sorted[rightIndex].capturedAt, style: .date)
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))

            // Side-by-side photos
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    photoPanel(url: leftURL, width: geometry.size.width / 2 - 0.5, zoomScale: $leftZoomScale)
                    photoPanel(url: rightURL, width: geometry.size.width / 2 - 0.5, zoomScale: $rightZoomScale)
                }
            }

            // Photo selector
            photoSelector
        }
    }

    private func photoPanel(url: URL?, width: CGFloat, zoomScale: Binding<CGFloat>) -> some View {
        Group {
            if let url = url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(zoomScale.wrappedValue)
                            .gesture(
                                MagnifyGesture()
                                    .onChanged { value in
                                        zoomScale.wrappedValue = max(1.0, min(value.magnification, 4.0))
                                    }
                                    .onEnded { _ in
                                        withAnimation { zoomScale.wrappedValue = 1.0 }
                                    }
                            )
                    case .failure:
                        placeholderView(icon: "exclamationmark.triangle", text: "Load failed")
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                placeholderView(icon: "photo", text: "No photo")
            }
        }
        .frame(width: width)
        .clipped()
    }

    private func placeholderView(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Photo Selector

    private var photoSelector: some View {
        let sorted = cachedSortedPhotos
        return VStack(spacing: 8) {
            HStack {
                Text("Earlier")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Recent")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            HStack {
                // Left photo picker
                Picker("Left", selection: $leftIndex) {
                    ForEach(0..<sorted.count, id: \.self) { index in
                        Text(sorted[index].capturedAt.formatted(date: .abbreviated, time: .omitted))
                            .tag(index)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)

                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Right photo picker
                Picker("Right", selection: $rightIndex) {
                    ForEach(0..<sorted.count, id: \.self) { index in
                        Text(sorted[index].capturedAt.formatted(date: .abbreviated, time: .omitted))
                            .tag(index)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)

            // Day difference label
            if leftIndex < sorted.count, rightIndex < sorted.count {
                let dayDiff = Calendar.current.dateComponents(
                    [.day],
                    from: sorted[leftIndex].capturedAt,
                    to: sorted[rightIndex].capturedAt
                ).day ?? 0

                Text("\(abs(dayDiff)) days apart")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .background(Color(.systemGroupedBackground))
        .onChange(of: leftIndex) { _, _ in
            reloadPhotos()
        }
        .onChange(of: rightIndex) { _, _ in
            reloadPhotos()
        }
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                reloadPhotos()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Loading

    private func reloadPhotos() {
        loadTask?.cancel()
        loadTask = Task {
            // Debounce rapid picker changes
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
            guard !Task.isCancelled else { return }
            await loadComparisonPhotos()
        }
    }

    private func loadComparisonPhotos() async {
        let sorted = cachedSortedPhotos
        guard sorted.count >= 2 else { return }
        guard leftIndex < sorted.count, rightIndex < sorted.count else { return }

        let authenticated = await biometricManager.ensureAuthenticated(
            reason: "Authenticate to compare condition photos"
        )
        guard authenticated else {
            errorMessage = "Authentication required to view photos."
            return
        }

        guard !Task.isCancelled else { return }

        isLoading = true
        errorMessage = nil

        do {
            let left = sorted[leftIndex]
            let right = sorted[rightIndex]

            async let leftResult = conditionPhotoService.getPhotoURL(photo: left)
            async let rightResult = conditionPhotoService.getPhotoURL(photo: right)

            let fetchedLeft = try await leftResult
            let fetchedRight = try await rightResult

            guard !Task.isCancelled else { return }

            leftURL = fetchedLeft
            rightURL = fetchedRight

            // Log access
            do {
                try await conditionPhotoService.logPhotoAccess(
                    circleId: left.circleId,
                    photoId: left.id,
                    accessType: "COMPARE"
                )
                try await conditionPhotoService.logPhotoAccess(
                    circleId: right.circleId,
                    photoId: right.id,
                    accessType: "COMPARE"
                )
            } catch {
                #if DEBUG
                print("[AuditLog] Failed to log COMPARE access")
                #endif
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Failed to load photos for comparison."
        }

        guard !Task.isCancelled else { return }
        isLoading = false
    }
}
