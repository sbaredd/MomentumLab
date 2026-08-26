-- ============================================================================
-- MomentumLab
-- Diagnostic  : Base Episode Detection V3
-- File        : 003_base_episode_detection_v3.sql
-- Version     : 3.0
--
-- Purpose:
--   Detect the currently relevant base episode from confirmed market structure.
--
-- Architecture:
--   trn.stock_market_structure_daily
--          |
--          v
--   confirmed structural pivots
--          |
--          v
--   prior swing high -> base swing low -> post-low higher low
--          |
--          v
--   one selected base episode per symbol
--
-- IMPORTANT:
--   - No hard-coded pivot prices
--   - No Base Quality scoring
--   - No INSERT / UPDATE
--   - Uses only confirmed structural information available by trade_date
--   - Diagnostic first; persistence comes later
--
-- V3 Principle:
--   A base episode begins with a meaningful correction from a confirmed
--   swing high to a subsequent confirmed swing low.
--
--   A later higher swing low is evidence that the stock has started
--   recovering / building structure above the base low.
--
-- V3 Test Scope:
--   5PAISA
--   CHENNPETRO
--   DEEPINDS
--   KTKBANK
--
-- Evaluation Date:
--   2026-08-13
-- ============================================================================


WITH params AS
(
    SELECT DATE '2026-08-13' AS trade_date
),


-- ============================================================================
-- 1. TEST UNIVERSE
-- ============================================================================

test_symbols AS
(
    SELECT symbol

    FROM
    (
        VALUES
            ('5PAISA'),
            ('CHENNPETRO'),
            ('DEEPINDS'),
            ('KTKBANK')
    ) AS x(symbol)
),


-- ============================================================================
-- 2. MARKET STRUCTURE HISTORY AVAILABLE AS OF EVALUATION DATE
-- ============================================================================

structure_history AS
(
    SELECT
        m.trade_date,
        m.symbol,

        m.previous_swing_high_date,
        m.previous_swing_high,

        m.latest_swing_high_date,
        m.latest_swing_high,

        m.previous_swing_low_date,
        m.previous_swing_low,

        m.latest_swing_low_date,
        m.latest_swing_low,

        m.high_structure,
        m.low_structure,
        m.market_structure

    FROM trn.stock_market_structure_daily m

    JOIN test_symbols t
      ON t.symbol = m.symbol

    CROSS JOIN params p

    WHERE m.trade_date <= p.trade_date
),


-- ============================================================================
-- 3. EXTRACT UNIQUE CONFIRMED SWING HIGHS
--
-- stock_market_structure_daily is a daily state table.
-- The same pivot may therefore appear on several consecutive rows.
-- ============================================================================

swing_highs AS
(
    SELECT DISTINCT
        symbol,

        latest_swing_high_date AS pivot_date,
        latest_swing_high      AS pivot_price

    FROM structure_history

    WHERE latest_swing_high_date IS NOT NULL
      AND latest_swing_high IS NOT NULL
),


-- ============================================================================
-- 4. EXTRACT UNIQUE CONFIRMED SWING LOWS
-- ============================================================================

swing_lows AS
(
    SELECT DISTINCT
        symbol,

        latest_swing_low_date AS pivot_date,
        latest_swing_low      AS pivot_price

    FROM structure_history

    WHERE latest_swing_low_date IS NOT NULL
      AND latest_swing_low IS NOT NULL
),


-- ============================================================================
-- 5. ORDER SWING LOWS
--
-- For every confirmed low determine the next confirmed low.
--
-- If the next low is higher, the current low is a possible base low.
-- ============================================================================

ordered_lows AS
(
    SELECT
        symbol,
        pivot_date,
        pivot_price,

        LAG(pivot_date) OVER
        (
            PARTITION BY symbol
            ORDER BY pivot_date
        ) AS previous_low_date,

        LAG(pivot_price) OVER
        (
            PARTITION BY symbol
            ORDER BY pivot_date
        ) AS previous_low,

        LEAD(pivot_date) OVER
        (
            PARTITION BY symbol
            ORDER BY pivot_date
        ) AS next_low_date,

        LEAD(pivot_price) OVER
        (
            PARTITION BY symbol
            ORDER BY pivot_date
        ) AS next_low

    FROM swing_lows
),


-- ============================================================================
-- 6. POTENTIAL BASE LOWS
--
-- A confirmed low becomes a candidate when the next confirmed swing low
-- is higher.
--
-- Example:
--
--      base low
--          \
--           \____ higher low
--
-- This is structural evidence that price may have stopped making lower lows.
-- ============================================================================

base_low_candidates AS
(
    SELECT
        symbol,

        pivot_date  AS base_low_date,
        pivot_price AS base_low,

        next_low_date AS post_low_date,
        next_low      AS post_low

    FROM ordered_lows

    WHERE next_low_date IS NOT NULL
      AND next_low IS NOT NULL
      AND next_low > pivot_price
),


-- ============================================================================
-- 7. ATTACH THE IMMEDIATELY PRECEDING CONFIRMED SWING HIGH
--
-- Each base-low candidate is paired with the latest confirmed swing high
-- occurring before that low.
-- ============================================================================

