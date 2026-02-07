import SwiftUI

// MARK: - Audit Log View

struct AuditLogView: View {
    @Environment(\.dismiss) private var dismiss

    let document: LegalDocument
    let service: LegalVaultService

    @State private var entries: [LegalDocumentAuditEntry] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxHeight: .infinity)
                } else if entries.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No Activity")
                            .font(.headline)
                        Text("Document access history will appear here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    List(entries) { entry in
                        AuditEntryRow(entry: entry)
                    }
                }
            }
            .navigationTitle("Audit Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadAuditLog()
            }
        }
    }

    private func loadAuditLog() async {
        isLoading = true
        do {
            entries = try await service.fetchAuditLog(documentId: document.id)
        } catch {
            self.error = "Failed to load audit log."
        }
        isLoading = false
    }
}

// MARK: - Audit Entry Row

struct AuditEntryRow: View {
    let entry: LegalDocumentAuditEntry

    var actionIcon: String {
        switch entry.action {
        case "VIEWED": return "eye"
        case "SHARED": return "square.and.arrow.up"
        case "DOWNLOADED": return "arrow.down.circle"
        case "PRINTED": return "printer"
        case "UPDATED": return "pencil"
        case "DELETED": return "trash"
        case "UPLOADED": return "arrow.up.doc"
        case "ACCESS_GRANTED": return "person.badge.plus"
        case "ACCESS_REVOKED": return "person.badge.minus"
        case "EXPIRATION_REMINDER": return "bell"
        case "AUTO_EXPIRED": return "clock.badge.xmark"
        default: return "questionmark.circle"
        }
    }

    var actionColor: Color {
        switch entry.action {
        case "VIEWED": return .blue
        case "SHARED": return .green
        case "DELETED": return .red
        case "ACCESS_REVOKED": return .red
        case "EXPIRATION_REMINDER": return .orange
        case "AUTO_EXPIRED": return .red
        default: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: actionIcon)
                .foregroundStyle(actionColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.action.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let userId = entry.userId {
                    Text("User: \(userId.prefix(8))...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("External access")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let ip = entry.ipAddress {
                    Text("IP: \(ip)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
