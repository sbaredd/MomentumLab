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

    -- SR03: Breakout Volume
    relative_volume_20         NUMERIC,
    breakout_volume_state      VARCHAR(30),

    -- SR04: Breakout Extension
    atr_pct                    NUMERIC,
    extension_from_pivot_pct   NUMERIC,
    extension_atr_multiple     NUMERIC,
    breakout_extension_state   VARCHAR(30),

    created_date               TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_stock_setup_readiness_daily
        PRIMARY KEY (security_id, trade_date)
);