candidate_episodes AS
(
    SELECT
        b.symbol,

        h.prior_swing_high_date,
        h.prior_swing_high,

        b.base_low_date,
        b.base_low,

        b.post_low_date,
        b.post_low

    FROM base_low_candidates b

    JOIN LATERAL
    (
        SELECT
            sh.pivot_date  AS prior_swing_high_date,
            sh.pivot_price AS prior_swing_high

        FROM swing_highs sh

        WHERE sh.symbol = b.symbol
          AND sh.pivot_date < b.base_low_date

        ORDER BY sh.pivot_date DESC

        LIMIT 1

    ) h
      ON TRUE
),


-- ============================================================================
-- 8. BASIC VALIDITY CHECKS
--
-- Structural order must be:
--
--      prior swing high
--             ↓
--          base low
--             ↓
--       post-low HL
--
-- The low must also be below the originating swing high.
-- ============================================================================

valid_episodes AS
(
    SELECT
        *

    FROM candidate_episodes

    WHERE prior_swing_high_date < base_low_date
      AND base_low_date < post_low_date
      AND base_low < prior_swing_high
),


-- ============================================================================
-- 9. MEASURE EACH EPISODE
-- ============================================================================

measurements AS
(
    SELECT
        v.symbol,
        p.trade_date,

        v.prior_swing_high_date,
        v.prior_swing_high,

        v.base_low_date,
        v.base_low,

        v.post_low_date,
        v.post_low,


        -- Calendar age from originating swing high
        (
            p.trade_date
            - v.prior_swing_high_date
        ) AS base_age_days,


        -- Calendar days since base low
        (
            p.trade_date
            - v.base_low_date
        ) AS post_low_days,


        -- Correction depth %
        ROUND
        (
            (
                (
                    v.prior_swing_high
                    - v.base_low
                )
                /
                NULLIF
                (
                    v.prior_swing_high,
                    0
                )
                * 100
            )::numeric,
            4
        ) AS correction_depth_pct,


        -- Recovery from base low toward prior swing high
        --
        -- 0%   = still at base low
        -- 100% = recovered to originating swing high
        -- >100 = exceeded originating swing high
        ROUND
        (
            (
                (
                    v.post_low
                    - v.base_low
                )
                /
                NULLIF
                (
                    v.prior_swing_high
                    - v.base_low,
                    0
                )
                * 100
            )::numeric,
            4
        ) AS recovery_pct

    FROM valid_episodes v

    CROSS JOIN params p
),


-- ============================================================================
-- 10. DEFINE EPISODES BY ORIGINATING SWING HIGH
--
-- V3 correction:
--
-- A later base at a higher price level can still be a completely new
-- structural episode.
--
-- Therefore we DO NOT group episodes based on whether successive lows
-- are rising or falling.
--
-- Episode identity:
--
--      symbol + prior_swing_high_date
--
-- Example:
--
-- KTKBANK
--
--      26-Feb high -> 02-Mar low     Episode A
--      01-Jul high -> 08-Jul low     Episode B
--      15-Jul high -> 17-Jul low     Episode C
-- ============================================================================

episode_candidates AS
(
    SELECT
        m.*,

        ROW_NUMBER() OVER
        (
            PARTITION BY
                symbol,
                prior_swing_high_date

            ORDER BY
                base_low_date DESC
        ) AS rn

    FROM measurements m
),


-- ============================================================================
-- 11. KEEP ONE BASE LOW FOR EACH ORIGINATING SWING HIGH
--
-- If multiple candidate lows are associated with one swing high,
-- retain the most recent structural base-low candidate.
-- ============================================================================

episode_origins AS
(
    SELECT
        symbol,
        trade_date,

        prior_swing_high_date,
        prior_swing_high,

        base_low_date,
        base_low,

        post_low_date,
        post_low,

        base_age_days,
        post_low_days,

        correction_depth_pct,
        recovery_pct

    FROM episode_candidates

    WHERE rn = 1
),


-- ============================================================================
-- 12. SELECT MOST RECENT EPISODE FOR EACH STOCK
--
-- Select the episode anchored by the most recent originating swing high.
-- ============================================================================

selected_episode AS
(
    SELECT
        *

    FROM
    (
        SELECT
            e.*,

            ROW_NUMBER() OVER
            (
                PARTITION BY symbol

                ORDER BY
                    prior_swing_high_date DESC,
                    base_low_date DESC
            ) AS rn

        FROM episode_origins e
    ) x

    WHERE rn = 1
)


-- ============================================================================
-- FINAL DIAGNOSTIC OUTPUT
-- ============================================================================

SELECT
    symbol,
    trade_date,

    prior_swing_high_date,
    prior_swing_high,

    base_low_date,
    base_low,

    post_low_date,
    post_low,

    base_age_days,
    post_low_days,

    correction_depth_pct,
    recovery_pct,

    CASE
        WHEN post_low_date IS NULL
            THEN 'DEVELOPING'

        ELSE 'RECOVERING'

    END AS episode_status

FROM selected_episode

ORDER BY symbol;