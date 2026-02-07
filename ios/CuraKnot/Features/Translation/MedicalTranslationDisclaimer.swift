import SwiftUI

// MARK: - Medical Translation Disclaimer

struct MedicalTranslationDisclaimer: View {
    let language: SupportedLanguage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text(language.medicalDisclaimer)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Medical translation warning: \(language.medicalDisclaimer)")
    }
}
