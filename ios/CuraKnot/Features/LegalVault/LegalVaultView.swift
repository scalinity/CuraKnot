import SwiftUI

// MARK: - Legal Vault View

struct LegalVaultView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dependencyContainer: DependencyContainer
    @StateObject private var viewModel: LegalVaultViewModel
    @State private var showingAddDocument = false

    let service: LegalVaultService

    init(service: LegalVaultService) {
        self.service = service
        _viewModel = StateObject(wrappedValue: LegalVaultViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            Group {
                if !viewModel.hasAccess {
                    featureLockedView
                } else if viewModel.isLoading {
                    ProgressView()
                        .frame(maxHeight: .infinity)
                } else if viewModel.documents.isEmpty {
                    EmptyStateView(
                        icon: "doc.text.fill",
                        title: "No Legal Documents",
                        message: "Store important legal documents like Power of Attorney, Healthcare Proxy, and Advance Directives.",
                        actionTitle: "Add Document"
                    ) {
                        if viewModel.canAddDocument {
                            showingAddDocument = true
                        } else {
                            viewModel.showingUpgradePrompt = true
                        }
                    }
                } else {
                    documentList
                }
            }
            .navigationTitle("Legal Documents")
            .toolbar {
                if viewModel.hasAccess && !viewModel.documents.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            if viewModel.canAddDocument {
                                showingAddDocument = true
                            } else {
                                viewModel.showingUpgradePrompt = true
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                    }

                    ToolbarItem(placement: .secondaryAction) {
                        NavigationLink {
                            EmergencyAccessSettingsView(viewModel: viewModel)
                        } label: {
                            Label("Emergency Settings", systemImage: "cross.case")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddDocument) {
                if let circleId = appState.currentCircleId,
                   let patientId = appState.currentPatientId {
                    AddLegalDocumentView(
                        service: service,
                        circleId: circleId,
                        patientId: patientId
                    ) {
                        Task {
                            await viewModel.loadDocuments(circleId: circleId, patientId: patientId)
                        }
                    }
                }
            }
            .alert("Upgrade Required", isPresented: $viewModel.showingUpgradePrompt) {
                Button("OK") {}
            } message: {
                Text("You've reached the document limit for your plan. Upgrade to Family for unlimited documents.")
            }
            .task {
                if let circleId = appState.currentCircleId,
                   let patientId = appState.currentPatientId {
                    await viewModel.loadDocuments(circleId: circleId, patientId: patientId)
                }
            }
        }
    }

    // MARK: - Document List

    private var documentList: some View {
        List {
            // Document limit indicator (Plus tier)
            if let limitMessage = viewModel.documentLimitMessage {
                Section {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text(limitMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Expiration warnings
            if !viewModel.expiringDocuments.isEmpty {
                Section {
                    ForEach(viewModel.expiringDocuments) { doc in
                        NavigationLink {
                            LegalDocumentDetailView(document: doc, service: service)
                        } label: {
                            ExpirationWarningRow(document: doc)
                        }
                    }
                } header: {
                    Label("Attention Needed", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            // Expired documents
            if !viewModel.expiredDocuments.isEmpty {
                Section {
                    ForEach(viewModel.expiredDocuments) { doc in
                        NavigationLink {
                            LegalDocumentDetailView(document: doc, service: service)
                        } label: {
                            LegalDocumentRow(document: doc)
                        }
                    }
                } header: {
                    Label("Expired", systemImage: "xmark.circle")
                        .foregroundStyle(.red)
                }
            }

            // Document sections by category
            documentSection("Healthcare Decisions", documents: viewModel.healthcareDocuments)
            documentSection("Financial & Legal", documents: viewModel.financialDocuments)
            documentSection("Estate Planning", documents: viewModel.estateDocuments)
            documentSection("Other", documents: viewModel.otherDocuments)
        }
    }

    // MARK: - Feature Locked View

    private var featureLockedView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "lock.doc.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Legal Document Vault")
                .font(.title2)
                .fontWeight(.bold)

            Text("Securely store and share legal documents like Power of Attorney, Healthcare Proxy, and Advance Directives.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("Requires Plus or Family subscription")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding()
    }

    // MARK: - Document Section Builder

    @ViewBuilder
    private func documentSection(_ title: String, documents: [LegalDocument]) -> some View {
        if !documents.isEmpty {
            Section(title) {
                ForEach(documents) { doc in
                    NavigationLink {
                        LegalDocumentDetailView(document: doc, service: service)
                    } label: {
                        LegalDocumentRow(document: doc)
                    }
                }
                .onDelete { indexSet in
                    deleteDocuments(from: documents, at: indexSet)
                }
            }
        }
    }

    // MARK: - Helpers

    private func deleteDocuments(from list: [LegalDocument], at offsets: IndexSet) {
        let docsToDelete = offsets.map { list[$0] }
        for doc in docsToDelete {
            Task {
                await viewModel.deleteDocument(doc)
            }
        }
    }
}

// MARK: - Expiration Warning Row

struct ExpirationWarningRow: View {
    let document: LegalDocument

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.headline)

                if let days = document.daysUntilExpiration {
                    if days < 0 {
                        Text("Expired \(abs(days)) days ago")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("Expires in \(days) days")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()
        }
    }
}
