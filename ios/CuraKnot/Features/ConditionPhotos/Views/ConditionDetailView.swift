import SwiftUI

// MARK: - Condition Detail View

struct ConditionDetailView: View {
    @EnvironmentObject var dependencyContainer: DependencyContainer
    @StateObject private var viewModel: ConditionDetailViewModel
    @StateObject private var biometricManager = BiometricSessionManager()

    init(condition: TrackedCondition) {
        _viewModel = StateObject(wrappedValue: ConditionDetailViewModel(condition: condition))
    }

    var body: some View {
        BiometricGateView(
            biometricManager: biometricManager,
            reason: "Authenticate to view condition photos"
        ) {
            conditionContent
        }
        .navigationTitle(viewModel.condition.conditionType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.configure(
                conditionPhotoService: dependencyContainer.conditionPhotoService,
                subscriptionManager: dependencyContainer.subscriptionManager,
                biometricManager: biometricManager
            )
            await viewModel.loadPhotos()
        }
    }

    private var conditionContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                conditionHeader
                actionButtons
                Divider()

                if viewModel.isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .padding(.vertical, 40)
                } else if viewModel.photos.isEmpty {
                    emptyPhotosView
                } else {
                    photoTimeline
                }
            }
            .padding()
        }
        .sheet(isPresented: $viewModel.showingCapture) {
            ConditionPhotoCaptureView { imageData, notes, quality in
                await viewModel.onPhotoCaptured(
                    imageData: imageData,
                    notes: notes,
                    lightingQuality: quality
                )
            }
        }
        .sheet(isPresented: $viewModel.showingComparison) {
            if viewModel.photos.count >= 2 {
                NavigationStack {
                    PhotoComparisonView(
                        photos: viewModel.photos,
                        conditionPhotoService: dependencyContainer.conditionPhotoService,
                        biometricManager: biometricManager
                    )
                }
            }
        }
        .sheet(isPresented: $viewModel.showingShareSheet) {
            ConditionShareSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingResolveSheet) {
            ResolveConditionSheet { notes in
                await viewModel.resolveCondition(notes: notes)
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            if let error = viewModel.errorMessage { Text(error) }
        }
    }

    // MARK: - Header

    private var conditionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: viewModel.condition.conditionType.icon)
                    .font(.title2)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading) {
                    Text(viewModel.condition.bodyLocation)
                        .font(.title3)
                        .fontWeight(.semibold)

                    if let desc = viewModel.condition.description, !desc.isEmpty {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(viewModel.condition.status.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.1))
                    .clipShape(Capsule())
            }

            HStack(spacing: 16) {
                Label("Day \(viewModel.condition.daysSinceStart)", systemImage: "calendar")
                Label("\(viewModel.photos.count) photos", systemImage: "photo")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch viewModel.condition.status {
        case .active: return .blue
        case .resolved: return .green
        case .archived: return .gray
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if viewModel.isActive {
                Button {
                    viewModel.showingCapture = true
                } label: {
                    Label("Add Photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityLabel("Add condition photo")
                .accessibilityHint("Opens camera to capture a new photo")
            }

            HStack(spacing: 10) {
                if viewModel.canCompare {
                    Button {
                        viewModel.showingComparison = true
                    } label: {
                        Label("Compare", systemImage: "rectangle.split.2x1")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Compare photos side by side")
                }

                if viewModel.canShare {
                    Button {
                        viewModel.showingShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Share photos with clinician")
                }
            }

            if viewModel.isActive {
                Button(role: .destructive) {
                    viewModel.showingResolveSheet = true
                } label: {
                    Label("Mark as Resolved", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Mark condition as resolved")
            }
        }
    }

    // MARK: - Empty State

    private var emptyPhotosView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No Photos Yet")
                .font(.headline)
            Text("Take your first photo to start tracking this condition's progression.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Photo Timeline

    private var photoTimeline: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            Text("Timeline")
                .font(.headline)
                .padding(.bottom, 12)

            ForEach(viewModel.photos) { photo in
                PhotoTimelineRow(
                    photo: photo,
                    thumbnailURL: viewModel.thumbnailURLs[photo.id],
                    onTap: { Task { await viewModel.viewPhoto(photo) } },
                    onDelete: { Task { await viewModel.deletePhoto(photo) } }
                )
            }
        }
        .sheet(item: $viewModel.selectedPhoto) { photo in
            if let url = viewModel.selectedPhotoURL {
                PhotoFullScreenView(photo: photo, url: url)
            }
        }
    }
}

// MARK: - Photo Timeline Row

struct PhotoTimelineRow: View {
    let photo: ConditionPhoto
    let thumbnailURL: URL?
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteConfirm = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                SwiftUI.Circle().fill(.blue).frame(width: 8, height: 8)
                Rectangle().fill(.blue.opacity(0.3)).frame(width: 2)
            }
            .frame(width: 8)

            Button(action: onTap) {
                if let url = thumbnailURL {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(.secondary.opacity(0.2))
                            .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Rectangle().fill(.secondary.opacity(0.2))
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(photo.capturedAt, style: .date)
                    .font(.subheadline).fontWeight(.medium)
                Text(photo.capturedAt, style: .time)
                    .font(.caption).foregroundStyle(.secondary)
                if let notes = photo.notes, !notes.isEmpty {
                    Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }

            Spacer()

            Button(role: .destructive) { showingDeleteConfirm = true } label: {
                Image(systemName: "trash").font(.caption)
            }
            .confirmationDialog("Delete Photo", isPresented: $showingDeleteConfirm) {
                Button("Delete Photo", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This photo will be permanently deleted.")
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Photo Full Screen View

struct PhotoFullScreenView: View {
    let photo: ConditionPhoto
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var screenshotDetected = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView().frame(height: 300)
                    }

                    if let notes = photo.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes").font(.caption).foregroundStyle(.secondary)
                            Text(notes).font(.body)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    }

                    HStack {
                        Label(photo.capturedAt.formatted(date: .long, time: .shortened), systemImage: "calendar")
                        Spacer()
                    }
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                }
            }
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
                screenshotDetected = true
            }
            .alert("Screenshot Detected", isPresented: $screenshotDetected) {
                Button("OK") { screenshotDetected = false }
            } message: {
                Text("This content contains sensitive medical photos. Please be mindful of patient privacy.")
            }
        }
    }
}

// MARK: - Resolve Condition Sheet

struct ResolveConditionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onResolve: (String?) async -> Void
    @State private var notes = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Resolution Notes (optional)") {
                    TextField("How did the condition resolve?", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section {
                    Text("Marking a condition as resolved will move it out of your active list. You can still view the photo timeline.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Resolve Condition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Resolve") {
                        isSaving = true
                        Task {
                            await onResolve(notes.isEmpty ? nil : notes)
                            isSaving = false
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }
}
