-- ============================================================================
-- Momentum Lab
-- Table       : trn.sector_index_features_daily
-- File        : 023_trn_sector_index_features_daily.sql
-- Version     : 1.0
-- Description : Daily derived features for NSE sector indices used for
--               sector strength and sector ranking
-- ============================================================================

CREATE TABLE IF NOT EXISTS trn.sector_index_features_daily
(
    index_id                        BIGINT NOT NULL,
    traded_date                     DATE NOT NULL,

    -- ========================================================================
    -- FOUNDATION VALUES
    -- ========================================================================

    ema_20                          NUMERIC(18,6),
    sma_50                          NUMERIC(18,6),
    high_52w                        NUMERIC(18,6),

    avg_range_20                    NUMERIC(18,6),

    -- ========================================================================
    -- TREND FEATURES
    -- ========================================================================

    close_above_ema_20              BOOLEAN,
    close_above_sma_50              BOOLEAN,

    ema_20_rising                   BOOLEAN,
    sma_50_rising                   BOOLEAN,

    ema_20_above_sma_50             BOOLEAN,

    distance_from_ema_20_pct        NUMERIC(12,6),
    distance_from_52w_high_pct      NUMERIC(12,6),

    -- ========================================================================
    -- ABSOLUTE MOMENTUM
    -- ========================================================================

    return_1d_pct                   NUMERIC(12,6),
    return_5d_pct                   NUMERIC(12,6),
    return_10d_pct                  NUMERIC(12,6),
    return_20d_pct                  NUMERIC(12,6),

    -- ========================================================================
    -- RELATIVE STRENGTH VS NIFTY 500
    --
    -- sector return - NIFTY 500 return
    -- Positive value = sector outperforming broad market
    -- ========================================================================

    rs_5d_vs_nifty500_pct           NUMERIC(12,6),
    rs_10d_vs_nifty500_pct          NUMERIC(12,6),
    rs_20d_vs_nifty500_pct          NUMERIC(12,6),

    -- ========================================================================
    -- DAILY PRICE BEHAVIOUR
    -- ========================================================================

    close_position                  NUMERIC(12,6),
    range_pct                       NUMERIC(12,6),
    range_expansion_ratio           NUMERIC(12,6),

    break_prev_high                 BOOLEAN,
    break_prev_low                  BOOLEAN,

    inside_day                      BOOLEAN,
    outside_day                     BOOLEAN,

    higher_high_higher_low          BOOLEAN,
    lower_high_lower_low            BOOLEAN,

    -- ========================================================================
    -- AUDIT
    -- ========================================================================

    created_date                    TIMESTAMP NOT NULL
                                    DEFAULT CURRENT_TIMESTAMP,

    updated_date                    TIMESTAMP NOT NULL
                                    DEFAULT CURRENT_TIMESTAMP,

    -- ========================================================================
    -- CONSTRAINTS
    -- ========================================================================

    CONSTRAINT pk_sector_index_features_daily
        PRIMARY KEY
        (
            index_id,
            traded_date
        ),

    CONSTRAINT fk_sector_index_features_daily_index
        FOREIGN KEY
        (
            index_id
        )
        REFERENCES ref.ref_sector_index
        (
            index_id
        )
);


-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS
    idx_sector_index_features_daily_date
ON trn.sector_index_features_daily
(
    traded_date
);


CREATE INDEX IF NOT EXISTS
    idx_sector_index_features_daily_index_date
ON trn.sector_index_features_daily
(
    index_id,
    traded_date DESC
);