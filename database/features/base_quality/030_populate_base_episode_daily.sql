-- ============================================================================
-- MomentumLab
-- Feature     : Base Episode Daily Population
-- File        : 030_populate_base_episode_daily.sql
-- Version     : 1.0
--
-- Purpose:
--   Detect and persist the currently relevant Base Episode for each security.
--
-- Current production-validation universe:
--   NIFTY 100
-- ============================================================================

WITH params AS
(
    SELECT
        DATE '2026-08-13' AS trade_date
),

-- ============================================================================
-- 1. NIFTY 100 UNIVERSE
-- ============================================================================

nifty100 AS
(
    SELECT
        s.security_id,
        s.symbol

    FROM ref.security_universe_membership um

    JOIN ref.ref_nse_equity_security s
      ON s.security_id = um.security_id

    WHERE um.universe_code = 'NIFTY_100'
),

-- ============================================================================
-- 2. MARKET STRUCTURE HISTORY
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

    JOIN nifty100 n
      ON n.symbol = m.symbol

    CROSS JOIN params p

    WHERE m.trade_date <= p.trade_date
),

-- ============================================================================
-- 3. UNIQUE CONFIRMED SWING HIGHS
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
-- 4. UNIQUE CONFIRMED SWING LOWS
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
-- A swing low becomes a candidate when the next confirmed swing low is higher.
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
-- 7. ATTACH IMMEDIATELY PRECEDING SWING HIGH
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
-- 8. BASIC VALIDITY
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
-- 9. MEASURE EPISODE
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

        (
            SELECT
                COUNT(*) - 1

            FROM trn.stock_market_structure_daily sm

            WHERE sm.symbol = v.symbol
              AND sm.trade_date BETWEEN
                    v.prior_swing_high_date
                    AND p.trade_date
        )::INTEGER AS base_age_sessions,

        (
            SELECT
                COUNT(*) - 1

            FROM trn.stock_market_structure_daily sm

            WHERE sm.symbol = v.symbol
              AND sm.trade_date BETWEEN
                    v.base_low_date
                    AND p.trade_date
        )::INTEGER AS post_low_sessions,

        ROUND
        (
            (
                (
                    v.prior_swing_high
                    - v.base_low
                )
                /
                NULLIF(v.prior_swing_high, 0)
                * 100
            )::NUMERIC,
            4
        ) AS correction_depth_pct,

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
            )::NUMERIC,
            4
        ) AS recovery_pct

    FROM valid_episodes v

    CROSS JOIN params p
),

-- ============================================================================
-- 10. DEFINE EPISODE BY ORIGINATING SWING HIGH
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
-- 11. KEEP ONE BASE LOW PER ORIGINATING SWING HIGH
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

        base_age_sessions,
        post_low_sessions,

        correction_depth_pct,
        recovery_pct

    FROM episode_candidates

    WHERE rn = 1
),

-- ============================================================================
-- 12. SELECT MOST RECENT EPISODE FOR EACH SYMBOL
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
),

-- ============================================================================
-- 13. RESOLVE SECURITY ID + STATUS
-- ============================================================================

resolved AS
(
    SELECT
        s.security_id,
        e.trade_date,

        e.prior_swing_high_date,
        e.prior_swing_high,

        e.base_low_date,
        e.base_low,

        e.base_age_sessions,
        e.post_low_sessions,

        e.correction_depth_pct,
        e.recovery_pct,

        CASE
            WHEN e.post_low_date IS NULL
                THEN 'DEVELOPING'

            WHEN e.recovery_pct >= 100
                THEN 'RECLAIMED'

            ELSE 'RECOVERING'
        END AS episode_status,

        e.post_low_date,
        e.post_low

    FROM selected_episode e

    JOIN ref.ref_nse_equity_security s
      ON s.symbol = e.symbol
)

-- ============================================================================
-- 14. PERSIST BASE EPISODE
-- ============================================================================

INSERT INTO trn.stock_base_episode_daily
(
    security_id,
    trade_date,

    prior_swing_high_date,
    prior_swing_high,

    base_low_date,
    base_low,

    base_age_sessions,
    post_low_sessions,

    correction_depth_pct,
    recovery_pct,

    episode_status,

    post_low_date,
    post_low
)

SELECT
    security_id,
    trade_date,

    prior_swing_high_date,
    prior_swing_high,

    base_low_date,
    base_low,

    base_age_sessions,
    post_low_sessions,

    correction_depth_pct,
    recovery_pct,

    episode_status,

    post_low_date,
    post_low

FROM resolved

ON CONFLICT (security_id, trade_date)

DO UPDATE SET

    prior_swing_high_date = EXCLUDED.prior_swing_high_date,
    prior_swing_high      = EXCLUDED.prior_swing_high,

    base_low_date         = EXCLUDED.base_low_date,
    base_low              = EXCLUDED.base_low,

    base_age_sessions     = EXCLUDED.base_age_sessions,
    post_low_sessions     = EXCLUDED.post_low_sessions,

    correction_depth_pct  = EXCLUDED.correction_depth_pct,
    recovery_pct          = EXCLUDED.recovery_pct,

    episode_status        = EXCLUDED.episode_status,

    post_low_date         = EXCLUDED.post_low_date,
    post_low              = EXCLUDED.post_low;