import SwiftUI
import PhotosUI

// MARK: - Med Scan Session Model

struct MedScanSession: Identifiable, Codable {
    let id: UUID
    let circleId: UUID
    let patientId: UUID
    let createdBy: UUID
    var status: Status
    var sourceObjectKeys: [String]
    let createdAt: Date
    var updatedAt: Date
    
    enum Status: String, Codable {
        case pending = "PENDING"
        case processing = "PROCESSING"
        case ready = "READY"
        case failed = "FAILED"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case patientId = "patient_id"
        case createdBy = "created_by"
        case status
        case sourceObjectKeys = "source_object_keys"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct MedProposal: Identifiable, Codable {
    let id: UUID
    let sessionId: UUID
    let circleId: UUID
    let patientId: UUID
    var proposedJson: ProposedMed
    var diffJson: DiffInfo?
    var status: Status
    var existingMedId: UUID?
    var acceptedBy: UUID?
    var acceptedAt: Date?
    let createdAt: Date
    
    struct ProposedMed: Codable {
        var name: String?
        var dose: String?
        var schedule: String?
        var purpose: String?
        var prescriber: String?
        var confidence: Confidence?
        
        struct Confidence: Codable {
            var name: Double?
            var dose: Double?
            var schedule: Double?
        }
    }
    
    struct DiffInfo: Codable {
        var hasMatch: Bool?
        var existingId: UUID?
        var existingTitle: String?
        var doseChanged: Bool?
        var scheduleChanged: Bool?
        var isNew: Bool?
        
        enum CodingKeys: String, CodingKey {
            case hasMatch = "has_match"
            case existingId = "existing_id"
            case existingTitle = "existing_title"
            case doseChanged = "dose_changed"
            case scheduleChanged = "schedule_changed"
            case isNew = "is_new"
        }
    }
    
    enum Status: String, Codable {
        case proposed = "PROPOSED"
        case accepted = "ACCEPTED"
        case rejected = "REJECTED"
        case merged = "MERGED"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case circleId = "circle_id"
        case patientId = "patient_id"
        case proposedJson = "proposed_json"
        case diffJson = "diff_json"
        case status
        case existingMedId = "existing_med_id"
        case acceptedBy = "accepted_by"
        case acceptedAt = "accepted_at"
        case createdAt = "created_at"
    }
}

// MARK: - Med Scan View

struct MedScanView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var selectedPatient: Patient?
    @State private var capturedImages: [UIImage] = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isScanning = false
    @State private var scanSession: MedScanSession?
    @State private var proposals: [MedProposal] = []
    @State private var showingCamera = false
    @State private var showingReview = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Patient Selector
                if appState.patients.count > 1 {
                    Picker("Patient", selection: $selectedPatient) {
                        Text("Select Patient").tag(nil as Patient?)
                        ForEach(appState.patients) { patient in
                            Text(patient.displayName).tag(patient as Patient?)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding()
                }
                
                if isScanning {
                    // Scanning Progress
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        
                        Text("Scanning medications...")
                            .font(.headline)
                        
                        Text("This may take a moment")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if !capturedImages.isEmpty {
                    // Captured Images Preview
                    ScrollView {
                        VStack(spacing: 16) {
                            Text("\(capturedImages.count) image(s) captured")
                                .font(.headline)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(capturedImages.indices, id: \.self) { index in
                                        Image(uiImage: capturedImages[index])
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 120, height: 160)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(alignment: .topTrailing) {
                                                Button {
                                                    capturedImages.remove(at: index)
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundStyle(.white)
                                                        .shadow(radius: 2)
                                                }
                                                .padding(4)
                                            }
                                    }
                                    
                                    // Add more button
                                    Button {
                                        showingCamera = true
                                    } label: {
                                        VStack {
                                            Image(systemName: "plus")
                                                .font(.largeTitle)
                                            Text("Add More")
                                                .font(.caption)
                                        }
                                        .frame(width: 120, height: 160)
                                        .background(Color.secondary.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal)
                            }
                            
                            // Scan Button
                            Button {
                                startScan()
                            } label: {
                                Text("Scan for Medications")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.horizontal)
                            
                            // Instructions
                            VStack(alignment: .leading, spacing: 8) {
                                InstructionRow(icon: "checkmark.circle", text: "Capture pill bottle labels or prescription printouts")
                                InstructionRow(icon: "checkmark.circle", text: "Ensure text is clearly visible and in focus")
                                InstructionRow(icon: "checkmark.circle", text: "Multiple images can be scanned together")
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                        }
                        .padding(.vertical)
                    }
                } else {
                    // Initial State - Capture Options
                    VStack(spacing: 24) {
                        Image(systemName: "pills.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)
                        
                        Text("Medication Reconciliation")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Scan medication labels to update your binder")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        
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
                                .frame(height: 100)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            
                            PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 10, matching: .images) {
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.on.rectangle")
                                        .font(.largeTitle)
                                    Text("Choose Photos")
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 100)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .foregroundStyle(.blue)
                        .padding(.horizontal)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .navigationTitle("Scan Medications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingCamera) {
                MedCameraView { image in
                    capturedImages.append(image)
                }
            }
            .sheet(isPresented: $showingReview) {
                MedProposalReviewView(proposals: proposals) { updatedProposals in
                    // Handle completed reconciliation
                    dismiss()
                }
            }
            .onChange(of: selectedPhotoItems) { _, items in
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            capturedImages.append(image)
                        }
                    }
                    selectedPhotoItems = []
                }
            }
            .onAppear {
                selectedPatient = appState.patients.first
            }
        }
    }
    
    private func startScan() {
        guard let patient = selectedPatient else { return }
        isScanning = true
        
        // TODO: Upload images and call ocr-med-scan edge function
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isScanning = false
            
            // Mock proposals
            proposals = [
                MedProposal(
                    id: UUID(),
                    sessionId: UUID(),
                    circleId: UUID(uuidString: appState.currentCircle?.id ?? "") ?? UUID(),
                    patientId: UUID(uuidString: patient.id) ?? UUID(),
                    proposedJson: MedProposal.ProposedMed(
                        name: "Lisinopril",
                        dose: "10mg",
                        schedule: "Once daily",
                        confidence: MedProposal.ProposedMed.Confidence(name: 0.95, dose: 0.9, schedule: 0.85)
                    ),
                    diffJson: MedProposal.DiffInfo(hasMatch: false, isNew: true),
                    status: .proposed,
                    createdAt: Date()
                ),
                MedProposal(
                    id: UUID(),
                    sessionId: UUID(),
                    circleId: UUID(uuidString: appState.currentCircle?.id ?? "") ?? UUID(),
                    patientId: UUID(uuidString: patient.id) ?? UUID(),
                    proposedJson: MedProposal.ProposedMed(
                        name: "Metformin",
                        dose: "500mg",
                        schedule: "Twice daily with meals",
                        confidence: MedProposal.ProposedMed.Confidence(name: 0.92, dose: 0.88, schedule: 0.82)
                    ),
                    diffJson: MedProposal.DiffInfo(hasMatch: true, existingTitle: "Metformin HCL", doseChanged: true),
                    status: .proposed,
                    createdAt: Date()
                )
            ]
            
            showingReview = true
        }
    }
}

// MARK: - Instruction Row

struct InstructionRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.green)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Med Camera View

struct MedCameraView: UIViewControllerRepresentable {
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

// MARK: - Preview

#Preview {
    MedScanView()
        .environmentObject(AppState())
}
