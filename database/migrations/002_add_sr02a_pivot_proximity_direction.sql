-- ============================================================================
-- MomentumLab
-- Migration   : Add SR02A - Pivot Proximity Direction
-- File        : 002_add_sr02a_pivot_proximity_direction.sql
-- Version     : 1.0
-- Description : Adds persistence columns for change in pivot proximity and
--               direction of movement relative to the active structural pivot.
--
-- Columns:
--   pivot_proximity_change_1d_pct
--   Change in pivot proximity versus the immediate previous trading session.
--
--   pivot_proximity_direction
--       APPROACHING_PIVOT
--       RETREATING_FROM_PIVOT
--       UNCHANGED
--
-- Notes:
--   - This migration changes schema only.
--   - It does not calculate or backfill SR02A.
--   - Columns remain nullable because SR02A requires a valid prior observation.
--   - ADD COLUMN IF NOT EXISTS makes the migration idempotent.
-- ============================================================================

ALTER TABLE trn.stock_setup_readiness_daily
    ADD COLUMN IF NOT EXISTS pivot_proximity_change_1d_pct NUMERIC,
    ADD COLUMN IF NOT EXISTS pivot_proximity_direction VARCHAR(30);