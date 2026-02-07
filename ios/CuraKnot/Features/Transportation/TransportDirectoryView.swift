import SwiftUI

// MARK: - Transport Directory View

struct TransportDirectoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @ObservedObject var service: TransportationService

    @State private var showingAddService = false
    @State private var searchText = ""
    @State private var filterType: TransportServiceEntry.ServiceType?
    @State private var errorMessage: String?

    // Cached filtered results to avoid recomputation on every render
    @State private var cachedFilteredServices: [TransportServiceEntry] = []
    @State private var cachedSystemServices: [TransportServiceEntry] = []
    @State private var cachedCircleServices: [TransportServiceEntry] = []

    private func updateFilteredServices() {
        var result = service.transportServices.filter { $0.isActive }

        if let filterType = filterType {
            result = result.filter { $0.serviceType == filterType }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                ($0.serviceArea?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                ($0.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        cachedFilteredServices = result
        cachedSystemServices = result.filter { $0.isSystemService }
        cachedCircleServices = result.filter { !$0.isSystemService }
    }

    var body: some View {
        NavigationStack {
            List {
                // Filter
                Section {
                    Picker("Filter by Type", selection: $filterType) {
                        Text("All Types").tag(nil as TransportServiceEntry.ServiceType?)
                        ForEach(TransportServiceEntry.ServiceType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type as TransportServiceEntry.ServiceType?)
                        }
                    }
                }

                // System Services
                if !cachedSystemServices.isEmpty {
                    Section("General Resources") {
                        ForEach(cachedSystemServices) { entry in
                            ServiceRow(entry: entry)
                        }
                    }
                }

                // Circle Services
                if !cachedCircleServices.isEmpty {
                    Section("Your Circle's Services") {
                        ForEach(cachedCircleServices) { entry in
                            ServiceRow(entry: entry)
                        }
                    }
                }

                // Empty state
                if cachedFilteredServices.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No services found")
                                .font(.headline)
                            Text("Add a local service below.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search services")
            .navigationTitle("Transport Directory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddService = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddService) {
                AddTransportServiceSheet(service: service)
            }
            .alert("Error", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onChange(of: searchText) { _, _ in updateFilteredServices() }
            .onChange(of: filterType) { _, _ in updateFilteredServices() }
            .onChange(of: service.transportServices) { _, _ in updateFilteredServices() }
            .task {
                guard !Task.isCancelled else { return }
                guard let circleId = appState.currentCircle?.id else { return }
                do {
                    try await service.fetchTransportServices(circleId: circleId)
                    guard !Task.isCancelled else { return }
                } catch {
                    guard !Task.isCancelled else { return }
                    errorMessage = error.localizedDescription
                }
                updateFilteredServices()
            }
        }
    }
}

// MARK: - Service Row

struct ServiceRow: View {
    let entry: TransportServiceEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: entry.serviceType.icon)
                    .foregroundStyle(.blue)
                Text(entry.name)
                    .font(.headline)
                Spacer()
                if entry.isSystemService {
                    Text("General")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            if let serviceArea = entry.serviceArea, !serviceArea.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                        .font(.caption)
                    Text(serviceArea)
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }

            if let hours = entry.hours, !hours.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text(hours)
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }

            // Capability badges
            HStack(spacing: 6) {
                if entry.wheelchairAccessible {
                    CapabilityBadge(text: "Wheelchair", available: true)
                }
                if entry.stretcherAvailable {
                    CapabilityBadge(text: "Stretcher", available: true)
                }
                if entry.oxygenAllowed {
                    CapabilityBadge(text: "Oxygen", available: true)
                }
            }

            // Contact
            HStack(spacing: 16) {
                if let phone = entry.phone, !phone.isEmpty {
                    let digits = phone.filter { $0.isNumber || $0 == "+" }
                    if let phoneURL = URL(string: "tel:\(digits)") {
                        Link(destination: phoneURL) {
                            Label("Call", systemImage: "phone")
                                .font(.caption)
                        }
                        .accessibilityLabel("Call \(entry.name)")
                    }
                }
                if let website = entry.website, !website.isEmpty {
                    let urlString = website.hasPrefix("http://") || website.hasPrefix("https://")
                        ? website
                        : "https://\(website)"
                    if let webURL = URL(string: urlString),
                       let scheme = webURL.scheme?.lowercased(),
                       scheme == "http" || scheme == "https" {
                        Link(destination: webURL) {
                            Label("Website", systemImage: "globe")
                                .font(.caption)
                        }
                        .accessibilityLabel("Visit \(entry.name) website")
                    }
                }
            }

            if let notes = entry.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(serviceRowAccessibilityLabel)
    }

    private var serviceRowAccessibilityLabel: String {
        var parts = [entry.name, entry.serviceType.displayName]
        if let area = entry.serviceArea, !area.isEmpty { parts.append(area) }
        if let hours = entry.hours, !hours.isEmpty { parts.append(hours) }
        if entry.wheelchairAccessible { parts.append("Wheelchair accessible") }
        if entry.stretcherAvailable { parts.append("Stretcher available") }
        if entry.oxygenAllowed { parts.append("Oxygen allowed") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Capability Badge

struct CapabilityBadge: View {
    let text: String
    let available: Bool

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(available ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
            .foregroundStyle(available ? .green : .red)
            .clipShape(Capsule())
            .accessibilityLabel("\(text): \(available ? "available" : "not available")")
    }
}

// MARK: - Add Transport Service Sheet

struct AddTransportServiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @ObservedObject var service: TransportationService

    @State private var name = ""
    @State private var serviceType: TransportServiceEntry.ServiceType = .medicalTransport
    @State private var phone = ""
    @State private var website = ""
    @State private var hours = ""
    @State private var serviceArea = ""
    @State private var wheelchairAccessible = false
    @State private var stretcherAvailable = false
    @State private var oxygenAllowed = false
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Service Information") {
                    TextField("Service Name", text: $name)

                    Picker("Type", selection: $serviceType) {
                        ForEach(TransportServiceEntry.ServiceType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon).tag(type)
                        }
                    }

                    TextField("Phone Number", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("Website", text: $website)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    TextField("Hours (e.g., Mon-Fri 8AM-5PM)", text: $hours)
                    TextField("Service Area", text: $serviceArea)
                }

                Section("Capabilities") {
                    Toggle("Wheelchair Accessible", isOn: $wheelchairAccessible)
                    Toggle("Stretcher Available", isOn: $stretcherAvailable)
                    Toggle("Oxygen Allowed", isOn: $oxygenAllowed)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }

                Section {
                    Button {
                        saveService()
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isSaving ? "Saving..." : "Add Service")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isSaving || name.trimmedAndLimited(to: 500).isEmpty || !isPhoneValid)
                }
            }
            .navigationTitle("Add Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var isPhoneValid: Bool {
        let stripped = phone.trimmingCharacters(in: .whitespaces)
        if stripped.isEmpty { return true } // phone is optional
        let digitCount = stripped.filter { $0.isNumber }.count
        return digitCount >= 7 && digitCount <= 15
    }

    private func saveService() {
        guard let circleId = appState.currentCircle?.id else { return }

        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                let request = AddTransportServiceRequest(
                    circleId: circleId,
                    name: name.trimmedAndLimited(to: 500),
                    serviceType: serviceType,
                    phone: phone.trimmedLimitedOrNil(to: 50),
                    website: website.trimmedLimitedOrNil(to: 2048),
                    hours: hours.trimmedLimitedOrNil(to: 500),
                    serviceArea: serviceArea.trimmedLimitedOrNil(to: 1000),
                    wheelchairAccessible: wheelchairAccessible,
                    stretcherAvailable: stretcherAvailable,
                    oxygenAllowed: oxygenAllowed,
                    notes: notes.trimmedLimitedOrNil(to: 5000)
                )
                try await service.addTransportService(request)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
