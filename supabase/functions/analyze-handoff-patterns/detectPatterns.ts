/**
 * Pattern detection algorithms for symptom patterns
 *
 * Detects 5 pattern types:
 * - FREQUENCY: 3+ mentions in 30 days
 * - TREND: Increasing/decreasing over time (>30% change week-over-week)
 * - NEW: First mention in last 7 days
 * - ABSENCE: Was frequent (5+ mentions), now stopped (14+ days no mention)
 * - CORRELATION: (Handled separately in correlateEvents.ts)
 */

import {
  ConcernCategory,
  PatternType,
  TrendDirection,
  type PatternResult,
} from "./types.ts";

interface Mention {
  handoffId: string;
  createdAt: Date;
  normalizedTerm: string;
  rawText: string;
}

const FREQUENCY_THRESHOLD = 3; // Minimum mentions for FREQUENCY pattern
const TREND_CHANGE_THRESHOLD = 0.3; // 30% change for INCREASING/DECREASING
const NEW_PATTERN_DAYS = 7; // Days for NEW pattern
const ABSENCE_THRESHOLD_DAYS = 14; // Days without mention for ABSENCE
const ABSENCE_MIN_PREVIOUS = 5; // Minimum previous mentions for ABSENCE

export function detectPatterns(
  _category: ConcernCategory,
  mentions: Mention[],
): PatternResult[] {
  if (mentions.length === 0) {
    return [];
  }

  // Sort by date ascending
  const sortedMentions = [...mentions].sort(
    (a, b) => a.createdAt.getTime() - b.createdAt.getTime(),
  );

  const now = new Date();
  const firstMention = sortedMentions[0].createdAt;
  const lastMention = sortedMentions[sortedMentions.length - 1].createdAt;

  // Validate dates before proceeding
  if (isNaN(firstMention.getTime()) || isNaN(lastMention.getTime())) {
    console.error("Invalid mention dates detected, skipping pattern detection");
    return [];
  }

  const patterns: PatternResult[] = [];

  // Check for NEW pattern (first mention in last 7 days)
  const daysSinceFirst = daysBetween(firstMention, now);
  if (daysSinceFirst <= NEW_PATTERN_DAYS && mentions.length >= 1) {
    patterns.push({
      type: PatternType.NEW,
      mentionCount: mentions.length,
      firstMentionDate: firstMention,
      lastMentionDate: lastMention,
      trend: undefined,
    });
  }

  // Check for FREQUENCY pattern (3+ mentions)
  if (mentions.length >= FREQUENCY_THRESHOLD) {
    const trend = calculateTrend(sortedMentions);

    patterns.push({
      type: PatternType.FREQUENCY,
      mentionCount: mentions.length,
      firstMentionDate: firstMention,
      lastMentionDate: lastMention,
      trend,
    });

    // If there's a significant trend, also add TREND pattern
    if (trend !== TrendDirection.STABLE) {
      patterns.push({
        type: PatternType.TREND,
        mentionCount: mentions.length,
        firstMentionDate: firstMention,
        lastMentionDate: lastMention,
        trend,
      });
    }
  }

  // Note: ABSENCE and CORRELATION patterns require historical data
  // and are detected separately with additional context

  return patterns;
}

/**
 * Calculate trend direction by comparing recent week to previous week
 * Uses exclusive lower bound to avoid off-by-one errors at week boundaries
 */
function calculateTrend(mentions: Mention[]): TrendDirection {
  if (mentions.length < 2) {
    return TrendDirection.STABLE;
  }

  // Use latest mention as reference point for consistent boundaries
  const sortedByDate = [...mentions].sort(
    (a, b) => b.createdAt.getTime() - a.createdAt.getTime(),
  );
  const referenceDate = sortedByDate[0].createdAt;

  // Calculate week boundaries in UTC to avoid timezone issues
  const oneWeekAgo = new Date(
    referenceDate.getTime() - 7 * 24 * 60 * 60 * 1000,
  );
  const twoWeeksAgo = new Date(
    referenceDate.getTime() - 14 * 24 * 60 * 60 * 1000,
  );

  // Count mentions in recent week vs previous week
  // Recent week: (oneWeekAgo, referenceDate] (exclusive lower, inclusive upper)
  const recentWeekCount = mentions.filter(
    (m) => m.createdAt > oneWeekAgo && m.createdAt <= referenceDate,
  ).length;

  // Previous week: [twoWeeksAgo, oneWeekAgo] (inclusive both)
  const previousWeekCount = mentions.filter(
    (m) => m.createdAt >= twoWeeksAgo && m.createdAt <= oneWeekAgo,
  ).length;

  // Handle edge case: no data in previous week
  if (previousWeekCount === 0) {
    if (recentWeekCount > 0) {
      return TrendDirection.INCREASING; // New activity
    }
    return TrendDirection.STABLE;
  }

  // Calculate percentage change with zero-division safety
  const changePercent =
    (recentWeekCount - previousWeekCount) / previousWeekCount;

  if (changePercent > TREND_CHANGE_THRESHOLD) {
    return TrendDirection.INCREASING;
  } else if (changePercent < -TREND_CHANGE_THRESHOLD) {
    return TrendDirection.DECREASING;
  }

  return TrendDirection.STABLE;
}

/**
 * Detect ABSENCE pattern by comparing historical frequency to recent silence
 *
 * @param historicalMentions All mentions from the past (e.g., 60 days ago to 14 days ago)
 * @param recentMentions Mentions from the recent period (e.g., last 14 days)
 */
export function detectAbsencePattern(
  _category: ConcernCategory,
  historicalMentions: Mention[],
  recentMentions: Mention[],
): PatternResult | null {
  // Need sufficient historical data and no recent mentions
  if (
    historicalMentions.length < ABSENCE_MIN_PREVIOUS ||
    recentMentions.length > 0
  ) {
    return null;
  }

  const sortedHistorical = [...historicalMentions].sort(
    (a, b) => a.createdAt.getTime() - b.createdAt.getTime(),
  );

  const firstMention = sortedHistorical[0].createdAt;
  const lastMention = sortedHistorical[sortedHistorical.length - 1].createdAt;
  const now = new Date();

  // Check if last mention was at least ABSENCE_THRESHOLD_DAYS ago
  if (daysBetween(lastMention, now) < ABSENCE_THRESHOLD_DAYS) {
    return null;
  }

  return {
    type: PatternType.ABSENCE,
    mentionCount: historicalMentions.length,
    firstMentionDate: firstMention,
    lastMentionDate: lastMention,
    trend: TrendDirection.DECREASING,
  };
}

function daysBetween(date1: Date, date2: Date): number {
  const diffMs = Math.abs(date2.getTime() - date1.getTime());
  return Math.floor(diffMs / (24 * 60 * 60 * 1000));
}

export type { PatternResult };
