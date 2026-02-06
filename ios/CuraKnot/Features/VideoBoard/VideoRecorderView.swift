import SwiftUI
import AVFoundation

// MARK: - Video Recorder View

struct VideoRecorderView: View {
    @StateObject private var viewModel: VideoRecorderViewModel
    @Environment(\.dismiss) private var dismiss
    
    let onRecordingComplete: (URL) -> Void
    let onCancel: () -> Void
    
    init(
        maxDuration: TimeInterval,
        onRecordingComplete: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: VideoRecorderViewModel(maxDuration: maxDuration))
        self.onRecordingComplete = onRecordingComplete
        self.onCancel = onCancel
    }
    
    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(session: viewModel.captureSession)
                .ignoresSafeArea()
            
            // Overlay controls
            VStack {
                // Top bar
                topBar
                
                Spacer()
                
                // Recording indicator and timer
                if case .recording = viewModel.recordingState {
                    recordingIndicator
                }
                
                // Bottom controls
                bottomControls
            }
        }
        .task {
            do {
                try await viewModel.setupSession()
            } catch {
                // Error handled in viewModel.recordingState
            }
        }
        .onChange(of: viewModel.recordingState) { _, newState in
            if case .stopped(let url) = newState {
                onRecordingComplete(url)
            }
        }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            // Cancel button
            Button {
                viewModel.cancelRecording()
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: SwiftUI.Circle())
            }
            
            Spacer()
            
            // Camera flip button (only in idle state)
            if case .idle = viewModel.recordingState {
                Button {
                    viewModel.flipCamera()
                } label: {
                    Image(systemName: "camera.rotate")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: SwiftUI.Circle())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
    
    // MARK: - Recording Indicator
    
    private var recordingIndicator: some View {
        HStack(spacing: 8) {
            SwiftUI.Circle()
                .fill(.red)
                .frame(width: 12, height: 12)
            
            Text(viewModel.durationFormatted)
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(.white)
            
            Text("/ \(Int(viewModel.maxDuration))s")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 20)
    }
    
    // MARK: - Bottom Controls
    
    private var bottomControls: some View {
        VStack(spacing: 20) {
            // Progress bar (when recording)
            if case .recording = viewModel.recordingState {
                progressBar
            }
            
            // Record button
            recordButton
        }
        .padding(.bottom, 40)
    }
    
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.3))
                    .frame(height: 4)
                
                Capsule()
                    .fill(.red)
                    .frame(width: geometry.size.width * viewModel.progress, height: 4)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 40)
    }
    
    private var recordButton: some View {
        Button {
            switch viewModel.recordingState {
            case .idle:
                viewModel.startRecording()
            case .recording:
                viewModel.stopRecording()
            default:
                break
            }
        } label: {
            recordButtonContent
        }
        .disabled(!canRecord)
    }
    
    @ViewBuilder
    private var recordButtonContent: some View {
        ZStack {
            // Outer ring
            SwiftUI.Circle()
                .stroke(.white, lineWidth: 4)
                .frame(width: 80, height: 80)
            
            // Inner button
            if case .recording = viewModel.recordingState {
                // Stop button (rounded square)
                RoundedRectangle(cornerRadius: 8)
                    .fill(.red)
                    .frame(width: 32, height: 32)
            } else {
                // Record button (circle)
                SwiftUI.Circle()
                    .fill(.red)
                    .frame(width: 64, height: 64)
            }
        }
    }
    
    private var canRecord: Bool {
        switch viewModel.recordingState {
        case .idle, .recording:
            return true
        default:
            return false
        }
    }
}

// MARK: - Camera Preview View

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.session = session
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.session = session
    }
}

final class CameraPreviewUIView: UIView {
    var session: AVCaptureSession? {
        didSet {
            previewLayer.session = session
        }
    }
    
    private var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
    
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspectFill
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}

// MARK: - Error View

extension VideoRecorderView {
    @ViewBuilder
    func errorView(for error: VideoRecorderViewModel.RecorderError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            
            Text(error.localizedDescription ?? "An error occurred")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            
            Button("Go to Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(40)
    }
}