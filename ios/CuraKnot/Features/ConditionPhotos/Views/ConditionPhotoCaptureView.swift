import SwiftUI
import AVFoundation

// MARK: - Condition Photo Capture View

struct ConditionPhotoCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (Data, String?, LightingQuality?) async -> Void

    @State private var capturedImage: UIImage?
    @State private var notes = ""
    @State private var lightingQuality: LightingQuality?
    @State private var isSaving = false
    @State private var showingCamera = true
    @State private var cameraError: String?
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            if showingCamera && capturedImage == nil {
                cameraView
            } else if let image = capturedImage {
                reviewView(image: image)
            } else {
                cameraUnavailableView
            }
        }
        .onDisappear {
            saveTask?.cancel()
        }
    }

    // MARK: - Camera View

    private var cameraView: some View {
        ZStack {
            CameraPreviewWrapper { image in
                capturedImage = image
            } onError: { error in
                cameraError = error
                showingCamera = false
            }
            .ignoresSafeArea()

            VStack {
                Spacer()

                // Guide frame overlay
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 280, height: 280)
                    .overlay(alignment: .bottom) {
                        Text("Center the affected area")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.5))
                            .clipShape(Capsule())
                            .offset(y: 30)
                    }

                Spacer()

                // Bottom controls
                HStack(spacing: 40) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white)

                    Spacer()

                    // Lighting indicator
                    if let quality = lightingQuality {
                        Label(quality.displayName, systemImage: quality.icon)
                            .font(.caption)
                            .foregroundStyle(lightingColor(quality))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Review View

    private func reviewView(image: UIImage) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Photo preview
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                // Lighting quality selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lighting Quality")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: 12) {
                        ForEach(LightingQuality.allCases, id: \.self) { quality in
                            Button {
                                lightingQuality = quality
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: quality.icon)
                                        .font(.title3)
                                    Text(quality.displayName)
                                        .font(.caption2)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(lightingQuality == quality ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.08))
                                .foregroundStyle(lightingQuality == quality ? .blue : .secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)

                // Notes
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes (optional)")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    TextField("What changed? Any observations?", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Review Photo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Retake") {
                    capturedImage = nil
                    showingCamera = true
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    isSaving = true
                    saveTask = Task {
                        if let data = image.jpegData(compressionQuality: 0.9) {
                            await onCapture(
                                data,
                                notes.isEmpty ? nil : notes,
                                lightingQuality
                            )
                        }
                        isSaving = false
                    }
                }
                .disabled(isSaving)
            }
        }
    }

    // MARK: - Camera Unavailable

    private var cameraUnavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Camera Unavailable")
                .font(.headline)

            if let error = cameraError {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Please allow camera access in Settings to take condition photos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .navigationTitle("Camera")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func lightingColor(_ quality: LightingQuality) -> Color {
        switch quality {
        case .good: return .green
        case .fair: return .yellow
        case .poor: return .red
        }
    }
}

// MARK: - Camera Preview Wrapper (UIKit bridge)

struct CameraPreviewWrapper: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.onCapture = onCapture
        controller.onError = onError
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

// MARK: - Camera View Controller

final class CameraViewController: UIViewController {
    var onCapture: ((UIImage) -> Void)?
    var onError: ((String) -> Void)?

    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let sessionQueue = DispatchQueue(label: "com.curaknot.camera.session")
    private var isSessionStopped = false

    override func viewDidLoad() {
        super.viewDidLoad()
        checkPermissionAndSetup()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSessionSafely()
    }

    deinit {
        stopSessionSafely()
    }

    private func stopSessionSafely() {
        let session = captureSession
        sessionQueue.async { [weak self] in
            guard let self, !self.isSessionStopped else { return }
            self.isSessionStopped = true
            session?.stopRunning()
        }
    }

    private func checkPermissionAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCamera()
                    } else {
                        self?.onError?("Camera access denied.")
                    }
                }
            }
        default:
            onError?("Camera access denied. Enable it in Settings.")
        }
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            onError?("Camera not available on this device.")
            return
        }

        guard session.canAddInput(input) else {
            onError?("Cannot add camera input.")
            return
        }
        session.addInput(input)

        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else {
            onError?("Cannot add photo output.")
            return
        }
        session.addOutput(output)
        photoOutput = output

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview

        captureSession = session

        // Add capture button
        let captureButton = UIButton(type: .system)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.backgroundColor = .white
        captureButton.layer.cornerRadius = 35
        captureButton.layer.borderWidth = 4
        captureButton.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        captureButton.accessibilityLabel = "Take Photo"
        captureButton.accessibilityHint = "Captures a photo of the condition"
        view.addSubview(captureButton)

        NSLayoutConstraint.activate([
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -50),
            captureButton.widthAnchor.constraint(equalToConstant: 70),
            captureButton.heightAnchor.constraint(equalToConstant: 70),
        ])

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    @objc private func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        photoOutput?.capturePhoto(with: settings, delegate: self)
    }
}

extension CameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            DispatchQueue.main.async { [weak self] in
                self?.onError?("Failed to capture photo.")
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.onCapture?(image)
        }
    }
}
