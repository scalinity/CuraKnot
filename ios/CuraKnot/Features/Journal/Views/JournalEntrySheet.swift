import SwiftUI
import PhotosUI

// MARK: - Journal Entry Sheet

/// Sheet for creating or editing a journal entry
struct JournalEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: JournalEntryViewModel

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingSaveError = false

    var onSave: ((JournalEntry) -> Void)?

    init(
        circleId: String,
        patientId: String,
        journalService: JournalService,
        existingEntry: JournalEntry? = nil,
        onSave: ((JournalEntry) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: JournalEntryViewModel(
            circleId: circleId,
            patientId: patientId,
            journalService: journalService,
            existingEntry: existingEntry
        ))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                // Entry type picker
                entryTypeSection

                // Milestone fields (if applicable)
                if viewModel.entryType == .milestone {
                    milestoneSection
                }

                // Content section
                contentSection

                // Photos section
                if viewModel.canAttachPhotos || !viewModel.selectedPhotos.isEmpty {
                    photosSection
                } else {
                    photoUpgradeSection
                }

                // Visibility section
                visibilitySection

                // Date section
                dateSection
            }
            .navigationTitle(viewModel.entryType == .goodMoment ? "Good Moment" : "Milestone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEntry()
                    }
                    .disabled(!viewModel.isValid || viewModel.isSaving)
                }
            }
            .task {
                await viewModel.onAppear()
            }
            .alert("Couldn't Save Entry", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.error?.localizedDescription ?? "An error occurred")
            }
            .sheet(isPresented: $viewModel.showingUpgradePrompt) {
                upgradePromptSheet
            }
            .onChange(of: selectedItems) { _, newItems in
                loadPhotos(from: newItems)
            }
            .disabled(viewModel.isSaving)
            .overlay {
                if viewModel.isSaving {
                    ProgressView("Saving...")
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Entry Type Section

    private var entryTypeSection: some View {
        Section {
            Picker("Entry Type", selection: $viewModel.entryType) {
                ForEach(JournalEntryType.allCases) { type in
                    Label(type.displayName, systemImage: type.icon)
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text(viewModel.entryType.description)
        }
    }

    // MARK: - Milestone Section

    private var milestoneSection: some View {
        Section("Milestone Details") {
            TextField("Title", text: $viewModel.title)

            Picker("Type", selection: Binding(
                get: { viewModel.milestoneType ?? .memory },
                set: { viewModel.milestoneType = $0 }
            )) {
                ForEach(MilestoneType.allCases) { type in
                    Label(type.displayName, systemImage: type.icon)
                        .tag(type)
                }
            }
        }
    }

    // MARK: - Content Section

    private var contentSection: some View {
        Section {
            TextEditor(text: $viewModel.content)
                .frame(minHeight: 150)
        } header: {
            Text(viewModel.entryType == .goodMoment
                 ? "What made you smile?"
                 : "Reflection"
            )
        } footer: {
            HStack {
                if !viewModel.validationErrors.isEmpty {
                    Text(viewModel.validationErrors.first ?? "")
                        .foregroundStyle(.red)
                }
                Spacer()
                Text(viewModel.characterCountText)
                    .foregroundStyle(
                        viewModel.contentCharacterCount > 2000 ? .red :
                        viewModel.contentCharacterCount > 1800 ? .orange : .secondary
                    )
            }
        }
    }

    // MARK: - Photos Section

    private var photosSection: some View {
        Section("Photos") {
            if !viewModel.selectedPhotos.isEmpty {
                // Show selected photos
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 8
                ) {
                    ForEach(Array(viewModel.selectedPhotos.enumerated()), id: \.offset) { index, image in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            Button {
                                viewModel.removePhoto(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white)
                                    .background(SwiftUI.Circle().fill(.black.opacity(0.5)))
                            }
                            .offset(x: 4, y: -4)
                        }
                    }

                    // Add more button (if under limit)
                    if viewModel.canAddMorePhotos {
                        PhotosPicker(
                            selection: $selectedItems,
                            maxSelectionCount: 3 - viewModel.selectedPhotos.count,
                            matching: .images
                        ) {
                            VStack {
                                Image(systemName: "plus")
                                    .font(.title2)
                                Text("Add")
                                    .font(.caption)
                            }
                            .frame(width: 80, height: 80)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            } else {
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 3,
                    matching: .images
                ) {
                    Label("Add Photos (up to 3)", systemImage: "photo.badge.plus")
                }
            }
        }
    }

    // MARK: - Photo Upgrade Section

    private var photoUpgradeSection: some View {
        Section {
            Button {
                viewModel.onPhotoButtonTapped()
            } label: {
                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                    Text("Attach photos with Plus")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Text("Photos")
        }
    }

    // MARK: - Visibility Section

    private var visibilitySection: some View {
        Section("Who can see this?") {
            Picker("Visibility", selection: $viewModel.visibility) {
                ForEach(EntryVisibility.allCases) { option in
                    Label(option.displayName, systemImage: option.icon)
                        .tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    // MARK: - Date Section

    private var dateSection: some View {
        Section("Date") {
            DatePicker(
                "Entry Date",
                selection: $viewModel.entryDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
        }
    }

    // MARK: - Upgrade Prompt Sheet

    private var upgradePromptSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 60))
                    .foregroundStyle(.purple.gradient)

                VStack(spacing: 8) {
                    Text("Add Photo Memories")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Capture moments with photos. Upgrade to Plus for photo attachments on your journal entries.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                Button {
                    // Navigate to upgrade
                    viewModel.showingUpgradePrompt = false
                } label: {
                    Text("Upgrade to Plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") {
                        viewModel.showingUpgradePrompt = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func saveEntry() {
        Task {
            do {
                let entry = try await viewModel.save()
                onSave?(entry)
                dismiss()
            } catch {
                showingSaveError = true
            }
        }
    }

    private func loadPhotos(from items: [PhotosPickerItem]) {
        Task {
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            viewModel.addPhotos(images)
            selectedItems = []
        }
    }
}

// Preview disabled - requires dependency injection
// To preview, use the app with DependencyContainer
