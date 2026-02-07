import SwiftUI

// MARK: - Scan Review View

/// Review scanned document: confirm classification, edit extracted data, route to destination
struct ScanReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dependencyContainer: DependencyContainer
    @StateObject private var viewModel: ScanReviewViewModel

    let onComplete: () -> Void

    init(scan: DocumentScan, onComplete: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: ScanReviewViewModel(scan: scan))
        self.onComplete = onComplete
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Image preview
                    imagePreviewSection

                    // Classification section
                    classificationSection

                    // Extracted data section (FAMILY tier)
                    if viewModel.hasExtractedData {
                        extractedDataSection
                    }

                    // Routing section
                    routingSection

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("Review Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await viewModel.routeDocument()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.canRoute || viewModel.isProcessing)
                }
            }
            .overlay {
                if viewModel.isProcessing {
                    processingOverlay
                }
            }
            .alert("Error", isPresented: $viewModel.showingError) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorMessage)
            }
            .onChange(of: viewModel.isRouted) { _, isRouted in
                if isRouted {
                    onComplete()
                }
            }
            .task {
                viewModel.configure(service: dependencyContainer.documentScannerService)
            }
        }
    }

    // MARK: - Image Preview

    private var imagePreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Document")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<viewModel.scan.pageCount, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 80, height: 100)
                            .overlay {
                                VStack {
                                    Image(systemName: "doc.fill")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                    Text("Page \(index + 1)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                    }
                }
            }
        }
    }

    // MARK: - Classification Section

    private var classificationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Document Type")
                    .font(.headline)

                Spacer()

                if let source = viewModel.scan.classificationSource {
                    HStack(spacing: 4) {
                        Image(systemName: source == .ai ? "sparkles" : "hand.tap")
                            .font(.caption2)
                        Text(source.displayName)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.1))
                    )
                }
            }

            if let confidence = viewModel.scan.confidencePercentage, viewModel.scan.classificationSource == .ai {
                HStack {
                    Text("Confidence: \(confidence)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if confidence < 80 {
                        Text("• Please verify")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            // Type picker
            Menu {
                ForEach(DocumentType.allCases) { type in
                    Button {
                        viewModel.selectedDocumentType = type
                    } label: {
                        Label(type.displayName, systemImage: type.icon)
                    }
                }
            } label: {
                HStack {
                    if let type = viewModel.selectedDocumentType {
                        Image(systemName: type.icon)
                            .foregroundStyle(.blue)
                            .frame(width: 30)
                        Text(type.displayName)
                    } else {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                            .frame(width: 30)
                        Text("Select document type")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Extracted Data Section

    private var extractedDataSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Extracted Data")
                    .font(.headline)

                Spacer()

                if let confidence = viewModel.scan.extractionConfidence {
                    Text("\(Int(confidence * 100))% confident")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let fields = viewModel.extractedFieldsForDisplay {
                VStack(spacing: 0) {
                    ForEach(fields, id: \.key) { field in
                        extractedFieldRow(field)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
            }
        }
    }

    private func extractedFieldRow(_ field: (key: String, value: String)) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(formatFieldKey(field.key))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)

                Text(field.value)
                    .font(.subheadline)

                Spacer()

                Button {
                    // TODO: Edit field
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            Divider()
                .padding(.leading)
        }
    }

    private func formatFieldKey(_ key: String) -> String {
        // Convert camelCase to Title Case
        let result = key.replacingOccurrences(
            of: "([a-z])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        )
        return result.prefix(1).uppercased() + result.dropFirst()
    }

    // MARK: - Routing Section

    private var routingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save To")
                .font(.headline)

            // Routing options
            VStack(spacing: 8) {
                ForEach(RoutingTarget.allCases, id: \.self) { target in
                    routingOptionButton(target)
                }
            }
        }
    }

    private func routingOptionButton(_ target: RoutingTarget) -> some View {
        Button {
            viewModel.selectedRoutingTarget = target
        } label: {
            HStack {
                Image(systemName: target.icon)
                    .foregroundStyle(viewModel.selectedRoutingTarget == target ? .white : .blue)
                    .frame(width: 30)

                VStack(alignment: .leading) {
                    Text(target.displayName)
                        .fontWeight(.medium)
                    Text(targetDescription(target))
                        .font(.caption)
                        .foregroundStyle(viewModel.selectedRoutingTarget == target ? .white.opacity(0.8) : .secondary)
                }

                Spacer()

                if viewModel.selectedRoutingTarget == target {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }
            .padding()
            .foregroundStyle(viewModel.selectedRoutingTarget == target ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(viewModel.selectedRoutingTarget == target ? Color.blue : Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    private func targetDescription(_ target: RoutingTarget) -> String {
        switch target {
        case .binder:
            return "Add to medications, contacts, or documents"
        case .billing:
            return "Track bills, claims, and EOBs"
        case .handoff:
            return "Create a handoff note for the care circle"
        case .inbox:
            return "Save for later review and triage"
        }
    }

    // MARK: - Processing Overlay

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)

                Text(viewModel.processingStatus)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground).opacity(0.9))
            )
        }
    }
}

// MARK: - Scan Review ViewModel

@MainActor
class ScanReviewViewModel: ObservableObject {
    // State
    @Published var scan: DocumentScan
    @Published var selectedDocumentType: DocumentType?
    @Published var selectedRoutingTarget: RoutingTarget
    @Published var isProcessing = false
    @Published var processingStatus = "Processing..."
    @Published var showingError = false
    @Published var errorMessage = ""
    @Published var isRouted = false

    // Dependencies
    private var scannerService: DocumentScannerService?

    init(scan: DocumentScan) {
        self.scan = scan
        self.selectedDocumentType = scan.documentType
        self.selectedRoutingTarget = scan.documentType?.defaultRoutingTarget ?? .inbox
    }

    func configure(service: DocumentScannerService) {
        self.scannerService = service
    }

    // MARK: - Computed Properties

    var canRoute: Bool {
        selectedDocumentType != nil
    }

    var hasExtractedData: Bool {
        scan.hasExtractedData
    }

    var extractedFieldsForDisplay: [(key: String, value: String)]? {
        guard let fields = scan.extractedFields else { return nil }

        return fields.compactMap { key, value -> (String, String)? in
            guard let stringValue = formatValue(value) else { return nil }
            return (key, stringValue)
        }.sorted { $0.0 < $1.0 }
    }

    private func formatValue(_ value: Any?) -> String? {
        guard let value = value else { return nil }

        if let string = value as? String, !string.isEmpty {
            return string
        } else if let number = value as? NSNumber {
            return number.stringValue
        } else if let array = value as? [String] {
            return array.joined(separator: ", ")
        }
        return nil
    }

    // MARK: - Actions

    func routeDocument() async {
        guard let service = scannerService,
              let docType = selectedDocumentType else { return }

        isProcessing = true

        do {
            // Classify if needed (manual override)
            if scan.documentType != docType {
                processingStatus = "Classifying..."
                _ = try await service.classifyDocument(
                    scanId: scan.id,
                    overrideType: docType
                )
            }

            // Route to destination
            processingStatus = "Saving to \(selectedRoutingTarget.displayName)..."
            _ = try await service.routeDocument(
                scanId: scan.id,
                targetType: selectedRoutingTarget,
                binderItemType: docType.binderItemType
            )

            isProcessing = false
            isRouted = true

        } catch {
            isProcessing = false
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - Preview

#Preview {
    ScanReviewView(
        scan: DocumentScan(
            id: "test",
            circleId: "circle",
            patientId: nil,
            createdBy: "user",
            storageKeys: ["test/page1.jpg"],
            pageCount: 1,
            ocrText: "Sample OCR text",
            ocrConfidence: 0.95,
            ocrProvider: .vision,
            documentType: .prescription,
            classificationConfidence: 0.87,
            classificationSource: .ai,
            extractedFieldsJson: nil,
            extractionConfidence: nil,
            routedToType: nil,
            routedToId: nil,
            routedAt: nil,
            routedBy: nil,
            status: .ready,
            errorMessage: nil,
            createdAt: Date(),
            updatedAt: Date()
        ),
        onComplete: {}
    )
    .environmentObject(AppState())
}
