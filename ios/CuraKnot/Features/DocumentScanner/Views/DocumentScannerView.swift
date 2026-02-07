import SwiftUI
import VisionKit
import PhotosUI

// MARK: - Document Scanner View

/// Main view for scanning documents using VisionKit
struct DocumentScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dependencyContainer: DependencyContainer
    @StateObject private var viewModel: DocumentScannerViewModel

    init(circleId: String, patientId: String?) {
        _viewModel = StateObject(wrappedValue: DocumentScannerViewModel(
            circleId: circleId,
            patientId: patientId
        ))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Scan Document")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
                .sheet(isPresented: $viewModel.showingScanner) {
                    DocumentCameraView { result in
                        switch result {
                        case .success(let images):
                            viewModel.capturedImages = images
                        case .failure(let error):
                            viewModel.error = DocumentScanError.uploadFailed(error.localizedDescription)
                        }
                        viewModel.showingScanner = false
                    }
                }
                .sheet(item: $viewModel.scanForReview) { scan in
                    ScanReviewView(
                        scan: scan,
                        onComplete: {
                            viewModel.scanForReview = nil
                            dismiss()
                        }
                    )
                }
                .alert("Error", isPresented: $viewModel.showingError) {
                    Button("OK") {
                        viewModel.showingError = false
                    }
                } message: {
                    Text(viewModel.error?.localizedDescription ?? "An error occurred")
                }
                .alert("Upgrade Required", isPresented: $viewModel.showingUpgradePrompt) {
                    Button("Upgrade") {
                        // TODO: Navigate to subscription screen
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(viewModel.upgradeMessage)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isProcessing {
            processingView
        } else if !viewModel.capturedImages.isEmpty {
            capturedImagesView
        } else {
            initialStateView
        }
    }

    // MARK: - Initial State

    private var initialStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 72))
                .foregroundStyle(.blue)

            // Title
            Text("Scan Any Document")
                .font(.title2)
                .fontWeight(.bold)

            // Description
            Text("Scan prescriptions, lab results, bills, insurance cards, and more. CuraKnot will automatically categorize and file them.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            // Usage info
            if let usage = viewModel.usageInfo {
                HStack {
                    Image(systemName: usage.unlimited == true ? "infinity" : "number.circle")
                        .foregroundStyle(.secondary)
                    Text(usage.usageDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }

            Spacer()

            // Action buttons
            VStack(spacing: 16) {
                // Camera button
                Button {
                    viewModel.showingScanner = true
                } label: {
                    Label("Scan with Camera", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)

                // Photo library button
                PhotosPicker(
                    selection: $viewModel.selectedPhotoItems,
                    maxSelectionCount: 10,
                    matching: .images
                ) {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .onChange(of: viewModel.selectedPhotoItems) { _, items in
            Task {
                await viewModel.loadSelectedPhotos(items)
            }
        }
        .task {
            viewModel.configure(service: dependencyContainer.documentScannerService)
            await viewModel.checkUsageLimit()
        }
    }

    // MARK: - Captured Images View

    private var capturedImagesView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Page count
                Text("\(viewModel.capturedImages.count) page\(viewModel.capturedImages.count == 1 ? "" : "s") captured")
                    .font(.headline)
                    .padding(.top)

                // Image carousel
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.capturedImages.indices, id: \.self) { index in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: viewModel.capturedImages[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .shadow(radius: 2)

                                // Page number
                                Text("\(index + 1)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(SwiftUI.Circle().fill(.black.opacity(0.6)))
                                    .padding(4)

                                // Delete button
                                Button {
                                    viewModel.removeImage(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.white)
                                        .shadow(radius: 2)
                                }
                                .offset(x: 8, y: -8)
                            }
                        }

                        // Add more button
                        Button {
                            viewModel.showingScanner = true
                        } label: {
                            VStack {
                                Image(systemName: "plus")
                                    .font(.largeTitle)
                                Text("Add Page")
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

                // Patient selector (if multiple patients)
                if appState.patients.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Patient")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Picker("Patient", selection: $viewModel.selectedPatientId) {
                            Text("General (no specific patient)").tag(nil as String?)
                            ForEach(appState.patients) { patient in
                                Text(patient.displayName).tag(patient.id as String?)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal)
                }

                Spacer(minLength: 40)

                // Process button
                Button {
                    Task {
                        await viewModel.processScannedImages()
                    }
                } label: {
                    Label("Process Document", systemImage: "wand.and.stars")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                // Clear button
                Button("Clear All", role: .destructive) {
                    viewModel.capturedImages = []
                }
                .padding(.bottom)
            }
        }
    }

    // MARK: - Processing View

    private var processingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text(viewModel.processingStatus)
                .font(.headline)

            Text("This may take a moment")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

// MARK: - Document Scanner ViewModel

@MainActor
class DocumentScannerViewModel: ObservableObject {
    // State
    @Published var capturedImages: [UIImage] = []
    @Published var selectedPhotoItems: [PhotosPickerItem] = []
    @Published var selectedPatientId: String?
    @Published var showingScanner = false
    @Published var isProcessing = false
    @Published var processingStatus = "Uploading..."
    @Published var error: DocumentScanError?
    @Published var showingError = false
    @Published var showingUpgradePrompt = false
    @Published var upgradeMessage = ""
    @Published var usageInfo: ScanUsageInfo?
    @Published var scanForReview: DocumentScan?

    // Configuration
    let circleId: String
    let patientId: String?

    // Dependencies (injected at runtime)
    private var scannerService: DocumentScannerService?

    init(circleId: String, patientId: String?) {
        self.circleId = circleId
        self.patientId = patientId
        self.selectedPatientId = patientId
    }

    func configure(service: DocumentScannerService) {
        self.scannerService = service
    }

    // MARK: - Actions

    func checkUsageLimit() async {
        guard let service = scannerService else { return }

        do {
            usageInfo = try await service.checkUsageLimit(circleId: circleId)
        } catch {
            #if DEBUG
            print("Failed to check usage: \(error)")
            #endif
        }
    }

    func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                capturedImages.append(image)
            }
        }
        selectedPhotoItems = []
    }

    func removeImage(at index: Int) {
        guard capturedImages.indices.contains(index) else { return }
        capturedImages.remove(at: index)
    }

    func processScannedImages() async {
        guard let service = scannerService else {
            error = DocumentScanError.notAuthenticated
            showingError = true
            return
        }

        guard !capturedImages.isEmpty else { return }

        isProcessing = true
        processingStatus = "Uploading images..."

        do {
            // Upload and create scan
            let scan = try await service.processScan(
                images: capturedImages,
                circleId: circleId,
                patientId: selectedPatientId
            )

            processingStatus = "Processing complete"
            isProcessing = false

            // Navigate to review
            scanForReview = scan

        } catch let scanError as DocumentScanError {
            isProcessing = false
            error = scanError

            if case .usageLimitReached = scanError {
                upgradeMessage = scanError.localizedDescription ?? "Upgrade required"
                showingUpgradePrompt = true
            } else if case .tierGate(_, let tier) = scanError {
                upgradeMessage = "Upgrade to \(tier) to access this feature"
                showingUpgradePrompt = true
            } else {
                showingError = true
            }
        } catch {
            isProcessing = false
            self.error = DocumentScanError.uploadFailed(error.localizedDescription)
            showingError = true
        }
    }
}

// MARK: - Document Camera View (VisionKit Wrapper)

struct DocumentCameraView: UIViewControllerRepresentable {
    let onResult: (Result<[UIImage], Error>) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult)
    }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onResult: (Result<[UIImage], Error>) -> Void

        init(onResult: @escaping (Result<[UIImage], Error>) -> Void) {
            self.onResult = onResult
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            var images: [UIImage] = []
            for i in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: i))
            }
            controller.dismiss(animated: true)
            onResult(.success(images))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
            onResult(.success([]))
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            controller.dismiss(animated: true)
            onResult(.failure(error))
        }
    }
}

// MARK: - Preview

#Preview {
    DocumentScannerView(circleId: "test-circle", patientId: nil)
        .environmentObject(AppState())
}
