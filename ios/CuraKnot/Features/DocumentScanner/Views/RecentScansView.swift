import SwiftUI

// MARK: - Recent Scans View

/// List of recent document scans with filtering and status
struct RecentScansView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dependencyContainer: DependencyContainer
    @StateObject private var viewModel: RecentScansViewModel

    init(circleId: String) {
        _viewModel = StateObject(wrappedValue: RecentScansViewModel(circleId: circleId))
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.scans.isEmpty {
                loadingView
            } else if viewModel.scans.isEmpty {
                emptyStateView
            } else {
                scansList
            }
        }
        .navigationTitle("Scanned Documents")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(ScanFilter.allCases, id: \.self) { filter in
                        Button {
                            viewModel.selectedFilter = filter
                        } label: {
                            Label(filter.displayName, systemImage: filter.icon)
                        }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            viewModel.configure(service: dependencyContainer.documentScannerService)
            await viewModel.loadScans()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading scans...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Scanned Documents", systemImage: "doc.text.viewfinder")
        } description: {
            Text("Documents you scan will appear here. Tap the + button to scan your first document.")
        }
    }

    // MARK: - Scans List

    private var scansList: some View {
        List {
            if viewModel.selectedFilter != .all {
                Section {
                    HStack {
                        Text("Showing: \(viewModel.selectedFilter.displayName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear") {
                            viewModel.selectedFilter = .all
                        }
                        .font(.subheadline)
                    }
                }
            }

            ForEach(viewModel.filteredScans) { scan in
                ScanRow(scan: scan)
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Scan Row

private struct ScanRow: View {
    let scan: DocumentScan

    var body: some View {
        HStack(spacing: 12) {
            // Document type icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(typeColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: scan.documentType?.icon ?? "doc.fill")
                    .font(.title3)
                    .foregroundStyle(typeColor)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(scan.documentType?.displayName ?? "Unclassified")
                        .font(.headline)

                    if scan.status == .pending || scan.status == .processing {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }

                HStack(spacing: 4) {
                    Text("\(scan.pageCount) page\(scan.pageCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .foregroundStyle(.secondary)

                    Text(scan.createdAt.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Status indicator
                if scan.status == .failed {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text("Processing failed")
                            .font(.caption)
                    }
                    .foregroundStyle(.red)
                } else if let routedTo = scan.routedToType {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                        Text("Saved to \(routedTo.displayName)")
                            .font(.caption)
                    }
                    .foregroundStyle(.green)
                }
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var typeColor: Color {
        guard let type = scan.documentType else { return .gray }
        switch type {
        case .prescription, .labResult, .medicationList:
            return .blue
        case .insuranceCard, .eob, .bill:
            return .green
        case .discharge:
            return .purple
        case .appointment:
            return .orange
        case .other:
            return .gray
        }
    }
}

// MARK: - Recent Scans ViewModel

@MainActor
class RecentScansViewModel: ObservableObject {
    @Published var scans: [DocumentScan] = []
    @Published var isLoading = false
    @Published var selectedFilter: ScanFilter = .all

    let circleId: String
    private var scannerService: DocumentScannerService?

    init(circleId: String) {
        self.circleId = circleId
    }

    func configure(service: DocumentScannerService) {
        self.scannerService = service
    }

    var filteredScans: [DocumentScan] {
        switch selectedFilter {
        case .all:
            return scans
        case .pending:
            return scans.filter { $0.status == .pending || $0.status == .processing }
        case .routed:
            return scans.filter { $0.status == .routed }
        case .failed:
            return scans.filter { $0.status == .failed }
        }
    }

    func loadScans() async {
        guard let service = scannerService else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            scans = try await service.fetchRecentScans(circleId: circleId)
        } catch {
            #if DEBUG
            print("Failed to load scans: \(error)")
            #endif
        }
    }

    func refresh() async {
        await loadScans()
    }
}

// MARK: - Scan Filter

enum ScanFilter: String, CaseIterable {
    case all
    case pending
    case routed
    case failed

    var displayName: String {
        switch self {
        case .all: return "All"
        case .pending: return "Processing"
        case .routed: return "Filed"
        case .failed: return "Failed"
        }
    }

    var icon: String {
        switch self {
        case .all: return "doc.on.doc"
        case .pending: return "clock"
        case .routed: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        RecentScansView(circleId: "test-circle")
            .environmentObject(AppState())
    }
}
