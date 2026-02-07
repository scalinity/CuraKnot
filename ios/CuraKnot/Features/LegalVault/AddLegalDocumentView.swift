import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Add Legal Document View

struct AddLegalDocumentView: View {
    @Environment(\.dismiss) private var dismiss

    let service: LegalVaultService
    let circleId: String
    let patientId: String
    let onSave: () -> Void

    // Document info
    @State private var documentType: LegalDocumentType = .powerOfAttorney
    @State private var title = ""
    @State private var description = ""

    // File
    @State private var selectedFileData: Data?
    @State private var selectedFileType = "PDF"
    @State private var selectedMimeType = "application/pdf"
    @State private var selectedFileName = ""
    @State private var showingDocumentPicker = false
    @State private var showingCamera = false

    // Dates
    @State private var hasExecutionDate = false
    @State private var executionDate = Date()
    @State private var hasExpirationDate = false
    @State private var expirationDate = Date()

    // Parties
    @State private var principalName = ""
    @State private var agentName = ""
    @State private var alternateAgentName = ""

    // Verification
    @State private var notarized = false
    @State private var notarizedDate = Date()
    @State private var witnessNames: [String] = []
    @State private var newWitnessName = ""

    // Emergency
    @State private var includeInEmergency = false

    // State
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                // Document type
                Section("Document Type") {
                    Picker("Type", selection: $documentType) {
                        ForEach(LegalDocumentType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }

                // Title and description
                Section("Document Info") {
                    TextField("Title", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }

                // File upload
                Section("Document File") {
                    if let _ = selectedFileData {
                        HStack {
                            Image(systemName: selectedFileType == "PDF" ? "doc.fill" : "photo.fill")
                                .foregroundStyle(.blue)
                            Text(selectedFileName.isEmpty ? "File selected" : selectedFileName)
                            Spacer()
                            Button("Remove") {
                                selectedFileData = nil
                                selectedFileName = ""
                                selectedFileType = "PDF"
                                selectedMimeType = "application/pdf"
                            }
                            .foregroundStyle(.red)
                        }
                    } else {
                        Button {
                            showingDocumentPicker = true
                        } label: {
                            Label("Import from Files", systemImage: "folder")
                        }

                        Button {
                            showingCamera = true
                        } label: {
                            Label("Scan Document", systemImage: "doc.text.viewfinder")
                        }
                    }
                }

                // Dates
                Section("Dates") {
                    Toggle("Execution Date", isOn: $hasExecutionDate)
                    if hasExecutionDate {
                        DatePicker("Executed", selection: $executionDate, displayedComponents: .date)
                    }

                    Toggle("Expiration Date", isOn: $hasExpirationDate)
                    if hasExpirationDate {
                        DatePicker("Expires", selection: $expirationDate, displayedComponents: .date)
                    }
                }

                // Parties
                Section("Parties") {
                    TextField("Principal (person granting authority)", text: $principalName)
                    TextField("Agent / Representative", text: $agentName)
                    TextField("Alternate Agent (optional)", text: $alternateAgentName)
                }

                // Verification
                Section("Verification") {
                    Toggle("Notarized", isOn: $notarized)
                    if notarized {
                        DatePicker("Notarized Date", selection: $notarizedDate, displayedComponents: .date)
                    }

                    // Witnesses
                    ForEach(Array(witnessNames.enumerated()), id: \.offset) { index, name in
                        HStack {
                            Text(name)
                            Spacer()
                            Button {
                                witnessNames.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    HStack {
                        TextField("Add witness", text: $newWitnessName)
                        Button {
                            guard !newWitnessName.isEmpty else { return }
                            witnessNames.append(newWitnessName)
                            newWitnessName = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .disabled(newWitnessName.isEmpty)
                    }
                }

                // Emergency access
                Section {
                    Toggle("Include in Emergency Card", isOn: $includeInEmergency)
                } footer: {
                    Text("When enabled, this document will be accessible from the Emergency Card.")
                }

                // Error display
                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Legal Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveDocument()
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("Uploading...")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .fileImporter(
                isPresented: $showingDocumentPicker,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraCaptureView { imageData in
                    selectedFileData = imageData
                    selectedFileType = "IMAGE"
                    selectedMimeType = "image/jpeg"
                    selectedFileName = "Scanned document"
                }
            }
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        !title.isEmpty && selectedFileData != nil
    }

    // MARK: - Save

    private func saveDocument() {
        guard let fileData = selectedFileData else { return }
        isSaving = true
        error = nil

        Task {
            do {
                _ = try await service.uploadDocument(
                    circleId: circleId,
                    patientId: patientId,
                    documentType: documentType,
                    title: title,
                    description: description.isEmpty ? nil : description,
                    fileData: fileData,
                    fileType: selectedFileType,
                    mimeType: selectedMimeType,
                    executionDate: hasExecutionDate ? executionDate : nil,
                    expirationDate: hasExpirationDate ? expirationDate : nil,
                    principalName: principalName.isEmpty ? nil : principalName,
                    agentName: agentName.isEmpty ? nil : agentName,
                    alternateAgentName: alternateAgentName.isEmpty ? nil : alternateAgentName,
                    notarized: notarized,
                    notarizedDate: notarized ? notarizedDate : nil,
                    witnessNames: witnessNames,
                    includeInEmergency: includeInEmergency,
                    accessUserIds: [] // Creator gets implicit access
                )
                onSave()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isSaving = false
        }
    }

    // MARK: - File Import

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                selectedFileData = data
                selectedFileName = url.lastPathComponent

                let lowercasedExt = url.pathExtension.lowercased()
                if lowercasedExt == "pdf" {
                    selectedFileType = "PDF"
                    selectedMimeType = "application/pdf"
                } else {
                    selectedFileType = "IMAGE"
                    switch lowercasedExt {
                    case "png": selectedMimeType = "image/png"
                    case "heic", "heif": selectedMimeType = "image/heic"
                    default: selectedMimeType = "image/jpeg"
                    }
                }
            } catch {
                self.error = "Failed to read file: \(error.localizedDescription)"
            }

        case .failure(let error):
            self.error = "Failed to import file: \(error.localizedDescription)"
        }
    }
}

// MARK: - Camera Capture View (Placeholder)

struct CameraCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (Data) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "camera")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)

                Text("Document Scanner")
                    .font(.headline)

                Text("Camera-based document scanning will use the existing DocumentScanner feature.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .navigationTitle("Scan Document")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
