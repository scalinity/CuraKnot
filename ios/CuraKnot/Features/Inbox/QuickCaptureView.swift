import SwiftUI
import PhotosUI
import AVFoundation

// MARK: - Quick Capture View

struct QuickCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    let onCapture: (InboxItem) -> Void
    
    @State private var selectedMode: CaptureMode = .photo
    @State private var title = ""
    @State private var note = ""
    @State private var selectedPatient: Patient?
    @State private var textContent = ""
    
    // Photo capture
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var showingCamera = false
    
    // PDF
    @State private var showingDocumentPicker = false
    @State private var selectedDocumentURL: URL?
    
    // Audio
    @State private var isRecording = false
    @State private var recordingDuration: TimeInterval = 0
    
    @State private var isSaving = false
    
    enum CaptureMode: String, CaseIterable {
        case photo = "Photo"
        case pdf = "PDF"
        case audio = "Audio"
        case text = "Text"
        
        var icon: String {
            switch self {
            case .photo: return "camera"
            case .pdf: return "doc"
            case .audio: return "mic"
            case .text: return "text.alignleft"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Mode Selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(CaptureMode.allCases, id: \.self) { mode in
                            CaptureModeButton(
                                mode: mode,
                                isSelected: selectedMode == mode
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedMode = mode
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
                
                Divider()
                
                // Capture Area
                ScrollView {
                    VStack(spacing: 20) {
                        captureContent
                        
                        // Common Fields
                        VStack(spacing: 16) {
                            TextField("Title (optional)", text: $title)
                                .textFieldStyle(.roundedBorder)
                            
                            TextField("Note (optional)", text: $note, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(3...6)
                            
                            // Patient Picker
                            Picker("Patient", selection: $selectedPatient) {
                                Text("No Patient").tag(nil as Patient?)
                                ForEach(appState.patients) { patient in
                                    Text(patient.displayName).tag(patient as Patient?)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Quick Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveItem()
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraView { image in
                    capturedImage = image
                }
            }
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPickerView { url in
                    selectedDocumentURL = url
                }
            }
        }
    }
    
    @ViewBuilder
    private var captureContent: some View {
        switch selectedMode {
        case .photo:
            photoCaptureView
        case .pdf:
            pdfCaptureView
        case .audio:
            audioCaptureView
        case .text:
            textCaptureView
        }
    }
    
    // MARK: - Photo Capture
    
    private var photoCaptureView: some View {
        VStack(spacing: 16) {
            if let image = capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            capturedImage = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                        }
                        .padding(8)
                    }
            } else {
                HStack(spacing: 16) {
                    Button {
                        showingCamera = true
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.largeTitle)
                            Text("Take Photo")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.largeTitle)
                            Text("Choose Photo")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            }
        }
        .onChange(of: selectedPhotoItem) { _, newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    capturedImage = image
                }
            }
        }
    }
    
    // MARK: - PDF Capture
    
    private var pdfCaptureView: some View {
        VStack(spacing: 16) {
            if let url = selectedDocumentURL {
                HStack(spacing: 12) {
                    Image(systemName: "doc.fill")
                        .font(.title)
                        .foregroundStyle(.blue)
                    
                    VStack(alignment: .leading) {
                        Text(url.lastPathComponent)
                            .font(.body)
                            .lineLimit(1)
                        Text("PDF Document")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        selectedDocumentURL = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            } else {
                Button {
                    showingDocumentPicker = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.badge.plus")
                            .font(.largeTitle)
                        Text("Choose PDF")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Audio Capture
    
    private var audioCaptureView: some View {
        VStack(spacing: 16) {
            // Waveform visualization placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 100)
                .overlay {
                    if isRecording {
                        HStack(spacing: 4) {
                            ForEach(0..<20, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.red)
                                    .frame(width: 4, height: CGFloat.random(in: 20...60))
                            }
                        }
                    } else {
                        Image(systemName: "waveform")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
            
            // Duration
            Text(formatDuration(recordingDuration))
                .font(.title2.monospacedDigit())
                .foregroundStyle(isRecording ? .red : .secondary)
            
            // Record Button
            Button {
                toggleRecording()
            } label: {
                ZStack {
                    SwiftUI.Circle()
                        .fill(isRecording ? Color.red : Color.blue)
                        .frame(width: 72, height: 72)
                    
                    if isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white)
                            .frame(width: 24, height: 24)
                    } else {
                        SwiftUI.Circle()
                            .fill(.white)
                            .frame(width: 24, height: 24)
                    }
                }
            }
        }
    }
    
    // MARK: - Text Capture
    
    private var textCaptureView: some View {
        VStack(spacing: 16) {
            TextEditor(text: $textContent)
                .frame(minHeight: 150)
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            
            Text("\(textContent.count) characters")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Helpers
    
    private var canSave: Bool {
        switch selectedMode {
        case .photo:
            return capturedImage != nil
        case .pdf:
            return selectedDocumentURL != nil
        case .audio:
            return recordingDuration > 0 && !isRecording
        case .text:
            return !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    
    private func toggleRecording() {
        isRecording.toggle()
        // TODO: Implement actual audio recording
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func saveItem() {
        isSaving = true
        
        // TODO: Upload attachment and create inbox item via API
        let kind: InboxItem.Kind
        switch selectedMode {
        case .photo: kind = .photo
        case .pdf: kind = .pdf
        case .audio: kind = .audio
        case .text: kind = .text
        }
        
        let newItem = InboxItem(
            id: UUID(),
            circleId: UUID(uuidString: appState.currentCircle?.id ?? "") ?? UUID(),
            patientId: (selectedPatient?.id).flatMap { UUID(uuidString: $0) },
            createdBy: UUID(uuidString: appState.currentUser?.id ?? "") ?? UUID(),
            kind: kind,
            status: .new,
            assignedTo: nil,
            title: title.isEmpty ? nil : title,
            note: note.isEmpty ? nil : note,
            attachmentId: nil,
            textPayload: selectedMode == .text ? textContent : nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        onCapture(newItem)
        dismiss()
    }
}

// MARK: - Capture Mode Button

struct CaptureModeButton: View {
    let mode: QuickCaptureView.CaptureMode
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.title2)
                Text(mode.rawValue)
                    .font(.caption)
            }
            .frame(width: 72, height: 64)
            .background(isSelected ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.1))
            .foregroundStyle(isSelected ? .blue : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
    }
}

// MARK: - Camera View

struct CameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        
        init(onCapture: @escaping (UIImage) -> Void) {
            self.onCapture = onCapture
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Document Picker View

struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf])
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        
        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                onPick(url)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    QuickCaptureView { _ in }
        .environmentObject(AppState())
}
