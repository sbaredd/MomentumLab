-- ============================================================================
-- Momentum Lab
-- Table       : trn.sector_strength_momentum_daily
-- File        : 025_trn_sector_strength_momentum_daily.sql
-- Version     : 1.0
-- Description : Measures change in sector strength and sector rank over time
--               to identify emerging and deteriorating sector leadership
-- ============================================================================

CREATE TABLE IF NOT EXISTS trn.sector_strength_momentum_daily
(
    index_id                    BIGINT NOT NULL,
    traded_date                 DATE NOT NULL,

    -- ========================================================================
    -- CURRENT STATE
    -- ========================================================================

    sector_strength_score       NUMERIC(6,2) NOT NULL,
    sector_rank                 INTEGER NOT NULL,

    -- ========================================================================
    -- SSM001 / SSM002
    -- STRENGTH SCORE CHANGE
    --
    -- Positive = sector strength improving
    -- Negative = sector strength deteriorating
    -- ========================================================================

    score_change_5d             NUMERIC(7,2),
    score_change_10d            NUMERIC(7,2),

    -- ========================================================================
    -- SSM003 / SSM004
    -- RANK CHANGE
    --
    -- IMPORTANT:
    -- Rank 1 is strongest.
    --
    -- Therefore:
    -- previous rank - current rank
    --
    -- Example:
    -- Previous rank = 18
    -- Current rank  = 8
    -- Rank change   = +10
    --
    -- Positive = improving
    -- Negative = deteriorating
    -- ========================================================================

    rank_change_5d              INTEGER,
    rank_change_10d             INTEGER,

    -- ========================================================================
    -- SSM005
    -- IMPROVING STREAK
    --
    -- Number of consecutive trading sessions where sector strength score
    -- increased compared with the immediately preceding session.
    -- ========================================================================

    improving_streak            INTEGER,

    -- ========================================================================
    -- SSM006
    -- SECTOR STRENGTH MOMENTUM SCORE
    --
    -- Reserved for the derived 0-100 momentum score.
    -- We will populate this only after defining and validating the rules.
    -- ========================================================================

    momentum_score              NUMERIC(6,2),

    -- ========================================================================
    -- SSM007
    -- MOMENTUM CLASSIFICATION
    -- ========================================================================

    momentum_code               VARCHAR(20),

    momentum_description        VARCHAR(100),

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

    CONSTRAINT pk_sector_strength_momentum_daily
        PRIMARY KEY
        (
            index_id,
            traded_date
        ),

    CONSTRAINT fk_sector_strength_momentum_daily_index
        FOREIGN KEY
        (
            index_id
        )
        REFERENCES ref.ref_sector_index
        (
            index_id
        ),

    CONSTRAINT chk_sector_strength_momentum_score
        CHECK
        (
            momentum_score IS NULL
            OR
            (
                momentum_score >= 0
                AND momentum_score <= 100
            )
        ),

    CONSTRAINT chk_sector_strength_momentum_rank
        CHECK
        (
            sector_rank >= 1
        ),

    CONSTRAINT chk_sector_strength_improving_streak
        CHECK
        (
            improving_streak IS NULL
            OR improving_streak >= 0
        ),

    CONSTRAINT chk_sector_strength_momentum_code
        CHECK
        (
            momentum_code IS NULL
            OR momentum_code IN
            (
                'ACCELERATING',
                'IMPROVING',
                'STABLE',
                'DETERIORATING'
            )
        )
);


-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS
    idx_sector_strength_momentum_date
ON trn.sector_strength_momentum_daily
(
    traded_date
);


CREATE INDEX IF NOT EXISTS
    idx_sector_strength_momentum_index_date
ON trn.sector_strength_momentum_daily
(
    index_id,
    traded_date DESC
);


CREATE INDEX IF NOT EXISTS
    idx_sector_strength_momentum_rank_change
ON trn.sector_strength_momentum_daily
(
    traded_date,
    rank_change_5d DESC
);