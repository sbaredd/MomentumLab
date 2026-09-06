-- ============================================================================
-- MomentumLab
-- Table       : trn.stock_setup_readiness_daily
-- Description : Daily actionable setup state relative to structural pivot
-- ============================================================================

CREATE TABLE IF NOT EXISTS trn.stock_setup_readiness_daily
(
    security_id                BIGINT NOT NULL,
    trade_date                 DATE NOT NULL,

    -- Pivot context
    pivot_date                 DATE,
    pivot_price                NUMERIC,
    pivot_type                 VARCHAR(30),

    -- SR01: Breakout State
    high_vs_pivot_pct          NUMERIC,
    close_vs_pivot_pct         NUMERIC,
    breakout_state             VARCHAR(30),

    -- SR02: Pivot Proximity
    pivot_proximity_pct        NUMERIC,

    -- SR02A: Pivot Proximity Direction
    pivot_proximity_change_1d_pct NUMERIC,
    pivot_proximity_direction     VARCHAR(30),

    -- SR03: Breakout Volume
    relative_volume_20         NUMERIC,
    breakout_volume_state      VARCHAR(30),

    -- SR04: Breakout Extension
    atr_pct                    NUMERIC,
    extension_from_pivot_pct   NUMERIC,
    extension_atr_multiple     NUMERIC,
    breakout_extension_state   VARCHAR(30),

        -- SR05: Pivot Tightness
    recent_5_range_pct              NUMERIC,
    recent_5_close_tightness_pct    NUMERIC,

    -- SR06: Pivot Volume Dry-Up
    recent_5_avg_volume             NUMERIC,
    recent_5_volume_vs_20d_pct      NUMERIC,

    -- SR07: Pre-Breakout Price Progression
    prebreakout_5d_return_pct       NUMERIC,
    prebreakout_close_position_pct  NUMERIC,
    prebreakout_5d_low              NUMERIC,

    -- SR08: Structural Entry Risk
    pivot_to_stop_risk_pct          NUMERIC,
    pivot_to_stop_risk_atr          NUMERIC,

    created_date               TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_stock_setup_readiness_daily
        PRIMARY KEY (security_id, trade_date)
);