/**
 * Wellness Scoring Algorithms
 * Used by calculate-wellness-score and evaluate-burnout-risk Edge Functions
 */

export interface WellnessSignals {
  // Check-in data
  stressLevel: number; // 1-5 (1=low stress, 5=high stress)
  sleepQuality: number; // 1-5 (1=poor, 5=excellent)
  capacityLevel: number; // 1-4 (1=running on empty, 4=full)

  // Behavioral signals (from handoff patterns)
  handoffCountLast7Days: number;
  handoffCountPrior7Days: number;
  lateNightEntries: number; // Handoffs after 10pm local
  averageSentiment: number; // -1 to 1 (negative to positive)
  taskCompletionRate: number; // 0 to 1
  daysWithoutBreak: number; // Consecutive days with handoffs
}

export type RiskLevel = "LOW" | "MODERATE" | "HIGH";

/**
 * Calculate wellness score from check-in responses (0-100)
 * Higher score = better wellness
 */
export function calculateWellnessScore(signals: WellnessSignals): number {
  // Stress: 1=low stress (good) -> 100, 5=high stress (bad) -> 0
  const stressScore = ((6 - signals.stressLevel) / 5) * 100;

  // Sleep: 1=poor -> 0, 5=excellent -> 100
  const sleepScore = (signals.sleepQuality / 5) * 100;

  // Capacity: 1=empty -> 0, 4=full -> 100
  const capacityScore = (signals.capacityLevel / 4) * 100;

  // Weighted average (equal weights for MVP)
  return Math.round((stressScore + sleepScore + capacityScore) / 3);
}

/**
 * Calculate behavioral score from handoff patterns (0-100)
 * Higher score = better (lower workload/stress indicators)
 */
export function calculateBehavioralScore(signals: WellnessSignals): number {
  let score = 100;

  // Workload spike: 50% increase in handoffs = penalty
  if (signals.handoffCountPrior7Days > 0) {
    const workloadRatio =
      signals.handoffCountLast7Days / signals.handoffCountPrior7Days;
    if (workloadRatio > 1.5) {
      score -= 20;
    } else if (workloadRatio > 1.2) {
      score -= 10;
    }
  } else if (signals.handoffCountLast7Days > 5) {
    // No prior baseline but high current = moderate penalty
    score -= 10;
  }

  // Late night entries (after 10pm): each one costs 5 points, max 20
  score -= Math.min(signals.lateNightEntries * 5, 20);

  // Negative sentiment in handoffs
  if (signals.averageSentiment < -0.3) {
    score -= 15;
  } else if (signals.averageSentiment < 0) {
    score -= 5;
  }

  // Low task completion rate
  if (signals.taskCompletionRate < 0.5) {
    score -= 15;
  } else if (signals.taskCompletionRate < 0.7) {
    score -= 10;
  }

  // Long stretch without break (day with no handoffs)
  if (signals.daysWithoutBreak > 21) {
    score -= 20;
  } else if (signals.daysWithoutBreak > 14) {
    score -= 10;
  } else if (signals.daysWithoutBreak > 7) {
    score -= 5;
  }

  return Math.max(0, Math.min(100, Math.round(score)));
}

/**
 * Calculate total wellness score (weighted average of check-in + behavioral)
 */
export function calculateTotalScore(
  wellnessScore: number,
  behavioralScore: number,
): number {
  // 60% check-in, 40% behavioral
  return Math.round(wellnessScore * 0.6 + behavioralScore * 0.4);
}

/**
 * Assess burnout risk based on signals
 * Returns LOW, MODERATE, or HIGH
 */
