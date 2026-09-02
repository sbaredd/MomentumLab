-- ============================================================================
-- MomentumLab
-- Table       : trn.stock_base_episode_daily
-- File        : 027_trn_stock_base_episode_daily.sql
-- Version     : 1.0
--
-- Purpose:
--   Stores the selected base episode for each security and evaluation date.
--
-- Important:
--   This table identifies WHICH base episode is being evaluated.
--   It does not score base quality.
-- ============================================================================

CREATE TABLE IF NOT EXISTS trn.stock_base_episode_daily
(
    security_id            BIGINT NOT NULL,
    trade_date             DATE NOT NULL,

    prior_swing_high_date  DATE NOT NULL,
    prior_swing_high       NUMERIC,

    base_low_date          DATE NOT NULL,
    base_low               NUMERIC,

    base_age_sessions      INTEGER,
    post_low_sessions      INTEGER,

    correction_depth_pct   NUMERIC,
    recovery_pct           NUMERIC,

    episode_status         VARCHAR(30),

    created_date           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_stock_base_episode_daily
        PRIMARY KEY (security_id, trade_date),

    CONSTRAINT fk_stock_base_episode_security
        FOREIGN KEY (security_id)
        REFERENCES ref.ref_nse_equity_security(security_id),

    CONSTRAINT chk_base_episode_dates
        CHECK (
            prior_swing_high_date < base_low_date
            AND base_low_date <= trade_date
        )
);