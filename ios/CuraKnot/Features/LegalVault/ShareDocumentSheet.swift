import SwiftUI

// MARK: - Share Method

enum ShareMethod: String, CaseIterable {
    case secureLink
    case email
    case print

    var displayName: String {
        switch self {
        case .secureLink: return "Secure Link"
        case .email: return "Email"
        case .print: return "Print"
        }
    }
}

// MARK: - Share Document Sheet

struct ShareDocumentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let document: LegalDocument
    let service: LegalVaultService

    @State private var shareMethod: ShareMethod = .secureLink
    @State private var expirationHours = 24
    @State private var requireAccessCode = true
    @State private var maxViews: Int?
    @State private var recipientEmail = ""
    @State private var isGenerating = false
    @State private var generatedResult: LegalVaultService.ShareResult?
    @State private var error: String?
    @State private var copiedToClipboard = false

    var body: some View {
        NavigationStack {
            Form {
                // Share method
                Section {
                    Picker("Share Method", selection: $shareMethod) {
                        ForEach(ShareMethod.allCases, id: \.self) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if shareMethod == .secureLink {
                    secureLinkSettings
                }

                if shareMethod == .email {
                    emailSettings
                }

                if shareMethod == .print {
                    printSettings
                }

                // Generated result
                if let result = generatedResult {
                    Section("Share Link") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(result.shareUrl)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.blue)
                                .textSelection(.enabled)

                            if let code = result.accessCode {
                                HStack {
                                    Text("Access Code:")
                                        .foregroundStyle(.secondary)
                                    Text(code)
                                        .font(.system(.body, design: .monospaced))
                                        .fontWeight(.bold)
                                }
                            }

                            Text("Expires: \(result.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button {
                                UIPasteboard.general.string = result.shareUrl
                                copiedToClipboard = true
                                Task {
                                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                                    copiedToClipboard = false
                                }
                            } label: {
                                Label(
                                    copiedToClipboard ? "Copied!" : "Copy Link",
                                    systemImage: copiedToClipboard ? "checkmark" : "doc.on.doc"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }

                // Error
                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Share Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }

                if generatedResult == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Share") {
                            generateShare()
                        }
                        .disabled(isGenerating || !isValid)
                    }
                }
            }
        }
    }

    // MARK: - Secure Link Settings

    private var secureLinkSettings: some View {
        Section("Link Settings") {
            Picker("Expires After", selection: $expirationHours) {
                Text("1 hour").tag(1)
                Text("24 hours").tag(24)
                Text("3 days").tag(72)
                Text("7 days").tag(168)
            }

            Toggle("Require Access Code", isOn: $requireAccessCode)

            Toggle("Limit Views", isOn: Binding(
                get: { maxViews != nil },
                set: { maxViews = $0 ? 1 : nil }
            ))

            if let currentMax = maxViews {
                Stepper("Max views: \(currentMax)", value: Binding(
                    get: { currentMax },
                    set: { maxViews = $0 }
                ), in: 1...100)
            }
        }
    }

    // MARK: - Email Settings

    private var emailSettings: some View {
        Section("Recipient") {
            TextField("Email Address", text: $recipientEmail)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
        }
    }

    // MARK: - Print Settings

    private var printSettings: some View {
        Section {
            Text("A print-ready version of the document will be prepared.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        switch shareMethod {
        case .secureLink:
            return true
        case .email:
            return !recipientEmail.isEmpty && recipientEmail.contains("@")
        case .print:
            return true
        }
    }

    // MARK: - Generate Share

    private func generateShare() {
        isGenerating = true
        error = nil

        Task {
            do {
                let result = try await service.generateShareLink(
                    documentId: document.id,
                    expirationHours: expirationHours,
                    requireAccessCode: requireAccessCode,
                    maxViews: maxViews
                )
                generatedResult = result
            } catch {
                self.error = error.localizedDescription
            }
            isGenerating = false
        }
    }
}