export function assessBurnoutRisk(signals: WellnessSignals): RiskLevel {
  let riskScore = 0;

  // Workload spike (50% increase)
  if (
    signals.handoffCountPrior7Days > 0 &&
    signals.handoffCountLast7Days > signals.handoffCountPrior7Days * 1.5
  ) {
    riskScore += 2;
  }

  // Late night pattern (3+ entries in a week)
  if (signals.lateNightEntries > 3) {
    riskScore += 2;
  }

  // Negative sentiment
  if (signals.averageSentiment < -0.3) {
    riskScore += 1;
  }

  // Task backlog (completion < 50%)
  if (signals.taskCompletionRate < 0.5) {
    riskScore += 1;
  }

  // Long stretch without break
  if (signals.daysWithoutBreak > 14) {
    riskScore += 2;
  }

  // High stress from check-in (4 or 5)
  if (signals.stressLevel >= 4) {
    riskScore += 1;
  }

  // Poor sleep from check-in (1 or 2)
  if (signals.sleepQuality <= 2) {
    riskScore += 1;
  }

  // Low capacity from check-in (1)
  if (signals.capacityLevel === 1) {
    riskScore += 1;
  }

  // Thresholds: 5+ = HIGH, 3-4 = MODERATE, 0-2 = LOW
  if (riskScore >= 5) return "HIGH";
  if (riskScore >= 3) return "MODERATE";
  return "LOW";
}

/**
 * Generate alert message based on risk factors
 */
export function generateAlertMessage(
  riskLevel: RiskLevel,
  signals: WellnessSignals,
): { title: string; message: string } {
  if (riskLevel === "HIGH") {
    const reasons: string[] = [];

    if (signals.stressLevel >= 4) {
      reasons.push("high stress levels");
    }
    if (signals.sleepQuality <= 2) {
      reasons.push("poor sleep");
    }
    if (signals.daysWithoutBreak > 14) {
      reasons.push(`${signals.daysWithoutBreak} days without a break`);
    }
    if (signals.lateNightEntries > 3) {
      reasons.push("multiple late-night entries");
    }

    const reasonText =
      reasons.length > 0 ? ` We noticed ${reasons.join(", ")}.` : "";

    return {
      title: "Take care of yourself",
      message: `You've been working so hard.${reasonText} Would you consider asking for help this week?`,
    };
  }

  if (riskLevel === "MODERATE") {
    return {
      title: "How are you holding up?",
      message:
        "Your recent check-in suggests you might be feeling stretched. Remember, it's okay to ask others to help.",
    };
  }

  return {
    title: "Keep it up",
    message: "You're doing great. Don't forget to take breaks when you can.",
  };
}

/**
 * Simple sentiment analysis using keyword matching
 * Returns score from -1 (very negative) to 1 (very positive)
 */
export function analyzeSentiment(text: string): number {
  if (!text || text.trim().length === 0) {
    return 0; // Neutral for empty text
  }

  const lowerText = text.toLowerCase();

  const negativeWords = [
    "exhausted",
    "tired",
    "overwhelmed",
    "stressed",
    "frustrated",
    "worried",
    "anxious",
    "difficult",
    "hard",
    "challenging",
    "struggle",
    "pain",
    "hurt",
    "worse",
    "declining",
    "crisis",
    "emergency",
    "terrible",
    "awful",
    "horrible",
    "scared",
    "afraid",
    "helpless",
    "hopeless",
    "burned out",
    "burnout",
  ];

  const positiveWords = [
    "good",
    "great",
    "better",
    "improving",
    "stable",
    "calm",
    "peaceful",
    "hopeful",
    "grateful",
    "thankful",
    "happy",
    "comfortable",
    "manageable",
    "progress",
    "improved",
    "positive",
    "well",
    "fine",
    "okay",
  ];

  let negativeCount = 0;
  let positiveCount = 0;

  for (const word of negativeWords) {
    if (lowerText.includes(word)) {
      negativeCount++;
    }
  }

  for (const word of positiveWords) {
    if (lowerText.includes(word)) {
      positiveCount++;
    }
  }

  const totalCount = negativeCount + positiveCount;
  if (totalCount === 0) {
    return 0; // Neutral
  }

  // Score: (positive - negative) / total, normalized to [-1, 1]
  return (positiveCount - negativeCount) / totalCount;
}
