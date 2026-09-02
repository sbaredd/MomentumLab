-- ============================================================================
-- Momentum Lab
-- Table       : trn.market_regime_daily
-- File        : 022_trn_market_regime_daily.sql
-- Version     : 1.0
-- Description : Daily Market Regime score derived from broad-index
--               MR001-MR020 features and cross-index participation
-- ============================================================================


CREATE TABLE IF NOT EXISTS trn.market_regime_daily
(
    traded_date DATE NOT NULL,


    -- ========================================================================
    -- INDIVIDUAL INDEX HEALTH SCORES
    -- Maximum score for each index = 75
    -- ========================================================================

    nifty_50_score              NUMERIC(6,2),
    nifty_500_score             NUMERIC(6,2),
    nifty_midcap_150_score      NUMERIC(6,2),
    nifty_smallcap_250_score    NUMERIC(6,2),


    -- ========================================================================
    -- WEIGHTED INDEX HEALTH
    --
    -- NIFTY 50          = 15%
    -- NIFTY 500         = 35%
    -- MIDCAP 150        = 25%
    -- SMALLCAP 250      = 25%
    --
    -- Maximum = 75
    -- ========================================================================

    weighted_index_health       NUMERIC(6,2),


    -- ========================================================================
    -- CROSS-INDEX PARTICIPATION COMPONENTS
    -- ========================================================================

    above_sma50_score           NUMERIC(6,2),
    sma50_rising_score          NUMERIC(6,2),
    above_ema20_score           NUMERIC(6,2),
    positive_10d_score          NUMERIC(6,2),
    mid_small_confirmation_score NUMERIC(6,2),


    -- Maximum = 25
    participation_score         NUMERIC(6,2),


    -- ========================================================================
    -- FINAL MARKET REGIME
    --
    -- Maximum = 100
    -- ========================================================================

    market_regime_score         NUMERIC(6,2) NOT NULL,

    regime_code                 VARCHAR(20) NOT NULL,

    regime_description          VARCHAR(100),


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

    CONSTRAINT pk_market_regime_daily
        PRIMARY KEY (traded_date),

    CONSTRAINT chk_market_regime_score
        CHECK (
            market_regime_score >= 0
            AND market_regime_score <= 100
        ),

    CONSTRAINT chk_weighted_index_health
        CHECK (
            weighted_index_health IS NULL
            OR (
                weighted_index_health >= 0
                AND weighted_index_health <= 75
            )
        ),

    CONSTRAINT chk_participation_score
        CHECK (
            participation_score IS NULL
            OR (
                participation_score >= 0
                AND participation_score <= 25
            )
        ),

    CONSTRAINT chk_regime_code
        CHECK (
            regime_code IN
            (
                'GREEN',
                'LIGHT_GREEN',
                'YELLOW',
                'ORANGE',
                'RED'
            )
        )
);


-- ============================================================================
-- INDEX
-- ============================================================================

CREATE INDEX IF NOT EXISTS
    idx_market_regime_daily_regime
ON trn.market_regime_daily
(
    regime_code,
    traded_date
);