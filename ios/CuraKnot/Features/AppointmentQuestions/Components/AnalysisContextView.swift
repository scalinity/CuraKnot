import SwiftUI

// MARK: - Analysis Context View

struct AnalysisContextView: View {
    let context: AnalysisContext

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                // Handoffs analyzed
                HStack {
                    Label("Handoffs Analyzed", systemImage: "doc.text")
                    Spacer()
                    Text("\(context.handoffsAnalyzed)")
                        .fontWeight(.medium)
                }
                .font(.subheadline)

                // Patterns detected
                if !context.patternsDetected.repeatedSymptoms.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Repeated Symptoms")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(context.patternsDetected.repeatedSymptoms.prefix(3), id: \.symptom) { symptom in
                            HStack {
                                Text(symptom.symptom.capitalized)
                                Spacer()
                                Text("\(symptom.count)x")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                }

                if !context.patternsDetected.medicationChanges.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Medication Changes")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(context.patternsDetected.medicationChanges.prefix(3), id: \.medicationId) { med in
                            HStack {
                                Text(med.medicationName)
                                Spacer()
                                Text(med.changeType.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                            .font(.subheadline)
                        }
                    }
                }

                if !context.patternsDetected.potentialSideEffects.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Potential Side Effects")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(context.patternsDetected.potentialSideEffects.prefix(2), id: \.medicationId) { effect in
                            HStack {
                                Text("\(effect.symptom) ← \(effect.medicationName)")
                                Spacer()
                                Text("\(Int(effect.correlationScore * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Label("Analysis Summary", systemImage: "chart.bar.doc.horizontal")
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Generating Questions Overlay

struct GeneratingQuestionsOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)

                VStack(spacing: 8) {
                    Text("Generating Questions")
                        .font(.headline)

                    Text("Analyzing recent handoffs and medications...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

// MARK: - Preview

#Preview("Analysis Context") {
    AnalysisContextView(
        context: AnalysisContext(
            handoffsAnalyzed: 12,
            dateRange: DateRange(start: "2026-01-06", end: "2026-02-05"),
            patternsDetected: PatternsDetected(
                repeatedSymptoms: [
                    RepeatedSymptom(symptom: "dizziness", count: 4, lastMentioned: "2026-02-03"),
                    RepeatedSymptom(symptom: "fatigue", count: 3, lastMentioned: "2026-02-01")
                ],
                medicationChanges: [
                    MedicationChange(medicationId: "1", medicationName: "Lisinopril", changeType: "NEW", changedAt: "2026-01-20")
                ],
                potentialSideEffects: [
                    PotentialSideEffect(medicationId: "1", medicationName: "Lisinopril", symptom: "dizziness", correlationScore: 0.75)
                ]
            ),
            templateQuestionsAdded: 3
        )
    )
    .padding()
}

#Preview("Generating Overlay") {
    GeneratingQuestionsOverlay()
}
