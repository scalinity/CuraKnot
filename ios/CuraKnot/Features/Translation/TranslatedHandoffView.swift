import SwiftUI

// MARK: - Translated Handoff View

struct TranslatedHandoffView: View {
    let handoff: Handoff
    let circleId: String
    @StateObject private var viewModel: TranslatedHandoffViewModel

    init(handoff: Handoff, circleId: String, translationService: TranslationService, subscriptionManager: SubscriptionManager, userId: String) {
        self.handoff = handoff
        self.circleId = circleId
        _viewModel = StateObject(wrappedValue: TranslatedHandoffViewModel(
            translationService: translationService,
            subscriptionManager: subscriptionManager,
            userId: userId
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Translation banner
            if viewModel.isTranslated {
                translationBanner
            }

            // Stale translation warning
            if viewModel.isStale {
                staleWarning
            }

            // Content
            if viewModel.showingOriginal || !viewModel.isTranslated {
                originalContent
            } else {
                translatedContent
            }

            // Medical disclaimer
            if viewModel.isTranslated && viewModel.showDisclaimer {
                MedicalTranslationDisclaimer(language: viewModel.targetLanguage)
            }

            // Translation loading state
            if viewModel.isTranslating {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Translating...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Translation in progress")
            }

            // Translation error with retry
            if let error = viewModel.translationError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Retry") {
                            Task {
                                await viewModel.requestTranslation(for: handoff, circleId: circleId)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.blue)
                    }
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Translation error: \(error). Double tap to retry.")
            }
        }
        .task {
            await viewModel.loadTranslation(for: handoff, circleId: circleId)
        }
    }

    // MARK: - Subviews

    private var translationBanner: some View {
        HStack {
            Image(systemName: "globe")
                .foregroundStyle(.blue)
            Text("Translated from \(viewModel.sourceLanguageName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(viewModel.showingOriginal ? "Show Translation" : "View Original") {
                viewModel.showingOriginal.toggle()
            }
            .font(.caption)
            .foregroundStyle(.blue)
        }
        .padding(8)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Translation from \(viewModel.sourceLanguageName). \(viewModel.showingOriginal ? "Showing original" : "Showing translation")")
        .accessibilityHint("Double tap to toggle between original and translated text")
    }

    private var staleWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption)
                .foregroundStyle(.orange)
            Text("Translation may be outdated. The original was updated.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Refresh") {
                Task {
                    await viewModel.requestTranslation(for: handoff, circleId: circleId)
                }
            }
            .font(.caption)
            .foregroundStyle(.blue)
        }
        .padding(8)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Translation may be outdated. Double tap to refresh.")
    }

    private var originalContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(handoff.title)
                .font(.headline)
                .accessibilityLabel("Title: \(handoff.title)")
            if let summary = handoff.summary {
                Text(summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Summary: \(summary)")
            }
        }
    }

    private var translatedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.translatedTitle ?? handoff.title)
                .font(.headline)
                .accessibilityLabel("Translated title: \(viewModel.translatedTitle ?? handoff.title)")
            if let summary = viewModel.translatedSummary ?? handoff.summary {
                Text(summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Translated summary: \(summary)")
            }
        }
    }
}

// MARK: - Translated Handoff View Model

@MainActor
final class TranslatedHandoffViewModel: ObservableObject {
    @Published var translatedTitle: String?
    @Published var translatedSummary: String?
    @Published var showingOriginal: Bool = false
    @Published var isTranslating: Bool = false
    @Published var isTranslated: Bool = false
    @Published var isStale: Bool = false
    @Published var showDisclaimer: Bool = false
    @Published var translationError: String?
    @Published var sourceLanguageName: String = ""
    @Published var targetLanguage: SupportedLanguage = .english

    private let translationService: TranslationService
    private let subscriptionManager: SubscriptionManager
    private let userId: String
    private var retryTask: Task<Void, Never>?
    private var lastRetryTime: Date = .distantPast

    init(translationService: TranslationService, subscriptionManager: SubscriptionManager, userId: String) {
        self.translationService = translationService
        self.subscriptionManager = subscriptionManager
        self.userId = userId
    }

    func loadTranslation(for handoff: Handoff, circleId: String) async {
        // Get user preferences
        let prefs: LanguagePreferences
        do {
            prefs = try await translationService.getUserLanguagePreferences(userId: userId)
        } catch {
            prefs = LanguagePreferences()
        }

        let userLanguage = SupportedLanguage(rawValue: prefs.preferredLanguage) ?? .english
        targetLanguage = userLanguage
        let sourceLanguage = handoff.sourceLanguage ?? "en"
        sourceLanguageName = SupportedLanguage(rawValue: sourceLanguage)?.englishName ?? sourceLanguage

        // Check if translation is needed
        guard sourceLanguage != userLanguage.rawValue else { return }

        // Check if user's plan supports translation
        guard userLanguage.isAvailable(for: subscriptionManager.currentPlan) else { return }

        // Check translation mode
        guard prefs.translationMode == .auto else {
            // For on-demand mode, user must tap to translate
            return
        }

        // Perform translation
        isTranslating = true
        translationError = nil

        do {
            let result = try await translationService.translateHandoff(
                handoff,
                to: userLanguage,
                circleId: circleId
            )

            translatedTitle = result.translatedTitle
            translatedSummary = result.translatedSummary
            isTranslated = true
            isStale = result.isStale
            // Show disclaimer when medical terms are present or confidence is low
            showDisclaimer = result.containsMedicalTerms || (result.confidenceScore ?? 1.0) < 0.95
            showingOriginal = prefs.showOriginal
        } catch {
            translationError = "Translation unavailable"
        }

        isTranslating = false
    }

    /// Manually trigger translation (for on-demand mode or retry) with debounce to prevent spam
    func requestTranslation(for handoff: Handoff, circleId: String) async {
        // Check isTranslating first to prevent race condition
        guard !isTranslating else { return }
        // Debounce: ignore rapid retries within 2 seconds
        let now = Date()
        guard now.timeIntervalSince(lastRetryTime) >= 2.0 else { return }
        lastRetryTime = now

        isTranslating = true
        translationError = nil

        do {
            let result = try await translationService.translateHandoff(
                handoff,
                to: targetLanguage,
                circleId: circleId
            )

            translatedTitle = result.translatedTitle
            translatedSummary = result.translatedSummary
            isTranslated = true
            isStale = false
            showDisclaimer = result.containsMedicalTerms || (result.confidenceScore ?? 1.0) < 0.95
        } catch {
            translationError = "Translation failed. Please try again."
        }

        isTranslating = false
    }
}
