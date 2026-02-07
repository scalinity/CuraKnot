/**
 * Type definitions for Symptom Pattern Surfacing
 */

export enum ConcernCategory {
  TIREDNESS = "TIREDNESS",
  APPETITE = "APPETITE",
  SLEEP = "SLEEP",
  PAIN = "PAIN",
  MOOD = "MOOD",
  MOBILITY = "MOBILITY",
  COGNITION = "COGNITION",
  DIGESTION = "DIGESTION",
  BREATHING = "BREATHING",
  SKIN = "SKIN",
}

export enum PatternType {
  FREQUENCY = "FREQUENCY", // 3+ mentions in 30 days
  TREND = "TREND", // Increasing or decreasing over time
  CORRELATION = "CORRELATION", // Near medication/facility change
  NEW = "NEW", // First mention in last 7 days
  ABSENCE = "ABSENCE", // Previously frequent, now stopped
}

export enum TrendDirection {
  INCREASING = "INCREASING",
  DECREASING = "DECREASING",
  STABLE = "STABLE",
}

export interface ConcernExtraction {
  category: ConcernCategory;
  rawText: string;
  normalizedTerm: string;
}

export interface PatternResult {
  type: PatternType;
  mentionCount: number;
  firstMentionDate: Date;
  lastMentionDate: Date;
  trend?: TrendDirection;
}

export interface CorrelatedEvent {
  eventType: "MEDICATION" | "FACILITY_CHANGE";
  eventId: string;
  eventDescription: string;
  eventDate: string;
  daysDifference: number;
  strength: "STRONG" | "POSSIBLE";
}

// Category keyword mappings for normalization reference
export const CATEGORY_KEYWORDS: Record<ConcernCategory, string[]> = {
  [ConcernCategory.TIREDNESS]: [
    "tired",
    "exhausted",
    "no energy",
    "fatigued",
    "sluggish",
    "lethargic",
    "worn out",
    "drained",
    "weary",
  ],
  [ConcernCategory.APPETITE]: [
    "not eating",
    "no appetite",
    "eating well",
    "hungry",
    "eating less",
    "not hungry",
    "appetite",
    "food",
  ],
  [ConcernCategory.SLEEP]: [
    "insomnia",
    "sleeping",
    "restless",
    "can't sleep",
    "waking up",
    "nightmares",
    "sleep",
    "nap",
    "drowsy",
  ],
  [ConcernCategory.PAIN]: [
    "pain",
    "hurting",
    "aches",
    "discomfort",
    "sore",
    "tender",
    "sharp",
    "dull",
    "throbbing",
  ],
  [ConcernCategory.MOOD]: [
    "sad",
    "anxious",
    "irritable",
    "happy",
    "depressed",
    "worried",
    "upset",
    "angry",
    "mood",
    "crying",
  ],
  [ConcernCategory.MOBILITY]: [
    "walking",
    "balance",
    "fell",
    "unsteady",
    "stumbling",
    "mobility",
    "standing",
    "moving",
    "weak legs",
  ],
  [ConcernCategory.COGNITION]: [
    "confused",
    "forgetful",
    "alert",
    "sharp",
    "disoriented",
    "memory",
    "thinking",
    "unclear",
  ],
  [ConcernCategory.DIGESTION]: [
    "nausea",
    "constipation",
    "upset stomach",
    "diarrhea",
    "vomiting",
    "bloated",
    "stomach",
    "bowel",
  ],
  [ConcernCategory.BREATHING]: [
    "short of breath",
    "coughing",
    "wheezing",
    "breathing",
    "chest",
    "breathless",
    "SOB",
  ],
  [ConcernCategory.SKIN]: [
    "rash",
    "bruise",
    "swelling",
    "wound",
    "redness",
    "itchy",
    "skin",
    "sore",
    "cut",
  ],
};

// Banned clinical terms for safety
export const BANNED_CLINICAL_TERMS = [
  "diagnosis",
  "diagnose",
  "disease",
  "infection",
  "syndrome",
  "disorder",
  "condition",
  "acute",
  "chronic",
  "severe",
  "critical",
  "emergency",
  "prognosis",
  "treatment",
  "prescription",
  "prescribe",
  "pathology",
  "pathological",
  "clinical",
  "medical assessment",
  "risk factor",
  "complication",
  "adverse effect",
];
