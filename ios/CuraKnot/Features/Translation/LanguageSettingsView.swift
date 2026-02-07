import SwiftUI

// MARK: - Language Settings View

struct LanguageSettingsView: View {
    @StateObject private var viewModel: LanguageSettingsViewModel

    init(translationService: TranslationService, subscriptionManager: SubscriptionManager, userId: String) {
        _viewModel = StateObject(wrappedValue: LanguageSettingsViewModel(
            translationService: translationService,
            subscriptionManager: subscriptionManager,
            userId: userId
        ))
    }

    var body: some View {
        Form {
            Section("Your Preferred Language") {
                Picker("Language", selection: $viewModel.preferredLanguage) {
                    ForEach(viewModel.availableLanguages) { language in
                        HStack {
                            Text(language.displayName)
                            if !language.isAvailable(for: viewModel.currentPlan) {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(language)
                    }
                }
                .accessibilityLabel("Preferred language")
                .accessibilityHint("Select the language you want content translated to")
            }

            Section("Translation Behavior") {
                Picker("When reading other languages", selection: $viewModel.translationMode) {
                    ForEach(TranslationMode.allCases) { mode in
                        VStack(alignment: .leading) {
                            Text(mode.displayName)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .accessibilityLabel("Translation behavior")
            }

            if viewModel.translationMode != .off {
                Section {
                    Toggle("Show original alongside translation", isOn: $viewModel.showOriginal)
                        .accessibilityLabel("Show original text")
                        .accessibilityHint("When enabled, displays both original and translated text side by side")
                } footer: {
                    Text("When enabled, you'll see both the original text and the translation side by side.")
                }
            }

            if viewModel.currentPlan == .free {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Translation requires Plus or Family plan", systemImage: "globe")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Upgrade to translate handoffs, tasks, and binder items between languages.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            } else if viewModel.currentPlan == .plus {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("English and Spanish available", systemImage: "globe")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Upgrade to Family plan for all 7 languages and custom medical glossary.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }

            if let error = viewModel.saveError {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Language Settings")
        .task {
            await viewModel.loadPreferences()
        }
        .onChange(of: viewModel.preferredLanguage) { _, newValue in
            guard newValue.isAvailable(for: viewModel.currentPlan) else {
                // Revert to previous value if the language is locked and show feedback
                viewModel.preferredLanguage = viewModel.lastSavedLanguage
                viewModel.showLockedAlert = true
                return
            }
            viewModel.debounceSave()
        }
        .alert("Language Locked", isPresented: $viewModel.showLockedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This language requires an upgrade. Check your plan for available languages.")
        }
        .onChange(of: viewModel.translationMode) { _, _ in
            viewModel.debounceSave()
        }
        .onChange(of: viewModel.showOriginal) { _, _ in
            viewModel.debounceSave()
        }
    }
}

// MARK: - Language Settings View Model

@MainActor
final class LanguageSettingsViewModel: ObservableObject {
    @Published var preferredLanguage: SupportedLanguage = .english
    @Published var translationMode: TranslationMode = .auto
    @Published var showOriginal: Bool = false
    @Published var isLoading: Bool = false
    @Published var saveError: String?
    @Published var showLockedAlert: Bool = false

    /// Track the last successfully saved language for revert on locked selection
    var lastSavedLanguage: SupportedLanguage = .english

    let subscriptionManager: SubscriptionManager
    private let translationService: TranslationService
    private let userId: String
    private var saveTask: Task<Void, Never>?

    var currentPlan: SubscriptionPlan {
        subscriptionManager.currentPlan
    }

    var availableLanguages: [SupportedLanguage] {
        SupportedLanguage.allCases
    }

    init(translationService: TranslationService, subscriptionManager: SubscriptionManager, userId: String) {
        self.translationService = translationService
        self.subscriptionManager = subscriptionManager
        self.userId = userId
    }

    func loadPreferences() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let prefs = try await translationService.getUserLanguagePreferences(userId: userId)
            preferredLanguage = prefs.preferredSupportedLanguage
            translationMode = prefs.translationMode
            showOriginal = prefs.showOriginal
            lastSavedLanguage = prefs.preferredSupportedLanguage
        } catch {
            // Use defaults on error
        }
    }

    /// Debounce save to avoid rapid API calls when user is changing pickers
    func debounceSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { return }
            await savePreferences()
        }
    }

    func savePreferences() async {
        saveError = nil
        let prefs = LanguagePreferences(
            preferredLanguage: preferredLanguage.rawValue,
            translationMode: translationMode,
            showOriginal: showOriginal
        )

        do {
            try await translationService.updateUserLanguagePreferences(userId: userId, preferences: prefs)
            lastSavedLanguage = preferredLanguage
        } catch {
            saveError = "Failed to save language preferences. Please try again."
        }
    }
}
