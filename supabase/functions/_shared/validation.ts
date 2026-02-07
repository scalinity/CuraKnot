/**
 * Shared validation helpers for Edge Functions
 */

/** UUID v4 format regex */
export const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/** ISO date format (YYYY-MM-DD) regex */
export const DATE_REGEX = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Validate UUID v4 format
 */
export function isValidUUID(str: string): boolean {
  return UUID_REGEX.test(str);
}

/**
 * Validate ISO date format (YYYY-MM-DD) and parsability
 */
export function isValidDate(str: string): boolean {
  return DATE_REGEX.test(str) && !isNaN(new Date(str).getTime());
}

/**
 * Escape HTML special characters to prevent XSS
 */
export function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}
