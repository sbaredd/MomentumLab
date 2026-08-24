-- ============================================================================
-- MomentumLab
-- Table       : trn.stock_base_quality_daily
-- File        : 026_trn_stock_base_quality_daily.sql
-- Version     : 1.0
-- Description : Daily raw Base Quality features for each NSE equity
--
-- Feature groups:
--   BQ01 - Correction / Pullback Behaviour
--   BQ02 - Post-Low Range Contraction
--   BQ03 - Post-Low Price Structure
--   BQ04 - Post-Low Volume Behaviour
--
-- Important:
--   This table stores RAW FEATURES only.
--   No Base Quality scoring thresholds are defined here.
-- ============================================================================

CREATE TABLE IF NOT EXISTS trn.stock_base_quality_daily
(
    security_id BIGINT NOT NULL,
    trade_date  DATE   NOT NULL,

    -- ------------------------------------------------------------------------
    -- Base Episode Context
    -- ------------------------------------------------------------------------

    prior_swing_high_date DATE,
    prior_swing_high      NUMERIC(18,4),

    base_low_date         DATE,
    base_low              NUMERIC(18,4),

    -- ------------------------------------------------------------------------
    -- BQ01 - Correction / Pullback Behaviour
    -- ------------------------------------------------------------------------

    correction_depth_pct             NUMERIC(10,4),
    pullback_sessions                INTEGER,
    correction_speed_pct_per_session NUMERIC(10,4),

    pullback_avg_range_pct           NUMERIC(10,4),
    pullback_max_range_pct           NUMERIC(10,4),

    pullback_down_up_volume_ratio    NUMERIC(10,4),

    -- ------------------------------------------------------------------------
    -- BQ02 - Post-Low Range Contraction
    -- ------------------------------------------------------------------------

    post_low_sessions       INTEGER,

    early_3_avg_range_pct   NUMERIC(10,4),
    recent_3_avg_range_pct  NUMERIC(10,4),

    range_contraction_pct   NUMERIC(10,4),

    -- ------------------------------------------------------------------------
    -- BQ03 - Post-Low Price Structure
    -- ------------------------------------------------------------------------

    higher_high_days        INTEGER,
    higher_low_days         INTEGER,

    lower_high_days         INTEGER,
    lower_low_days          INTEGER,

    higher_high_ratio_pct   NUMERIC(10,4),
    higher_low_ratio_pct    NUMERIC(10,4),
    lower_low_ratio_pct     NUMERIC(10,4),

    max_close_recovery_pct  NUMERIC(10,4),
    max_price_recovery_pct  NUMERIC(10,4),

    -- ------------------------------------------------------------------------
    -- BQ04 - Post-Low Volume Behaviour
    -- ------------------------------------------------------------------------

    post_low_up_days        INTEGER,
    post_low_down_days      INTEGER,
    post_low_flat_days      INTEGER,

    avg_up_volume           NUMERIC(20,2),
    avg_down_volume         NUMERIC(20,2),

    down_vs_up_volume_ratio NUMERIC(10,4),
    up_vs_down_volume_ratio NUMERIC(10,4),

    -- ------------------------------------------------------------------------
    -- Audit
    -- ------------------------------------------------------------------------

    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- ------------------------------------------------------------------------
    -- Constraints
    -- ------------------------------------------------------------------------

    CONSTRAINT pk_stock_base_quality_daily
        PRIMARY KEY (security_id, trade_date),

    CONSTRAINT fk_stock_base_quality_security
        FOREIGN KEY (security_id)
        REFERENCES ref.ref_nse_equity_security(security_id)
);