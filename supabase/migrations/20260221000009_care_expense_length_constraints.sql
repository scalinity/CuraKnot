-- ============================================================================
-- Migration: Care Expense Length Constraints
-- Created: 2026-02-21
-- Description: Add length constraints on care_expenses description and
--              vendor_name columns for defense-in-depth validation.
-- ============================================================================

-- Add CHECK constraints for string length limits
-- These match the client-side validation in CareCostService.swift
ALTER TABLE care_expenses
    ADD CONSTRAINT chk_care_expenses_description_length
    CHECK (length(description) <= 1000);

ALTER TABLE care_expenses
    ADD CONSTRAINT chk_care_expenses_vendor_name_length
    CHECK (vendor_name IS NULL OR length(vendor_name) <= 200);
