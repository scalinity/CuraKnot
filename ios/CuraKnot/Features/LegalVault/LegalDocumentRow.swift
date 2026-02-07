import SwiftUI

// MARK: - Legal Document Row

struct LegalDocumentRow: View {
    let document: LegalDocument

    var body: some View {
        HStack {
            Image(systemName: document.documentType.icon)
                .foregroundStyle(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.headline)

                if let agent = document.agentName {
                    Text("Agent: \(agent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let execDate = document.executionDate {
                    Text("Executed: \(execDate, style: .date)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            DocumentStatusBadge(document: document)
        }
    }
}

// MARK: - Document Status Badge

struct DocumentStatusBadge: View {
    let document: LegalDocument

    var body: some View {
        Group {
            switch document.status {
            case .expired:
                Label("Expired", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)

            case .revoked:
                Label("Revoked", systemImage: "nosign")
                    .font(.caption)
                    .foregroundStyle(.red)

            case .superseded:
                Label("Superseded", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.orange)

            case .active:
                if let daysUntil = document.daysUntilExpiration, daysUntil <= 90 {
                    if daysUntil < 0 {
                        Label("Expired", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Label("\(daysUntil)d", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } else {
                    Label("Valid", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }
}
