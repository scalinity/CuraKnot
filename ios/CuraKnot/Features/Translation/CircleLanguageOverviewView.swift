import SwiftUI

// MARK: - Circle Language Overview View

struct CircleLanguageOverviewView: View {
    let circleId: String
    let translationService: TranslationService
    let subscriptionManager: SubscriptionManager
    let userId: String

    @State private var memberLanguages: [String: [String]] = [:] // language -> [member names]
    @State private var isLoading: Bool = true

    var body: some View {
        List {
            languagesSection
            infoSection
            glossarySection
        }
        .navigationTitle("Circle Languages")
        .task {
            await loadMemberLanguages()
        }
    }

    @ViewBuilder
    private var languagesSection: some View {
        Section("Circle Languages Used") {
            if isLoading {
                ProgressView()
            } else if memberLanguages.isEmpty {
                Text("No language data available")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(memberLanguages.keys.sorted()), id: \.self) { langCode in
                    languageRow(langCode: langCode)
                }
            }
        }
    }

    @ViewBuilder
    private func languageRow(langCode: String) -> some View {
        if let language = SupportedLanguage(rawValue: langCode) {
            VStack(alignment: .leading, spacing: 4) {
                Text(language.displayName)
                    .font(.headline)
                if let members = memberLanguages[langCode] {
                    ForEach(members, id: \.self) { member in
                        HStack(spacing: 6) {
                            SwiftUI.Circle()
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: 6, height: 6)
                            Text(member)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var infoSection: some View {
        Section {
            Text("Translation is automatic when members have different language preferences.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var glossarySection: some View {
        if subscriptionManager.currentPlan == .family {
            Section("Medical Terms") {
                NavigationLink {
                    GlossaryEditorView(
                        circleId: circleId,
                        translationService: translationService,
                        userId: userId
                    )
                } label: {
                    Label("Custom Medical Glossary", systemImage: "character.book.closed")
                }
            }
        } else {
            Section("Medical Terms") {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Custom Glossary", systemImage: "lock.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Custom medical glossary requires the Family plan.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func loadMemberLanguages() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let rows = try await translationService.fetchCircleMemberLanguages(circleId: circleId)

            var grouped: [String: [String]] = [:]
            for row in rows {
                let (name, langCode) = TranslationService.parseMemberLanguage(row)
                grouped[langCode, default: []].append(name)
            }
            memberLanguages = grouped
        } catch {
            // Show at least the current user's language on error
            memberLanguages = ["en": ["You"]]
        }
    }
}
