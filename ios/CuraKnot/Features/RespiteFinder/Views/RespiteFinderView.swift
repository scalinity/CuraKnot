import SwiftUI

// MARK: - Respite Finder View

struct RespiteFinderView: View {
    @StateObject private var viewModel: RespiteFinderViewModel
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var dependencyContainer: DependencyContainer

    init(service: RespiteFinderService) {
        _viewModel = StateObject(wrappedValue: RespiteFinderViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search & Filter Bar
                searchBar

                if let error = viewModel.locationError {
                    locationBanner(error)
                }

                // Content
                if viewModel.isSearching && viewModel.service.providers.isEmpty {
                    loadingView
                } else if viewModel.service.providers.isEmpty && viewModel.errorMessage == nil {
                    emptyStateView
                } else if let error = viewModel.errorMessage, viewModel.service.providers.isEmpty {
                    errorView(error)
                } else {
                    providerList
                }
            }
            .navigationTitle(String(localized: "Respite Care"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if viewModel.service.canSubmitRequests {
                            Button {
                                viewModel.showHistoryView = true
                            } label: {
                                Label(String(localized: "My Requests"), systemImage: "list.bullet.clipboard")
                            }
                        }

                        if viewModel.service.canTrackRespite {
                            Button {
                                viewModel.showHistoryView = true
                            } label: {
                                Label(String(localized: "Respite History"), systemImage: "calendar.badge.clock")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $viewModel.showFilters) {
                FilterSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showProviderDetail) {
                if let provider = viewModel.selectedProvider {
                    ProviderDetailView(
                        provider: provider,
                        service: viewModel.service,
                        circleId: appState.currentCircleId,
                        patientId: appState.currentPatientId
                    )
                }
            }
            .sheet(isPresented: $viewModel.showRequestSheet) {
                if let provider = viewModel.selectedProvider,
                   let circleId = appState.currentCircleId,
                   let patientId = appState.currentPatientId {
                    RespiteRequestSheet(
                        service: viewModel.service,
                        provider: provider,
                        circleId: circleId,
                        patientId: patientId
                    )
                }
            }
            .sheet(isPresented: $viewModel.showHistoryView) {
                if let circleId = appState.currentCircleId {
                    RespiteHistoryView(service: viewModel.service, circleId: circleId, patientId: appState.currentPatientId)
                }
            }
            .task {
                viewModel.requestLocation()
                await viewModel.performSearch()
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(String(localized: "Nearby Providers"))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button {
                viewModel.showFilters = true
            } label: {
                Image(systemName: viewModel.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.title3)
            }
            .accessibilityLabel(String(localized: "Filters"))
            .accessibilityHint(viewModel.hasActiveFilters ? String(localized: "Active filters applied") : String(localized: "No filters applied"))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Location Banner

    private func locationBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "location.slash")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(String(localized: "Finding nearby providers..."))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "heart.text.clipboard")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(String(localized: "No Providers Found"))
                .font(.headline)
            Text(String(localized: "Try expanding your search radius or adjusting filters."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(String(localized: "Search Again")) {
                Task { await viewModel.performSearch() }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(String(localized: "Retry")) {
                Task { await viewModel.performSearch() }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
    }

    // MARK: - Provider List

    private var providerList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.service.providers) { provider in
                    ProviderCard(provider: provider) {
                        viewModel.selectProvider(provider)
                    }
                }

                if viewModel.service.hasMore && !viewModel.isSearching {
                    Button(String(localized: "Load More")) {
                        Task { await viewModel.loadMore() }
                    }
                    .buttonStyle(.bordered)
                    .padding()
                }

                if viewModel.isSearching {
                    ProgressView()
                        .padding()
                }
            }
            .padding()
        }
        .refreshable {
            await viewModel.performSearch()
        }
    }
}

// MARK: - Filter Sheet

private struct FilterSheet: View {
    @ObservedObject var viewModel: RespiteFinderViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Provider Type")) {
                    Picker(String(localized: "Type"), selection: $viewModel.selectedType) {
                        Text(String(localized: "All Types")).tag(RespiteProvider.ProviderType?.none)
                        ForEach(RespiteProvider.ProviderType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(RespiteProvider.ProviderType?.some(type))
                        }
                    }
                }

                Section(String(localized: "Search Radius")) {
                    HStack {
                        Slider(value: $viewModel.radiusMiles, in: 5...200, step: 5)
                        Text("\(Int(viewModel.radiusMiles)) mi")
                            .frame(width: 50, alignment: .trailing)
                            .monospacedDigit()
                    }
                }

                Section(String(localized: "Minimum Rating")) {
                    HStack {
                        RatingStars(rating: Int(viewModel.minRating), maxRating: 5, size: 20) { rating in
                            viewModel.minRating = Double(rating)
                        }
                        Spacer()
                        if viewModel.minRating > 0 {
                            Button(String(localized: "Clear")) {
                                viewModel.minRating = 0
                            }
                            .font(.caption)
                        }
                    }
                }

                Section(String(localized: "Budget (Max Price)")) {
                    HStack {
                        Slider(value: $viewModel.maxPrice, in: 0...500, step: 25)
                        if viewModel.maxPrice > 0 {
                            Text("$\(Int(viewModel.maxPrice))")
                                .frame(width: 50, alignment: .trailing)
                                .monospacedDigit()
                        } else {
                            Text(String(localized: "Any"))
                                .frame(width: 50, alignment: .trailing)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(String(localized: "Other")) {
                    Toggle(String(localized: "Verified Providers Only"), isOn: $viewModel.verifiedOnly)
                }

                Section(String(localized: "Services")) {
                    ForEach(RespiteFinderViewModel.commonServices, id: \.self) { svc in
                        Button {
                            if viewModel.selectedServices.contains(svc) {
                                viewModel.selectedServices.remove(svc)
                            } else {
                                viewModel.selectedServices.insert(svc)
                            }
                        } label: {
                            HStack {
                                Text(svc)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if viewModel.selectedServices.contains(svc) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Filters"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Reset")) {
                        viewModel.clearFilters()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Apply")) {
                        dismiss()
                        Task { await viewModel.performSearch() }
                    }
                    .bold()
                }
            }
        }
    }
}
