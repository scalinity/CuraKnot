import SwiftUI

// MARK: - Add Glossary Term Sheet

struct AddGlossaryTermSheet: View {
    let circleId: String
    let translationService: TranslationService
    let userId: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var sourceLanguage: SupportedLanguage = .english
    @State private var targetLanguage: SupportedLanguage = .spanish
    @State private var sourceTerm: String = ""
    @State private var translatedTerm: String = ""
    @State private var context: String = ""
    @State private var category: GlossaryCategory = .condition
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    private let maxTermLength = 200
    private let maxContextLength = 500

    enum GlossaryCategory: String, CaseIterable, Identifiable {
        case medication = "MEDICATION"
        case condition = "CONDITION"
        case procedure = "PROCEDURE"
        case measurement = "MEASUREMENT"
        case other = "OTHER"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .medication: return "Medication"
            case .condition: return "Condition"
            case .procedure: return "Procedure"
            case .measurement: return "Measurement"
            case .other: return "Other"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Languages") {
                    Picker("Source Language", selection: $sourceLanguage) {
                        ForEach(SupportedLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .accessibilityLabel("Source language for this term")

                    Picker("Target Language", selection: $targetLanguage) {
                        ForEach(SupportedLanguage.allCases.filter { $0 != sourceLanguage }) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .accessibilityLabel("Target language for this term")
                }

                Section("Term") {
                    TextField("Original term", text: $sourceTerm)
                        .textInputAutocapitalization(.never)
                        .onChange(of: sourceTerm) { _, newValue in
                            if newValue.count > maxTermLength {
                                sourceTerm = String(newValue.prefix(maxTermLength))
                            }
                        }
                        .accessibilityLabel("Original term in source language")
                    TextField("Translated term", text: $translatedTerm)
                        .textInputAutocapitalization(.never)
                        .onChange(of: translatedTerm) { _, newValue in
                            if newValue.count > maxTermLength {
                                translatedTerm = String(newValue.prefix(maxTermLength))
                            }
                        }
                        .accessibilityLabel("Translated term in target language")
                }

                Section("Details") {
                    Picker("Category", selection: $category) {
                        ForEach(GlossaryCategory.allCases) { cat in
                            Text(cat.displayName).tag(cat)
                        }
                    }
                    .accessibilityLabel("Term category")

                    TextField("Context (optional)", text: $context, axis: .vertical)
                        .lineLimit(2...4)
                        .onChange(of: context) { _, newValue in
                            if newValue.count > maxContextLength {
                                context = String(newValue.prefix(maxContextLength))
                            }
                        }
                        .accessibilityLabel("Usage context for this term")
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Custom Term")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveTerm() }
                    }
                    .disabled(sourceTerm.isEmpty || translatedTerm.isEmpty || isSaving)
                }
            }
        }
    }

    private func saveTerm() async {
        isSaving = true
        errorMessage = nil

        do {
            try await translationService.addGlossaryEntry(
                circleId: circleId,
                sourceLanguage: sourceLanguage.rawValue,
                targetLanguage: targetLanguage.rawValue,
                sourceTerm: sourceTerm.trimmingCharacters(in: .whitespacesAndNewlines),
                translatedTerm: translatedTerm.trimmingCharacters(in: .whitespacesAndNewlines),
                context: context.isEmpty ? nil : context.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category.rawValue,
                userId: userId
            )
            onSave()
            dismiss()
        } catch {
            errorMessage = "Failed to save term. Please try again."
        }

        isSaving = false
    }
}
