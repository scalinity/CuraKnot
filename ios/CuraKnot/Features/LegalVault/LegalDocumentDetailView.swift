import SwiftUI
import PDFKit
import os

private let logger = Logger(subsystem: "com.curaknot.app", category: "LegalDocumentDetailView")

// MARK: - Legal Document Detail View

struct LegalDocumentDetailView: View {
    let document: LegalDocument
    let service: LegalVaultService

    @State private var isUnlocked = false
    @State private var isAuthenticating = false
    @State private var authFailed = false
    @State private var documentURL: URL?
    @State private var isLoadingDocument = false
    @State private var showingShareSheet = false
    @State private var showingAccessControl = false
    @State private var showingAuditLog = false
    @State private var showingDeleteConfirmation = false
    @State private var deleteError: String?
    @State private var loadError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if isUnlocked {
                unlockedContent
            } else {
                lockedContent
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            authenticate()
        }
    }

    // MARK: - Locked Content

    private var lockedContent: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "lock.doc.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Protected Document")
                .font(.headline)

            Text("This legal document requires authentication to view.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if authFailed {
                Text("Authentication failed. Please try again.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                authenticate()
            } label: {
                Label("Unlock with Face ID", systemImage: "faceid")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAuthenticating)

            Spacer()
        }
        .padding()
    }

    // MARK: - Unlocked Content

    private var unlockedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Document preview
                documentPreview

                Divider()

                // Metadata
                metadataSection

                // Parties
                if document.agentName != nil || document.principalName != nil {
                    Divider()
                    partiesSection
                }

                // Verification
                if document.notarized || !document.witnessNames.isEmpty {
                    Divider()
                    verificationSection
                }

                // Actions
                Divider()
                actionsSection
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showingAccessControl = true
                    } label: {
                        Label("Access Controls", systemImage: "person.badge.key")
                    }

                    Button {
                        showingAuditLog = true
                    } label: {
                        Label("Audit Log", systemImage: "clock.arrow.circlepath")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareDocumentSheet(document: document, service: service)
        }
        .sheet(isPresented: $showingAccessControl) {
            AccessControlView(document: document, service: service)
        }
        .sheet(isPresented: $showingAuditLog) {
            AuditLogView(document: document, service: service)
        }
        .alert("Delete Document", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await service.deleteDocument(document)
                        dismiss()
                    } catch {
                        deleteError = "Failed to delete document: \(error.localizedDescription)"
                    }
                }
            }
        } message: {
            Text("Are you sure you want to permanently delete \"\(document.title)\"? This cannot be undone.")
        }
        .alert("Delete Failed", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "An unknown error occurred.")
        }
        .task {
            // Log view — failure is non-blocking but logged for audit compliance monitoring
            do {
                try await service.logView(documentId: document.id)
            } catch {
                logger.error("Failed to log document view for \(document.id): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Document Preview

    private var documentPreview: some View {
        Group {
            if isLoadingDocument {
                ProgressView("Loading document...")
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else if let url = documentURL {
                if document.fileType == "PDF" {
                    PDFViewWrapper(url: url)
                        .frame(maxWidth: .infinity, minHeight: 400)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3))
                        )
                } else {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: document.documentType.icon)
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)

                    if let loadError {
                        Text(loadError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button("Load Document") {
                        loadDocument()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Document Details", systemImage: "info.circle")
                .font(.headline)

            DetailRow(label: "Type", value: document.documentType.displayName)
            DetailRow(label: "Status", value: document.status.displayName)

            if let execDate = document.executionDate {
                DetailRow(label: "Execution Date", value: execDate.formatted(date: .long, time: .omitted))
            }

            if let expDate = document.expirationDate {
                DetailRow(label: "Expiration Date", value: expDate.formatted(date: .long, time: .omitted))
            }

            if let desc = document.description {
                DetailRow(label: "Description", value: desc)
            }

            if document.includeInEmergency {
                HStack {
                    Image(systemName: "cross.case.fill")
                        .foregroundStyle(.red)
                    Text("Linked to Emergency Card")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Parties Section

    private var partiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Parties", systemImage: "person.2")
                .font(.headline)

            if let principal = document.principalName {
                DetailRow(label: "Principal", value: principal)
            }

            if let agent = document.agentName {
                DetailRow(label: "Agent", value: agent)
            }

            if let altAgent = document.alternateAgentName {
                DetailRow(label: "Alternate Agent", value: altAgent)
            }
        }
    }

    // MARK: - Verification Section

    private var verificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Verification", systemImage: "checkmark.seal")
                .font(.headline)

            if document.notarized {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Notarized")
                    if let date = document.notarizedDate {
                        Text("on \(date.formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }

            if !document.witnessNames.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Witnesses:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(Array(document.witnessNames.enumerated()), id: \.offset) { _, name in
                        Text("  \(name)")
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button {
                showingShareSheet = true
            } label: {
                Label("Share Document", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                showingAccessControl = true
            } label: {
                Label("Manage Access", systemImage: "person.badge.key")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Authentication

    private func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        authFailed = false

        Task {
            let success = await LegalVaultViewModel.authenticateWithBiometrics()
            isUnlocked = success
            authFailed = !success
            isAuthenticating = false
        }
    }

    // MARK: - Load Document

    private func loadDocument() {
        isLoadingDocument = true
        loadError = nil
        Task {
            do {
                documentURL = try await service.getDocumentURL(storageKey: document.storageKey)
            } catch {
                loadError = "Failed to load document: \(error.localizedDescription)"
            }
            isLoadingDocument = false
        }
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.subheadline)
        }
    }
}

// MARK: - PDF View Wrapper

struct PDFViewWrapper: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if let document = PDFDocument(url: url) {
            uiView.document = document
        }
    }
}
