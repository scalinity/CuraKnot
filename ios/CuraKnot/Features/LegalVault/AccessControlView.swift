import SwiftUI

// MARK: - Access Control View

struct AccessControlView: View {
    @Environment(\.dismiss) private var dismiss

    let document: LegalDocument
    let service: LegalVaultService

    @State private var accessEntries: [LegalDocumentAccess] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxHeight: .infinity)
                } else if accessEntries.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.badge.key")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No Additional Access")
                            .font(.headline)
                        Text("Only the document creator has access. Grant access to circle members below.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        // Creator (always shown)
                        Section("Document Owner") {
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(.blue)
                                Text("You (Creator)")
                                Spacer()
                                Text("Full Access")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }

                        // Granted access
                        Section("Members with Access") {
                            ForEach(accessEntries) { entry in
                                AccessEntryRow(entry: entry) {
                                    revokeAccess(entry)
                                }
                            }
                        }

                        if let error {
                            Section {
                                Text(error)
                                    .foregroundStyle(.red)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Access Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadAccess()
            }
        }
    }

    // MARK: - Load Access

    private func loadAccess() async {
        isLoading = true
        do {
            accessEntries = try await service.fetchDocumentAccess(documentId: document.id)
        } catch {
            self.error = "Failed to load access controls."
        }
        isLoading = false
    }

    // MARK: - Revoke Access

    private func revokeAccess(_ entry: LegalDocumentAccess) {
        Task {
            do {
                try await service.revokeAccess(documentId: document.id, userId: entry.userId)
                accessEntries.removeAll { $0.id == entry.id }
            } catch {
                self.error = "Failed to revoke access."
            }
        }
    }
}

// MARK: - Access Entry Row

struct AccessEntryRow: View {
    let entry: LegalDocumentAccess
    let onRevoke: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("User: \(entry.userId.prefix(8))...")
                    .font(.subheadline)

                HStack(spacing: 8) {
                    if entry.canView {
                        PermissionBadge(text: "View", color: .blue)
                    }
                    if entry.canShare {
                        PermissionBadge(text: "Share", color: .green)
                    }
                    if entry.canEdit {
                        PermissionBadge(text: "Edit", color: .orange)
                    }
                }
            }

            Spacer()

            Button(role: .destructive) {
                onRevoke()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Permission Badge

struct PermissionBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
