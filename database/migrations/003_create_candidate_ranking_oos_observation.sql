-- ============================================================================
-- MomentumLab
-- Migration   : 003_create_candidate_ranking_oos_observation.sql
-- Purpose     : Persist immutable prediction-time observations for
--               Candidate Ranking V1 out-of-sample validation.
--
-- Grain       : One row per structural setup episode.
--
-- Important:
--   - Stores prediction-time information only.
--   - Does NOT store future outcomes.
--   - Does NOT store ranking scores, weights, or tiers.
--   - OOS cohort start date is enforced by the capture process,
--     not by this table.
-- ============================================================================

CREATE TABLE IF NOT EXISTS trn.candidate_ranking_oos_observation
(
    security_id                    BIGINT          NOT NULL,
    pivot_date                     DATE            NOT NULL,
    pivot_price                    NUMERIC         NOT NULL,
    episode_start_date             DATE            NOT NULL,

    observation_date               DATE            NOT NULL,

    -- CR01: Pivot Proximity
    pivot_proximity_pct            NUMERIC         NOT NULL,

    -- CR03: Pre-Breakout 5-Day Progression
    prebreakout_5d_return_pct      NUMERIC         NOT NULL,

    -- CR06: Recent Volume Participation
    recent_5_volume_vs_20d_pct     NUMERIC         NOT NULL,

    -- CR04: Context only.
    -- NULL means direction was not observable at first V1 entry.
    pivot_proximity_direction      VARCHAR(50),

    created_at                     TIMESTAMP       NOT NULL
                                                   DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_candidate_ranking_oos_observation
        PRIMARY KEY
        (
            security_id,
            pivot_date,
            pivot_price,
            episode_start_date
        )
);