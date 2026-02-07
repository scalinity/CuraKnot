import Foundation
import SwiftUI
import UIKit

// MARK: - Care Network View Model

@MainActor
final class CareNetworkViewModel: ObservableObject {
    // MARK: - Published State

    @Published var providerGroups: [ProviderGroup] = []
    @Published var isLoading = false
    @Published var error: Error? {
        didSet {
            showError = error != nil
        }
    }
    @Published var showError = false

    // Feature Access
    @Published var canExport = false
    @Published var canShare = false
    @Published var canAddNotes = false

    // Export State
    @Published var isExporting = false
    @Published var currentExport: CareNetworkExport?
    @Published var showExportSheet = false
    @Published var showShareSheet = false

    // Share Configuration
    @Published var selectedCategories: Set<ProviderCategory> = Set(ProviderCategory.exportableCategories)
    @Published var shareLinkDays = 7
    @Published var includeShareLink = true

    // MARK: - Dependencies

    private let service: CareNetworkService
    let circleId: String
    let patientId: String
    let patientName: String

    // MARK: - Initialization

    init(
        service: CareNetworkService,
        circleId: String,
        patientId: String,
        patientName: String
    ) {
        self.service = service
        self.circleId = circleId
        self.patientId = patientId
        self.patientName = patientName
    }

    // MARK: - Loading State

    private var loadTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var lastLoadTime: Date?
    private let cacheExpirationInterval: TimeInterval = 300 // 5 minutes

    deinit {
        loadTask?.cancel()
        exportTask?.cancel()
    }

    // MARK: - Data Loading

    func loadProviders() async {
        // Cancel any existing load task to prevent race conditions
        loadTask?.cancel()

        // Check if cache is still valid
        if let lastLoad = lastLoadTime,
           Date().timeIntervalSince(lastLoad) < cacheExpirationInterval,
           !providerGroups.isEmpty {
            return
        }

        isLoading = true
        error = nil

        loadTask = Task {
            do {
                // Use structured concurrency to load data in parallel
                async let providersTask = service.fetchProviders(circleId: circleId, patientId: patientId)
                async let exportAccessTask = service.canExport()
                async let shareAccessTask = service.canShare()
                async let notesAccessTask = service.canAddNotes()

                // Await all results
                let loadedProviders = try await providersTask
                let exportAccess = await exportAccessTask
                let shareAccess = await shareAccessTask
                let notesAccess = await notesAccessTask

                // Check for cancellation before updating state
                if Task.isCancelled { return }

                providerGroups = loadedProviders
                canExport = exportAccess
                canShare = shareAccess
                canAddNotes = notesAccess
                lastLoadTime = Date()
            } catch {
                if !Task.isCancelled {
                    self.error = error
                }
            }

            if !Task.isCancelled {
                isLoading = false
            }
        }

        await loadTask?.value
    }

    /// Force refresh, ignoring cache
    func refreshProviders() async {
        lastLoadTime = nil
        await loadProviders()
    }

    // MARK: - Provider Count

    var totalProviderCount: Int {
        providerGroups.reduce(0) { $0 + $1.providers.count }
    }

    // MARK: - Export Actions

    func generatePDF() async {
        guard canExport else {
            error = CareNetworkError.featureGated
            return
        }

        // Cancel any existing export task
        exportTask?.cancel()

        isExporting = true
        error = nil

        exportTask = Task {
            do {
                let includedTypes = Array(selectedCategories)
                let export = try await service.generateExport(
                    patientId: patientId,
                    includedTypes: includedTypes,
                    createShareLink: includeShareLink,
                    shareLinkDays: shareLinkDays
                )

                // Check for cancellation before updating state
                if Task.isCancelled { return }

                currentExport = export
                showExportSheet = true
            } catch {
                if !Task.isCancelled {
                    self.error = error
                }
            }

            if !Task.isCancelled {
                isExporting = false
            }
        }

        await exportTask?.value
    }

    func createShareLink() async {
        guard canShare, let export = currentExport else { return }

        do {
            let shareLink = try await service.createShareLink(exportId: export.id, ttlDays: shareLinkDays)
            currentExport = CareNetworkExport(
                id: export.id,
                pdfURL: export.pdfURL,
                providerCount: export.providerCount,
                shareLink: shareLink,
                createdAt: export.createdAt
            )
        } catch {
            self.error = error
        }
    }

    // MARK: - Quick Actions

    func callProvider(_ provider: Provider) {
        guard let phone = provider.phone,
              let url = URL(string: "tel://\(phone.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: ""))") else {
            return
        }
        UIApplication.shared.open(url)
    }

    func emailProvider(_ provider: Provider) {
        guard let email = provider.email,
              let url = URL(string: "mailto:\(email)") else {
            return
        }
        UIApplication.shared.open(url)
    }

    func getDirections(_ provider: Provider) {
        guard let address = provider.address,
              let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "maps://?address=\(encoded)") else {
            return
        }
        UIApplication.shared.open(url)
    }

    func copyProviderInfo(_ provider: Provider) {
        var info = provider.name
        if let subtitle = provider.subtitle {
            info += "\n\(subtitle)"
        }
        if let org = provider.organization {
            info += "\n\(org)"
        }
        if let phone = provider.phone {
            info += "\nPhone: \(phone)"
        }
        if let email = provider.email {
            info += "\nEmail: \(email)"
        }
        if let address = provider.address {
            info += "\nAddress: \(address)"
        }
        UIPasteboard.general.string = info
    }

    // MARK: - Share Link Actions

    func copyShareLink() {
        guard let shareLink = currentExport?.shareLink else { return }
        UIPasteboard.general.string = shareLink.url
    }

    func shareViaSystem() {
        showShareSheet = true
    }

    // MARK: - Category Selection

    func toggleCategory(_ category: ProviderCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
    }

    var selectedProviderCount: Int {
        providerGroups
            .filter { selectedCategories.contains($0.category) }
            .reduce(0) { $0 + $1.providers.count }
    }
}
