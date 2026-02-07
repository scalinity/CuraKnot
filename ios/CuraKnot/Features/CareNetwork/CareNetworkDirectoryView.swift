import SwiftUI

// MARK: - Care Network Directory View

struct CareNetworkDirectoryView: View {
    @StateObject private var viewModel: CareNetworkViewModel
    @Environment(\.dismiss) private var dismiss

    init(
        service: CareNetworkService,
        circleId: String,
        patientId: String,
        patientName: String
    ) {
        _viewModel = StateObject(wrappedValue: CareNetworkViewModel(
            service: service,
            circleId: circleId,
            patientId: patientId,
            patientName: patientName
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading care team...")
                } else if viewModel.providerGroups.isEmpty {
                    emptyStateView
                } else {
                    providerListView
                }
            }
            .navigationTitle("\(viewModel.patientName)'s Care Team")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    shareMenu
                }
            }
            .task {
                await viewModel.loadProviders()
            }
            .sheet(isPresented: $viewModel.showExportSheet) {
                if let export = viewModel.currentExport {
                    CareNetworkExportSheet(
                        export: export,
                        viewModel: viewModel
                    )
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {
                    viewModel.error = nil
                }
            } message: {
                Text(viewModel.error?.localizedDescription ?? "An unknown error occurred")
            }
        }
    }

    // MARK: - Provider List

    private var providerListView: some View {
        List {
            ForEach(viewModel.providerGroups) { group in
                Section {
                    ForEach(group.providers) { provider in
                        ProviderCard(
                            provider: provider,
                            showNotesAction: viewModel.canAddNotes,
                            onCall: { viewModel.callProvider(provider) },
                            onEmail: { viewModel.emailProvider(provider) },
                            onDirections: { viewModel.getDirections(provider) },
                            onCopy: { viewModel.copyProviderInfo(provider) }
                        )
                    }
                } header: {
                    Label(group.category.displayName, systemImage: group.category.icon)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Providers Yet", systemImage: "person.2.slash")
        } description: {
            Text("Add contacts and facilities in the Binder to see them here.")
        } actions: {
            Button("Go to Binder") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Share Menu

    @ViewBuilder
    private var shareMenu: some View {
        if viewModel.totalProviderCount > 0 {
            Menu {
                if viewModel.canExport {
                    Button {
                        Task {
                            await viewModel.generatePDF()
                        }
                    } label: {
                        Label("Download PDF", systemImage: "doc.fill")
                    }

                    Button {
                        viewModel.includeShareLink = true
                        Task {
                            await viewModel.generatePDF()
                        }
                    } label: {
                        Label("Create Share Link", systemImage: "link")
                    }
                } else {
                    Button {
                        // Show upgrade prompt
                    } label: {
                        Label("Upgrade to Export", systemImage: "lock.fill")
                    }
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(viewModel.isExporting)
        }
    }
}

// MARK: - Provider Card

struct ProviderCard: View {
    let provider: Provider
    let showNotesAction: Bool
    let onCall: () -> Void
    let onEmail: () -> Void
    let onDirections: () -> Void
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name)
                        .font(.headline)

                    if let subtitle = provider.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let org = provider.organization {
                        Text(org)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                actionsMenu
            }

            // Contact Info
            if let phone = provider.phone {
                Button {
                    onCall()
                } label: {
                    Label(phone, systemImage: "phone")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }

            if let email = provider.email {
                Button {
                    onEmail()
                } label: {
                    Label(email, systemImage: "envelope")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }

            if let address = provider.address {
                Button {
                    onDirections()
                } label: {
                    Label(address, systemImage: "location")
                        .font(.caption)
                        .lineLimit(2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var actionsMenu: some View {
        Menu {
            if provider.phone != nil {
                Button {
                    onCall()
                } label: {
                    Label("Call", systemImage: "phone")
                }
            }

            if provider.email != nil {
                Button {
                    onEmail()
                } label: {
                    Label("Email", systemImage: "envelope")
                }
            }

            if provider.address != nil {
                Button {
                    onDirections()
                } label: {
                    Label("Get Directions", systemImage: "map")
                }
            }

            Divider()

            Button {
                onCopy()
            } label: {
                Label("Copy Info", systemImage: "doc.on.doc")
            }

            if showNotesAction {
                Button {
                    // Open notes editor
                } label: {
                    Label("Add Note", systemImage: "note.text")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Export Sheet

struct CareNetworkExportSheet: View {
    let export: CareNetworkExport
    @ObservedObject var viewModel: CareNetworkViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showShareActivity = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Success Header
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)

                    Text("Care Team Directory Ready")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("\(export.providerCount) providers included")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 32)

                Divider()

                // PDF Section
                VStack(alignment: .leading, spacing: 12) {
                    Label("PDF Document", systemImage: "doc.fill")
                        .font(.headline)

                    HStack {
                        Button {
                            showShareActivity = true
                        } label: {
                            Label("Share PDF", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal)

                // Share Link Section
                if let shareLink = export.shareLink {
                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Secure Link", systemImage: "link")
                            .font(.headline)

                        Text("Anyone with this link can view the care team for 7 days. No login required.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text(shareLink.url)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            Button {
                                viewModel.copyShareLink()
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                        }

                        Text("Expires: \(shareLink.formattedExpiry)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }

                Spacer()

                // CuraKnot Branding
                VStack(spacing: 4) {
                    Text("Shared via CuraKnot")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("The caregiving app that keeps families coordinated")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom)
            }
            .navigationTitle("Export Ready")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showShareActivity) {
                ShareSheet(items: [export.pdfURL])
            }
        }
    }
}

// MARK: - Share Sheet (UIKit Bridge)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Share Options Sheet

struct CareNetworkShareOptionsSheet: View {
    @ObservedObject var viewModel: CareNetworkViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Include") {
                    ForEach(ProviderCategory.exportableCategories, id: \.self) { category in
                        Toggle(isOn: Binding(
                            get: { viewModel.selectedCategories.contains(category) },
                            set: { _ in viewModel.toggleCategory(category) }
                        )) {
                            Label(category.displayName, systemImage: category.icon)
                        }
                    }
                }

                Section("Share Link") {
                    Toggle("Include share link", isOn: $viewModel.includeShareLink)

                    if viewModel.includeShareLink {
                        Picker("Link expires in", selection: $viewModel.shareLinkDays) {
                            Text("1 day").tag(1)
                            Text("7 days").tag(7)
                            Text("30 days").tag(30)
                        }
                    }
                }

                Section {
                    Button {
                        Task {
                            await viewModel.generatePDF()
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isExporting {
                                ProgressView()
                            } else {
                                Text("Generate")
                            }
                            Spacer()
                        }
                    }
                    .disabled(viewModel.selectedCategories.isEmpty || viewModel.isExporting)
                } footer: {
                    Text("\(viewModel.selectedProviderCount) providers will be included")
                }
            }
            .navigationTitle("Share Care Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Directory") {
    // Preview would require mock service
    Text("Care Network Directory Preview")
}
