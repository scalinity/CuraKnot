import SwiftUI
import PDFKit

// MARK: - PDF Preview View

struct PDFPreviewView: View {
    let pdfURL: URL
    @State private var isLoading = true
    @State private var pdfDocument: PDFDocument?
    @State private var loadError: Error?
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading PDF...")
            } else if let document = pdfDocument {
                PDFKitView(document: document)
            } else if let error = loadError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("Failed to load PDF")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            await loadPDF()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if pdfDocument != nil {
                    ShareLink(item: pdfURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
    
    private func loadPDF() async {
        isLoading = true
        
        do {
            if pdfURL.isFileURL {
                // Local file
                if let document = PDFDocument(url: pdfURL) {
                    pdfDocument = document
                } else {
                    loadError = PDFError.invalidDocument
                }
            } else {
                // Remote URL - download first
                let (data, _) = try await URLSession.shared.data(from: pdfURL)
                if let document = PDFDocument(data: data) {
                    pdfDocument = document
                } else {
                    loadError = PDFError.invalidDocument
                }
            }
        } catch {
            loadError = error
        }
        
        isLoading = false
    }
}

// MARK: - PDF Kit View

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = document
        return pdfView
    }
    
    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = document
    }
}

// MARK: - PDF Error

enum PDFError: Error, LocalizedError {
    case invalidDocument
    case downloadFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return "Could not read PDF document"
        case .downloadFailed:
            return "Failed to download PDF"
        }
    }
}

// MARK: - Export Preview View

struct ExportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    
    let exportId: String
    let downloadURL: URL
    
    @State private var isDownloading = false
    @State private var localURL: URL?
    
    var body: some View {
        NavigationStack {
            Group {
                if isDownloading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Downloading PDF...")
                    }
                } else if let url = localURL {
                    PDFPreviewView(pdfURL: url)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.largeTitle)
                        Text("Care Summary Ready")
                            .font(.headline)
                        
                        Button("View PDF") {
                            downloadPDF()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Care Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                if let url = localURL {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .onAppear {
            downloadPDF()
        }
    }
    
    private func downloadPDF() {
        isDownloading = true
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: downloadURL)
                
                // Save to temp file
                let tempDir = FileManager.default.temporaryDirectory
                let fileName = "care_summary_\(exportId).pdf"
                let fileURL = tempDir.appendingPathComponent(fileName)
                
                try data.write(to: fileURL)
                localURL = fileURL
            } catch {
                #if DEBUG
                print("Download failed: \(error)")
                #endif
            }
            
            isDownloading = false
        }
    }
}

#Preview {
    ExportPreviewView(
        exportId: "test",
        downloadURL: URL(string: "https://example.com/test.pdf")!
    )
}
