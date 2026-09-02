-- ============================================================================
-- MomentumLab
-- Feature      : Base Episode Detection
-- File         : 001_base_episode_detection_v1.sql
-- Version      : 1.0
--
-- Purpose:
--   Detect the structural components of a potential base episode using
--   previously calculated swing / market-structure information.
--
-- IMPORTANT:
--   - Detection only
--   - No Base Quality scoring
--   - No INSERT / UPDATE
--   - Diagnostic output only
--
-- V1 Test Scope:
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
    SELECT DATE '2026-08-13' AS evaluation_date
),

-- ---------------------------------------------------------------------------
-- 1. Market structure available as of evaluation date
-- ---------------------------------------------------------------------------
ms AS
(
    SELECT
        m.symbol,
        m.trade_date,

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
    CROSS JOIN params p

    WHERE m.trade_date <= p.evaluation_date
      AND m.symbol IN
      (
          '5PAISA',
          'CHENNPETRO',
          'DEEPINDS',
          'KTKBANK'
      )
),

-- ---------------------------------------------------------------------------
-- 2. Identify a change in the latest swing low.
--
--    We don't want every daily repeated market-structure row.
--    We only want the date on which a new swing low became available.
-- ---------------------------------------------------------------------------
low_changes AS
(
    SELECT
        *,
        LAG(latest_swing_low_date)
            OVER
            (
                PARTITION BY symbol
                ORDER BY trade_date
            ) AS prior_reported_low_date

    FROM ms
),

new_lows AS
(
    SELECT
        symbol,
        trade_date,

        latest_swing_low_date AS base_low_date,
        latest_swing_low      AS base_low,

        low_structure

    FROM low_changes

    WHERE latest_swing_low_date IS NOT NULL

      AND
      (
          prior_reported_low_date IS NULL
          OR latest_swing_low_date <> prior_reported_low_date
      )
),

-- ---------------------------------------------------------------------------
-- 3. Find candidate base lows.
--
--    V1 structural hypothesis:
--       LL = correction establishes a lower swing low.
--
--    IMPORTANT:
--       This does NOT mean the base is good.
--       It only establishes a candidate structural low.
-- ---------------------------------------------------------------------------
candidate_lows AS
(
    SELECT *
    FROM new_lows
    WHERE low_structure = 'LL'
),

-- ---------------------------------------------------------------------------
-- 4. Find the most recent swing high preceding each candidate low.
-- ---------------------------------------------------------------------------
episodes AS
(
    SELECT
        cl.symbol,
        cl.base_low_date,
        cl.base_low,

        ph.prior_swing_high_date,
        ph.prior_swing_high

    FROM candidate_lows cl

    LEFT JOIN LATERAL
    (
        SELECT
            x.latest_swing_high_date AS prior_swing_high_date,
            x.latest_swing_high      AS prior_swing_high

        FROM ms x

        WHERE x.symbol = cl.symbol
          AND x.latest_swing_high_date < cl.base_low_date
          AND x.latest_swing_high IS NOT NULL

        ORDER BY x.latest_swing_high_date DESC

        LIMIT 1

    ) ph ON TRUE
),

-- ---------------------------------------------------------------------------
-- 5. Find first subsequent Higher Low after candidate base low.
--
--    This represents evidence that price may have stopped making lower lows.
-- ---------------------------------------------------------------------------
post_low AS
(
    SELECT
        e.*,

        pl.post_low_date,
        pl.post_low

    FROM episodes e

    LEFT JOIN LATERAL
    (
        SELECT
            x.latest_swing_low_date AS post_low_date,
            x.latest_swing_low      AS post_low

        FROM ms x

        WHERE x.symbol = e.symbol
          AND x.latest_swing_low_date > e.base_low_date
          AND x.low_structure = 'HL'

        ORDER BY x.latest_swing_low_date

        LIMIT 1

    ) pl ON TRUE
),

-- ---------------------------------------------------------------------------
-- 6. Calculate raw episode measurements.
-- ---------------------------------------------------------------------------
measurements AS
(
    SELECT
        p.symbol,

        (SELECT evaluation_date FROM params) AS trade_date,

        p.prior_swing_high_date,
        p.prior_swing_high,

        p.base_low_date,
        p.base_low,

        p.post_low_date,
        p.post_low,

        -- Calendar-day values for V1 diagnostic only.
        -- Trading-session counts can replace these later.
        (
            (SELECT evaluation_date FROM params)
            - p.base_low_date
        ) AS base_age_days,

        CASE
            WHEN p.post_low_date IS NOT NULL
            THEN p.post_low_date - p.base_low_date
        END AS post_low_days,

        CASE
            WHEN p.prior_swing_high > 0
            THEN ROUND(
                (
                    (p.prior_swing_high - p.base_low)
                    / p.prior_swing_high
                ) * 100,
                2
            )
        END AS correction_depth_pct,

        CASE
            WHEN p.base_low > 0
             AND p.post_low IS NOT NULL
            THEN ROUND(
                (
                    (p.post_low - p.base_low)
                    / p.base_low
                ) * 100,
                2
            )
        END AS recovery_pct

    FROM post_low p
)

-- ---------------------------------------------------------------------------
-- FINAL DIAGNOSTIC OUTPUT
-- ---------------------------------------------------------------------------
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
        WHEN post_low_date IS NOT NULL
            THEN 'RECOVERING'
        ELSE 'DEVELOPING'
    END AS episode_status

FROM measurements

ORDER BY
    symbol,
    base_low_date;