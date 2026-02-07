import SwiftUI

// MARK: - Wellness Score Card

/// Card displaying the current wellness score and risk level
struct WellnessScoreCard: View {
    let checkIn: WellnessCheckIn

    private var scoreColor: Color {
        guard let score = checkIn.totalScore else { return .gray }
        if score >= 70 { return .green }
        if score >= 40 { return .yellow }
        return .red
    }

    private var riskColor: Color {
        switch checkIn.riskLevel {
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .red
        case .unknown: return .gray
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Score circle
            ZStack {
                // Background circle
                SwiftUI.Circle()
                    .stroke(Color(.systemGray5), lineWidth: 12)

                // Progress circle
                if let score = checkIn.totalScore {
                    SwiftUI.Circle()
                        .trim(from: 0, to: CGFloat(score) / 100)
                        .stroke(
                            scoreColor,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.5), value: score)
                }

                // Score text
                VStack(spacing: 4) {
                    if let score = checkIn.totalScore {
                        Text("\(score)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(scoreColor)
                    } else {
                        Text("--")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Text("Wellness Score")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 150, height: 150)

            // Risk level badge
            HStack(spacing: 8) {
                SwiftUI.Circle()
                    .fill(riskColor)
                    .frame(width: 8, height: 8)

                Text(checkIn.riskLevel.displayText)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(riskColor.opacity(0.1))
            .clipShape(Capsule())

            // Score breakdown
            if checkIn.wellnessScore != nil || checkIn.behavioralScore != nil {
                HStack(spacing: 24) {
                    if let wellnessScore = checkIn.wellnessScore {
                        ScoreBreakdownItem(
                            title: "Self-Report",
                            score: wellnessScore
                        )
                    }

                    if let behavioralScore = checkIn.behavioralScore {
                        ScoreBreakdownItem(
                            title: "Activity",
                            score: behavioralScore
                        )
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}

// MARK: - Score Breakdown Item

private struct ScoreBreakdownItem: View {
    let title: String
    let score: Int

    var body: some View {
        VStack(spacing: 4) {
            Text("\(score)")
                .font(.title3)
                .fontWeight(.semibold)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
