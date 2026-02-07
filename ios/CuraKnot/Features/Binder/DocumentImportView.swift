import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Document Import View

struct DocumentImportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    let circleId: String
    let patientId: String?
    
    @State private var selectedPhotosItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var selectedFileURL: URL?
    @State private var documentType: DocumentContent.DocumentType = .other
    @State private var description = ""
    @State private var documentDate = Date()
    @State private var isUploading = false
    @State private var showFilePicker = false
    
    var body: some View {
        NavigationStack {
            Form {
                // Source Selection
                Section("Select Document") {
                    PhotosPicker(
                        selection: $selectedPhotosItem,
                        matching: .images
                    ) {
                        Label("Choose from Photos", systemImage: "photo.on.rectangle")
                    }
                    
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Choose from Files", systemImage: "doc")
                    }
                }
                
                // Preview
                if let image = selectedImage {
                    Section("Preview") {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .cornerRadius(8)
                    }
                } else if let url = selectedFileURL {
                    Section("Selected File") {
                        Label(url.lastPathComponent, systemImage: "doc.fill")
                    }
                }
                
                // Details
                Section("Details") {
                    Picker("Document Type", selection: $documentType) {
                        ForEach(DocumentContent.DocumentType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    
                    DatePicker("Document Date", selection: $documentDate, displayedComponents: .date)
                    
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Import Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Upload") {
                        uploadDocument()
                    }
                    .disabled(selectedImage == nil && selectedFileURL == nil || isUploading)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            .onChange(of: selectedPhotosItem) { _, newValue in
                Task {
                    await loadImage(from: newValue)
                }
            }
            .overlay {
                if isUploading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView("Uploading...")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    
    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item = item else { return }
        
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            selectedImage = image
            selectedFileURL = nil
        }
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                selectedFileURL = url
                selectedImage = nil
            }
        case .failure(let error):
            #if DEBUG
            print("File selection error: \(error)")
            #endif
        }
    }
    
    private func uploadDocument() {
        isUploading = true
        
        Task {
            do {
                let data: Data
                let mimeType: String
                let filename: String
                
                if let image = selectedImage {
                    data = image.jpegData(compressionQuality: 0.8) ?? Data()
                    mimeType = "image/jpeg"
                    filename = "photo_\(Date().timeIntervalSince1970).jpg"
                } else if let url = selectedFileURL {
                    _ = url.startAccessingSecurityScopedResource()
                    defer { url.stopAccessingSecurityScopedResource() }
                    
                    data = try Data(contentsOf: url)
                    mimeType = url.pathExtension == "pdf" ? "application/pdf" : "image/jpeg"
                    filename = url.lastPathComponent
                } else {
                    throw DocumentImportError.noFile
                }
                
                // TODO: Upload via UploadManager
                // let storageKey = try await uploadManager.uploadAttachment(...)
                _ = (data, mimeType, filename) // Silence warnings until upload is implemented
                
                // Create binder item with attachment reference
                // let documentContent = DocumentContent(
                //     description: description.isEmpty ? nil : description,
                //     documentType: documentType,
                //     date: documentDate,
                //     attachmentId: attachmentId
                // )
                
                isUploading = false
                dismiss()
                
            } catch {
                #if DEBUG
                print("Upload error: \(error)")
                #endif
                isUploading = false
            }
        }
    }
}

// MARK: - Document Import Error

enum DocumentImportError: Error, LocalizedError {
    case noFile
    case uploadFailed
    
    var errorDescription: String? {
        switch self {
        case .noFile:
            return "No file selected"
        case .uploadFailed:
            return "Failed to upload document"
        }
    }
}

// NOTE: DocumentScannerView moved to Features/DocumentScanner/Views/DocumentScannerView.swift

#Preview {
    DocumentImportView(circleId: "test", patientId: "patient")
        .environmentObject(AppState())
}
