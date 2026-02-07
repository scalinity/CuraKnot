import SwiftUI

// MARK: - Emergency Access Settings View

struct EmergencyAccessSettingsView: View {
    @ObservedObject var viewModel: LegalVaultViewModel

    var body: some View {
        List {
            Section {
                Text("Choose which legal documents should be accessible from the Emergency Card. These documents can be quickly shared with first responders and healthcare providers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Healthcare documents (most relevant for emergency)
            if !viewModel.healthcareDocuments.isEmpty {
                Section("Healthcare Decisions") {
                    ForEach(viewModel.healthcareDocuments) { doc in
                        EmergencyToggleRow(
                            document: doc,
                            isEnabled: doc.includeInEmergency
                        ) {
                            Task {
                                await viewModel.toggleEmergencyAccess(for: doc)
                            }
                        }
                    }
                }
            }

            // Financial documents
            if !viewModel.financialDocuments.isEmpty {
                Section("Financial & Legal") {
                    ForEach(viewModel.financialDocuments) { doc in
                        EmergencyToggleRow(
                            document: doc,
                            isEnabled: doc.includeInEmergency
                        ) {
                            Task {
                                await viewModel.toggleEmergencyAccess(for: doc)
                            }
                        }
                    }
                }
            }

            // Estate documents
            if !viewModel.estateDocuments.isEmpty {
                Section("Estate Planning") {
                    ForEach(viewModel.estateDocuments) { doc in
                        EmergencyToggleRow(
                            document: doc,
                            isEnabled: doc.includeInEmergency
                        ) {
                            Task {
                                await viewModel.toggleEmergencyAccess(for: doc)
                            }
                        }
                    }
                }
            }

            Section {
                HStack {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.blue)
                    Text("Emergency access still requires biometric authentication.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Emergency Access")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Emergency Toggle Row

struct EmergencyToggleRow: View {
    let document: LegalDocument
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Image(systemName: document.documentType.icon)
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .font(.subheadline)

                Text(document.documentType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
        }
    }
}
