import SwiftUI

// MARK: - Glossary Editor View

struct GlossaryEditorView: View {
    let circleId: String
    @StateObject private var viewModel: GlossaryEditorViewModel

    init(circleId: String, translationService: TranslationService, userId: String) {
        self.circleId = circleId
        _viewModel = StateObject(wrappedValue: GlossaryEditorViewModel(
            circleId: circleId,
            translationService: translationService,
            userId: userId
        ))
    }

    var body: some View {
        List {
            // Language pair filter
            Section("Filter by Language Pair") {
                Picker("From", selection: $viewModel.sourceLanguage) {
                    ForEach(SupportedLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .accessibilityLabel("Source language filter")

                Picker("To", selection: $viewModel.targetLanguage) {
                    ForEach(SupportedLanguage.allCases.filter { $0 != viewModel.sourceLanguage }) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .accessibilityLabel("Target language filter")
            }

            if viewModel.isLoading {
                Section {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading glossary...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if viewModel.customTerms.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Custom Terms",
                        systemImage: "character.book.closed",
                        description: Text("Add terms specific to your loved one's care. These will be used during translation.")
                    )
                }
            }

            if !viewModel.customTerms.isEmpty {
                Section("Circle-Specific Terms") {
                    ForEach(viewModel.customTerms) { term in
                        GlossaryTermRow(term: term)
                    }
                    .onDelete { indexSet in
                        Task {
                            await viewModel.deleteTerms(at: indexSet)
                        }
                    }
                }
            }

            Section {
                Button(action: { viewModel.showingAddTerm = true }) {
                    Label("Add Custom Term", systemImage: "plus")
                }
                .accessibilityLabel("Add custom glossary term")
            }

            Section("System Medical Glossary") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CuraKnot includes a built-in medical glossary covering common conditions, medications, and procedures.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("System terms are applied automatically during translation.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Medical Glossary")
        .toolbar {
            EditButton()
        }
        .sheet(isPresented: $viewModel.showingAddTerm) {
            AddGlossaryTermSheet(
                circleId: circleId,
                translationService: viewModel.translationService,
                userId: viewModel.userId
            ) {
                Task { await viewModel.loadTerms() }
            }
        }
        .task {
            await viewModel.loadTerms()
        }
        .refreshable {
            await viewModel.loadTerms()
        }
        .onChange(of: viewModel.sourceLanguage) { _, _ in
            Task { await viewModel.loadTerms() }
        }
        .onChange(of: viewModel.targetLanguage) { _, _ in
            Task { await viewModel.loadTerms() }
        }
    }
}

// MARK: - Glossary Term Row

struct GlossaryTermRow: View {
    let term: GlossaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(term.sourceTerm)
                    .font(.body)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(term.translatedTerm)
                    .font(.body)
                    .foregroundStyle(.blue)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(term.sourceTerm) translates to \(term.translatedTerm)")
            HStack(spacing: 8) {
                if let sourceLanguage = SupportedLanguage(rawValue: term.sourceLanguage) {
                    Text(sourceLanguage.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(4)
                }
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if let targetLanguage = SupportedLanguage(rawValue: term.targetLanguage) {
                    Text(targetLanguage.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(4)
                }
            }
            if let context = term.context, !context.isEmpty {
                Text(context)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Glossary Editor View Model

@MainActor
final class GlossaryEditorViewModel: ObservableObject {
    @Published var customTerms: [GlossaryEntry] = []
    @Published var isLoading: Bool = false
    @Published var showingAddTerm: Bool = false
    @Published var sourceLanguage: SupportedLanguage = .english
    @Published var targetLanguage: SupportedLanguage = .spanish

    let translationService: TranslationService
    let userId: String
    private let circleId: String

    init(circleId: String, translationService: TranslationService, userId: String) {
        self.circleId = circleId
        self.translationService = translationService
        self.userId = userId
    }

    func loadTerms() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let entries = try await translationService.fetchGlossary(
                circleId: circleId,
                sourceLanguage: sourceLanguage.rawValue,
                targetLanguage: targetLanguage.rawValue
            )
            customTerms = entries.filter { !$0.isSystemEntry }
        } catch {
            // Keep existing terms on error
        }
    }

    func deleteTerms(at indexSet: IndexSet) async {
        let termsToDelete = indexSet.map { customTerms[$0] }
        customTerms.remove(atOffsets: indexSet)

        for term in termsToDelete {
            do {
                try await translationService.deleteGlossaryEntry(id: term.id)
            } catch {
                // Reload on error to restore state
                await loadTerms()
                return
            }
        }
    }
}
