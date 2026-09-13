-- ============================================================================
-- MomentumLab
-- Feature     : Candidate Ranking V1 OOS Observation Capture
-- File        : 001_capture_candidate_ranking_oos_observation.sql
-- Version     : 1.0
--
-- Purpose:
--   Capture one immutable prediction-time observation for each structural
--   episode whose FIRST-EVER Candidate Selection V1 eligible observation
--   occurs on or after the frozen OOS start date.
--
-- Frozen OOS start:
--   2026-09-14
--
-- Important:
--   1. First V1 eligibility is calculated across ALL available history.
--   2. The OOS date filter is applied only AFTER first-entry identification.
--   3. Pre-OOS carry-forward episodes cannot enter the OOS cohort.
--   4. Existing observations are never updated.
--   5. No future outcome information is stored here.
-- ============================================================================

WITH v1_eligible AS
(
    SELECT
        e.security_id,
        e.pivot_date,
        e.pivot_price,
        e.episode_start_date,

        r.trade_date AS observation_date,

        r.pivot_proximity_pct,
        r.prebreakout_5d_return_pct,
        r.recent_5_volume_vs_20d_pct,
        r.pivot_proximity_direction,

        ROW_NUMBER() OVER
        (
            PARTITION BY
                e.security_id,
                e.pivot_date,
                e.pivot_price,
                e.episode_start_date
            ORDER BY r.trade_date
        ) AS eligible_seq

    FROM trn.stock_setup_episode e

    JOIN trn.stock_setup_readiness_daily r
      ON r.security_id = e.security_id
     AND r.pivot_date = e.pivot_date
     AND r.pivot_price = e.pivot_price
     AND r.trade_date >= e.episode_start_date
     AND r.trade_date <= COALESCE(e.episode_end_date, r.trade_date)

    WHERE r.breakout_state = 'BELOW_PIVOT'
      AND r.pivot_proximity_pct >= -4.0
      AND r.pivot_proximity_pct < 0.0
),
first_v1_entry AS
(
    SELECT
        security_id,
        pivot_date,
        pivot_price,
        episode_start_date,
        observation_date,
        pivot_proximity_pct,
        prebreakout_5d_return_pct,
        recent_5_volume_vs_20d_pct,
        pivot_proximity_direction
    FROM v1_eligible
    WHERE eligible_seq = 1
)
INSERT INTO trn.candidate_ranking_oos_observation
(
    security_id,
    pivot_date,
    pivot_price,
    episode_start_date,
    observation_date,
    pivot_proximity_pct,
    prebreakout_5d_return_pct,
    recent_5_volume_vs_20d_pct,
    pivot_proximity_direction
)
SELECT
    security_id,
    pivot_date,
    pivot_price,
    episode_start_date,
    observation_date,
    pivot_proximity_pct,
    prebreakout_5d_return_pct,
    recent_5_volume_vs_20d_pct,
    pivot_proximity_direction
FROM first_v1_entry
WHERE observation_date >= DATE '2026-09-14'
  AND observation_date = :evaluation_date

ON CONFLICT
(
    security_id,
    pivot_date,
    pivot_price,
    episode_start_date
)
DO NOTHING;
