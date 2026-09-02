-- ============================================================================
-- MomentumLab
-- Table       : trn.broad_index_features_daily
-- File        : 021_trn_broad_index_features_daily.sql
-- Description : Daily derived features for broad market indices
--               used by the Market Regime engine
-- ============================================================================

CREATE TABLE IF NOT EXISTS trn.broad_index_features_daily
(
    index_id                    BIGINT NOT NULL,
    traded_date                 DATE NOT NULL,

    -- Trend Features
    ema_20                      NUMERIC(18,6),
    sma_50                      NUMERIC(18,6),
    high_52w                    NUMERIC(18,6),

    close_above_ema_20          BOOLEAN,          -- MR001
    close_above_sma_50          BOOLEAN,          -- MR002
    ema_20_rising               BOOLEAN,          -- MR003
    sma_50_rising               BOOLEAN,          -- MR004
    ema_20_above_sma_50         BOOLEAN,          -- MR005

    distance_from_ema_20_pct    NUMERIC(12,6),    -- MR006
    distance_from_52w_high_pct  NUMERIC(12,6),    -- MR007

    -- Momentum Features
    return_1d_pct               NUMERIC(12,6),    -- MR008
    return_5d_pct               NUMERIC(12,6),    -- MR009
    return_10d_pct              NUMERIC(12,6),    -- MR010
    return_20d_pct              NUMERIC(12,6),    -- MR011

    -- Daily Price Behaviour
    close_position              NUMERIC(12,6),    -- MR012
    range_pct                   NUMERIC(12,6),    -- MR013

    avg_range_20                NUMERIC(18,6),
    range_expansion_ratio       NUMERIC(12,6),    -- MR014

    break_prev_high             BOOLEAN,          -- MR015
    break_prev_low              BOOLEAN,          -- MR016
    inside_day                  BOOLEAN,          -- MR017
    outside_day                 BOOLEAN,          -- MR018
    higher_high_higher_low      BOOLEAN,          -- MR019
    lower_high_lower_low        BOOLEAN,          -- MR020

    -- Audit
    created_date                TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_date                TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT pk_broad_index_features_daily
        PRIMARY KEY (index_id, traded_date),

    CONSTRAINT fk_broad_index_features_daily_index
        FOREIGN KEY (index_id)
        REFERENCES ref.ref_broad_index(index_id)
);