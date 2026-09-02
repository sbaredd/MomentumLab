-- ============================================================================
-- Momentum Lab
-- Table       : trn.sector_strength_daily
-- File        : 024_trn_sector_strength_daily.sql
-- Version     : 1.0
-- Description : Daily Sector Strength score and rank derived from
--               sector-index features SF001-SF027
-- ============================================================================

CREATE TABLE IF NOT EXISTS trn.sector_strength_daily
(
    index_id                    BIGINT NOT NULL,
    traded_date                 DATE NOT NULL,

    -- ========================================================================
    -- SCORE COMPONENTS
    -- ========================================================================

    -- SS01: Trend Structure
    -- Maximum = 30
    trend_score                 NUMERIC(6,2) NOT NULL,

    -- SS02: Absolute Momentum
    -- Maximum = 20
    absolute_momentum_score     NUMERIC(6,2) NOT NULL,

    -- SS03: Relative Strength vs NIFTY 500
    -- Maximum = 35
    relative_strength_score     NUMERIC(6,2) NOT NULL,

    -- SS04: Price Behaviour
    -- Maximum = 15
    price_behaviour_score       NUMERIC(6,2) NOT NULL,

    -- ========================================================================
    -- FINAL SECTOR STRENGTH
    -- Maximum = 100
    -- ========================================================================

    sector_strength_score       NUMERIC(6,2) NOT NULL,

    -- Rank 1 = strongest sector for that trading day
    sector_rank                 INTEGER NOT NULL,

    -- ========================================================================
    -- CLASSIFICATION
    -- ========================================================================

    strength_code               VARCHAR(20) NOT NULL,

    strength_description        VARCHAR(100),

    -- ========================================================================
    -- AUDIT
    -- ========================================================================

    created_date                TIMESTAMP NOT NULL
                                DEFAULT CURRENT_TIMESTAMP,

    updated_date                TIMESTAMP NOT NULL
                                DEFAULT CURRENT_TIMESTAMP,

    -- ========================================================================
    -- CONSTRAINTS
    -- ========================================================================

    CONSTRAINT pk_sector_strength_daily
        PRIMARY KEY
        (
            index_id,
            traded_date
        ),

    CONSTRAINT fk_sector_strength_daily_index
        FOREIGN KEY
        (
            index_id
        )
        REFERENCES ref.ref_sector_index
        (
            index_id
        ),

    CONSTRAINT chk_sector_strength_score
        CHECK
        (
            sector_strength_score >= 0
            AND sector_strength_score <= 100
        ),

    CONSTRAINT chk_trend_score
        CHECK
        (
            trend_score >= 0
            AND trend_score <= 30
        ),

    CONSTRAINT chk_absolute_momentum_score
        CHECK
        (
            absolute_momentum_score >= 0
            AND absolute_momentum_score <= 20
        ),

    CONSTRAINT chk_relative_strength_score
        CHECK
        (
            relative_strength_score >= 0
            AND relative_strength_score <= 35
        ),

    CONSTRAINT chk_price_behaviour_score
        CHECK
        (
            price_behaviour_score >= 0
            AND price_behaviour_score <= 15
        ),

    CONSTRAINT chk_sector_rank
        CHECK
        (
            sector_rank >= 1
        ),

    CONSTRAINT chk_strength_code
        CHECK
        (
            strength_code IN
            (
                'LEADING',
                'STRONG',
                'IMPROVING',
                'WEAK',
                'LAGGING'
            )
        )
);


-- ============================================================================
-- INDEXES
-- ============================================================================

-- Daily sector leaderboard
CREATE INDEX IF NOT EXISTS
    idx_sector_strength_daily_date_rank
ON trn.sector_strength_daily
(
    traded_date,
    sector_rank
);


-- Historical strength of one sector
CREATE INDEX IF NOT EXISTS
    idx_sector_strength_daily_index_date
ON trn.sector_strength_daily
(
    index_id,
    traded_date DESC
);


-- Find sectors by strength classification
CREATE INDEX IF NOT EXISTS
    idx_sector_strength_daily_code
ON trn.sector_strength_daily
(
    strength_code,
    traded_date
);