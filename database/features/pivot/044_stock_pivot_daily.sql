-- ============================================================================
-- MomentumLab
-- Table       : trn.stock_pivot_daily
-- File        : 044_stock_pivot_daily.sql
-- Version     : 1.0
-- Description : Stores the actionable structural pivot for each security
--               and evaluation date.
--
-- Design:
--   Base Episode  -> identifies the active base
--   Base Quality  -> evaluates the quality of that base
--   Pivot         -> identifies the actionable resistance level
--
-- Notes:
--   1. Pivot identification is structural only.
--   2. Volume confirmation and breakout quality are NOT evaluated here.
--   3. right_side_pivot_* stores a confirmed post-base-low resistance.
--   4. If no valid right-side pivot exists, prior_swing_high is used.
-- ============================================================================

CREATE TABLE IF NOT EXISTS trn.stock_pivot_daily
(
    security_id BIGINT NOT NULL,
    trade_date  DATE   NOT NULL,

    -- ------------------------------------------------------------------------
    -- Base episode reference
    -- ------------------------------------------------------------------------
    base_low_date         DATE,
    prior_swing_high_date DATE,
    prior_swing_high      NUMERIC,

    -- ------------------------------------------------------------------------
    -- Confirmed right-side resistance
    -- ------------------------------------------------------------------------
    right_side_pivot_date  DATE,
    right_side_pivot_price NUMERIC,

    -- ------------------------------------------------------------------------
    -- Resolved actionable pivot
    -- ------------------------------------------------------------------------
    pivot_date  DATE,
    pivot_price NUMERIC,

    pivot_type VARCHAR(30),

    -- ------------------------------------------------------------------------
    -- Price position relative to pivot
    -- ------------------------------------------------------------------------
    close_price           NUMERIC,
    distance_to_pivot_pct NUMERIC,

    -- ------------------------------------------------------------------------
    -- Structural breakout state
    -- ------------------------------------------------------------------------
    pivot_crossed      BOOLEAN,
    pivot_crossed_date DATE,

    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_stock_pivot_daily
        PRIMARY KEY (security_id, trade_date),

    CONSTRAINT chk_stock_pivot_daily_pivot_type
        CHECK
        (
            pivot_type IS NULL
            OR pivot_type IN
            (
                'RIGHT_SIDE_PIVOT',
                'PRIOR_SWING_HIGH'
            )
        )
);