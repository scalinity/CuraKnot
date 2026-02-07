import SwiftUI

// MARK: - Financial Resources View

struct FinancialResourcesView: View {
    @StateObject private var viewModel: FinancialResourcesViewModel
    @State private var showingExternalURLConfirmation = false
    @State private var pendingURL: URL?

    init(careCostService: CareCostService) {
        _viewModel = StateObject(wrappedValue: FinancialResourcesViewModel(
            careCostService: careCostService
        ))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Loading resources...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error:
                errorView
            case .loaded:
                if viewModel.resources.isEmpty {
                    emptyView
                } else {
                    loadedView
                }
            }
        }
        .navigationTitle("Financial Resources")
        .navigationBarTitleDisplayMode(.large)
        .task { await viewModel.load() }
        .confirmationDialog(
            "Open External Link",
            isPresented: $showingExternalURLConfirmation,
            titleVisibility: .visible
        ) {
            if let url = pendingURL {
                Button("Open in Browser") {
                    UIApplication.shared.open(url)
                }
                Button("Cancel", role: .cancel) {
                    pendingURL = nil
                }
            }
        } message: {
            Text("This will open an external website. CuraKnot is not responsible for the content of external sites.")
        }
    }

    // MARK: - Loaded Content

    private var loadedView: some View {
        List {
            categoryFilterSection

            ForEach(viewModel.groupedResources, id: \.category) { group in
                Section(group.category.displayName) {
                    ForEach(group.resources) { resource in
                        ResourceCard(resource: resource) {
                            if let url = resource.resourceURL {
                                pendingURL = url
                                showingExternalURLConfirmation = true
                            }
                        }
                    }
                }
            }

            Section {
                FinancialDisclaimerView()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Category Filter

    private var categoryFilterSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(
                        title: "All",
                        isSelected: viewModel.selectedCategory == nil
                    ) {
                        viewModel.selectedCategory = nil
                    }

                    ForEach(ResourceCategory.allCases, id: \.self) { category in
                        FilterChip(
                            title: category.displayName,
                            isSelected: viewModel.selectedCategory == category
                        ) {
                            viewModel.selectedCategory = category
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
    }

    // MARK: - Empty View

    private var emptyView: some View {
        EmptyStateView(
            icon: "book.closed",
            title: "No Resources Available",
            message: "Financial assistance resources will appear here when available."
        )
    }

    // MARK: - Error View

    private var errorView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            Text("Unable to Load Resources")
                .font(.headline)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button("Try Again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) category filter")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FinancialResourcesView(careCostService: CareCostService.preview)
    }
}
