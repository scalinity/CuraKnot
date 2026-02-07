import SwiftUI

// MARK: - Condition Share Sheet

struct ConditionShareSheet: View {
    @ObservedObject var viewModel: ConditionDetailViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhotoIds: Set<UUID> = []
    @State private var expirationDays: Int = 3
    @State private var singleUse = false
    @State private var recipient = ""

    private let expirationOptions = [1, 3, 7]

    var body: some View {
        NavigationStack {
            if let shareURL = viewModel.shareURL {
                shareLinkResult(shareURL)
            } else {
                shareForm
            }
        }
    }

    // MARK: - Share Form

    private var shareForm: some View {
        Form {
            // Photo selection
            Section {
                ForEach(viewModel.photos) { photo in
                    Button {
                        toggleSelection(photo.id)
                    } label: {
                        HStack {
                            if let url = viewModel.thumbnailURLs[photo.id] {
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Rectangle().fill(.secondary.opacity(0.2))
                                }
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                Rectangle()
                                    .fill(.secondary.opacity(0.2))
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay {
                                        Image(systemName: "lock.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(photo.capturedAt, style: .date)
                                    .font(.subheadline)
                                if let notes = photo.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Image(systemName: selectedPhotoIds.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedPhotoIds.contains(photo.id) ? .blue : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                HStack {
                    Text("Select Photos")
                    Spacer()
                    Button(selectedPhotoIds.count == viewModel.photos.count ? "Deselect All" : "Select All") {
                        if selectedPhotoIds.count == viewModel.photos.count {
                            selectedPhotoIds.removeAll()
                        } else {
                            selectedPhotoIds = Set(viewModel.photos.map(\.id))
                        }
                    }
                    .font(.caption)
                }
            }

            // Settings
            Section("Link Settings") {
                Picker("Expires in", selection: $expirationDays) {
                    ForEach(expirationOptions, id: \.self) { days in
                        Text("\(days) \(days == 1 ? "day" : "days")").tag(days)
                    }
                }

                Toggle("Single use (one-time access)", isOn: $singleUse)
            }

            // Recipient
            Section("Recipient (optional)") {
                TextField("Clinician name or email", text: $recipient)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
            }

            // Info
            Section {
                Label {
                    Text("Share links provide temporary access to selected photos without requiring login. Links are logged for security.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                }
            }
        }
        .navigationTitle("Share Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create Link") {
                    Task {
                        await viewModel.createShareLink(
                            photoIds: Array(selectedPhotoIds),
                            expirationDays: expirationDays,
                            singleUse: singleUse,
                            recipient: recipient.isEmpty ? nil : recipient
                        )
                    }
                }
                .disabled(selectedPhotoIds.isEmpty || viewModel.isCreatingShare)
            }
        }
        .onAppear {
            // Pre-select all photos
            selectedPhotoIds = Set(viewModel.photos.map(\.id))
        }
    }

    // MARK: - Share Link Result

    private func shareLinkResult(_ url: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.green)

            Text("Share Link Created")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Send this link to a clinician. It will expire in \(expirationDays) \(expirationDays == 1 ? "day" : "days").")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Link display
            HStack {
                Text(url)
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Button {
                    UIPasteboard.general.string = url
                } label: {
                    Image(systemName: "doc.on.doc")
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)

            // Share via system share sheet
            ShareLink(item: url) {
                Label("Share Link", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)

            if singleUse {
                Label("This link can only be used once", systemImage: "1.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") { dismiss() }
                .padding(.bottom)
        }
        .navigationTitle("Share Link")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

    private func toggleSelection(_ id: UUID) {
        if selectedPhotoIds.contains(id) {
            selectedPhotoIds.remove(id)
        } else {
            selectedPhotoIds.insert(id)
        }
    }
}
