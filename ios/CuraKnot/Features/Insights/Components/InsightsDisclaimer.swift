import SwiftUI

/// Non-clinical disclaimer banner for symptom patterns
struct InsightsDisclaimer: View {
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
                .imageScale(.large)

            VStack(alignment: .leading, spacing: 4) {
                if !compact {
                    Text("Observation Only")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }

                Text(disclaimerText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var disclaimerText: String {
        if compact {
            return "These are observations from your handoffs, not medical assessments."
        }
        return "Patterns are observations from your handoffs, not medical assessments. Discuss any concerns with healthcare providers."
    }
}

#Preview {
    VStack(spacing: 16) {
        InsightsDisclaimer()
        InsightsDisclaimer(compact: true)
    }
    .padding()
}
