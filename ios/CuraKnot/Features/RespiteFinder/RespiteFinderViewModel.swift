import Foundation
import CoreLocation
import OSLog
import SwiftUI

// MARK: - Respite Finder View Model

@MainActor
final class RespiteFinderViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    let service: RespiteFinderService

    private let logger = Logger(subsystem: "com.curaknot", category: "RespiteFinderVM")
    private let locationManager = CLLocationManager()
    private var searchTask: Task<Void, Never>?

    // Default fallback when location services unavailable (San Francisco)
    private static let defaultFallbackLocation = (latitude: 37.7749, longitude: -122.4194)

    // MARK: - Published State

    @Published var searchQuery = ""
    @Published var selectedType: RespiteProvider.ProviderType?
    @Published var radiusMiles: Double = 25
    @Published var minRating: Double = 0
    @Published var maxPrice: Double = 0
    @Published var verifiedOnly = false
    @Published var selectedServices: Set<String> = []

    @Published var userLatitude: Double?
    @Published var userLongitude: Double?
    @Published var locationError: String?

    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var showFilters = false
    @Published var selectedProvider: RespiteProvider?
    @Published var showProviderDetail = false
    @Published var showRequestSheet = false
    @Published var showHistoryView = false

    private var currentOffset = 0
    private let pageSize = 20

    // MARK: - Init

    init(service: RespiteFinderService) {
        self.service = service
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    deinit {
        searchTask?.cancel()
    }

    // MARK: - Location

    func requestLocation() {
        let status = locationManager.authorizationStatus

        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            // Use cached location optimistically if available, delegate will update
            if let location = locationManager.location {
                updateLocation(location)
            } else {
                applyFallbackLocation(error: String(localized: "Requesting location permission. Using default location."))
            }
        case .authorizedWhenInUse, .authorizedAlways:
            if let location = locationManager.location {
                updateLocation(location)
            } else {
                locationManager.requestLocation()
                applyFallbackLocation(error: String(localized: "Acquiring location. Using default location temporarily."))
            }
        case .denied, .restricted:
            applyFallbackLocation(error: String(localized: "Location access denied. Using default location."))
        @unknown default:
            applyFallbackLocation(error: String(localized: "Location unavailable. Using default location."))
        }
    }

    private func updateLocation(_ location: CLLocation) {
        userLatitude = location.coordinate.latitude
        userLongitude = location.coordinate.longitude
        locationError = nil
    }

    private func applyFallbackLocation(error: String) {
        userLatitude = Self.defaultFallbackLocation.latitude
        userLongitude = Self.defaultFallbackLocation.longitude
        locationError = error
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            updateLocation(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if userLatitude == nil || userLongitude == nil {
                applyFallbackLocation(error: String(localized: "Failed to get location. Using default location."))
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                applyFallbackLocation(error: String(localized: "Location access denied. Using default location."))
            default:
                break
            }
        }
    }

    // MARK: - Search

    func performSearch() async {
        // Cancel any in-flight search to prevent race conditions
        searchTask?.cancel()

        // Request location if not yet available (sets fallback coordinates synchronously)
        if userLatitude == nil || userLongitude == nil {
            requestLocation()
        }

        guard let lat = userLatitude, let lng = userLongitude else {
            errorMessage = String(localized: "Location not available. Please enable location services and try again.")
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.doSearch(latitude: lat, longitude: lng, offset: 0)
        }
        searchTask = task
        await task.value
    }

    func loadMore() async {
        guard service.hasMore, !isSearching, let lat = userLatitude, let lng = userLongitude else { return }
        searchTask?.cancel()
        let nextOffset = currentOffset + pageSize
        let task = Task { [weak self] in
            guard let self else { return }
            await self.doSearch(latitude: lat, longitude: lng, offset: nextOffset)
        }
        searchTask = task
        await task.value
    }

    private func doSearch(latitude: Double, longitude: Double, offset: Int) async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            try Task.checkCancellation()

            try await service.searchProviders(
                latitude: latitude,
                longitude: longitude,
                radiusMiles: radiusMiles,
                providerType: selectedType,
                services: selectedServices.isEmpty ? nil : Array(selectedServices),
                minRating: minRating > 0 ? minRating : nil,
                maxPrice: maxPrice > 0 ? maxPrice : nil,
                verifiedOnly: verifiedOnly,
                limit: pageSize,
                offset: offset
            )

            try Task.checkCancellation()

            // Only update offset after successful fetch to avoid skipping pages on retry
            currentOffset = offset

            // VoiceOver announcement for search results
            let count = service.providers.count
            let message: String
            if count == 0 {
                message = String(localized: "No providers found")
            } else if count == 1 {
                message = String(localized: "1 provider found")
            } else {
                message = String(localized: "\(count) providers found")
            }
            AccessibilityNotification.Announcement(message).post()
        } catch is CancellationError {
            // Silently ignore cancellation — a newer search superseded this one
            return
        } catch {
            errorMessage = error.localizedDescription
            AccessibilityNotification.Announcement(String(localized: "Search failed")).post()
        }
    }

    // MARK: - Filters

    func clearFilters() {
        selectedType = nil
        minRating = 0
        maxPrice = 0
        verifiedOnly = false
        selectedServices = []
        radiusMiles = 25
    }

    var hasActiveFilters: Bool {
        selectedType != nil || minRating > 0 || maxPrice > 0 || verifiedOnly || !selectedServices.isEmpty || radiusMiles != 25
    }

    // MARK: - Provider Selection

    func selectProvider(_ provider: RespiteProvider) {
        selectedProvider = provider
        showProviderDetail = true
    }

    func requestAvailability(for provider: RespiteProvider) {
        selectedProvider = provider
        showRequestSheet = true
    }

    // MARK: - Available Services (for filter chips)

    static let commonServices = [
        "Personal Care",
        "Meal Preparation",
        "Medication Reminders",
        "Companionship",
        "Transportation",
        "Light Housekeeping",
        "Memory Care",
        "Physical Therapy",
        "Skilled Nursing"
    ]
}
