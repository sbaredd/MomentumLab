-- ============================================================================
-- MomentumLab
-- Feature      : Base Episode Detection V2
-- File         : 002_base_episode_detection_v2.sql
-- Version      : 2.0
--
-- Purpose:
--   Consolidate historical structural candidates into ONE currently relevant
--   base episode per security as of the evaluation date.
--
-- IMPORTANT:
--   - Diagnostic only
--   - No INSERT / UPDATE
--   - No Base Quality scoring
-- ============================================================================

WITH params AS
(
    SELECT DATE '2026-08-13' AS evaluation_date
),

ms AS
(
    SELECT m.*
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

-- Detect when a new swing low first becomes visible in market structure.
low_transitions AS
(
    SELECT
        m.*,

        LAG(latest_swing_low_date) OVER
        (
            PARTITION BY symbol
            ORDER BY trade_date
        ) AS previous_reported_low_date

    FROM ms m
),

distinct_swing_lows AS
(
    SELECT
        symbol,
        trade_date AS confirmation_trade_date,
        latest_swing_low_date AS swing_low_date,
        latest_swing_low AS swing_low,
        low_structure

    FROM low_transitions

    WHERE latest_swing_low_date IS NOT NULL
      AND
      (
          previous_reported_low_date IS NULL
          OR latest_swing_low_date <> previous_reported_low_date
      )
),

-- V2 hypothesis:
-- A lower-low represents a candidate correction/base low.
ll_candidates AS
(
    SELECT *
    FROM distinct_swing_lows
    WHERE low_structure = 'LL'
),

-- Keep only the most recent LL for each stock.
current_low AS
(
    SELECT *
    FROM
    (
        SELECT
            l.*,

            ROW_NUMBER() OVER
            (
                PARTITION BY symbol
                ORDER BY swing_low_date DESC
            ) AS rn

        FROM ll_candidates l
    ) x

    WHERE rn = 1
),

-- Find the most recent confirmed swing high BEFORE the selected base low.
base_origin AS
(
    SELECT
        l.symbol,

        l.swing_low_date AS base_low_date,
        l.swing_low      AS base_low,

        h.prior_swing_high_date,
        h.prior_swing_high

    FROM current_low l

    LEFT JOIN LATERAL
    (
        SELECT DISTINCT
            m.latest_swing_high_date AS prior_swing_high_date,
            m.latest_swing_high      AS prior_swing_high

        FROM ms m

        WHERE m.symbol = l.symbol
          AND m.latest_swing_high_date < l.swing_low_date
          AND m.latest_swing_high IS NOT NULL

        ORDER BY
            m.latest_swing_high_date DESC,
            m.latest_swing_high DESC

        LIMIT 1

    ) h ON TRUE
),

-- Find first confirmed HL after the selected base low.
recovery_structure AS
(
    SELECT
        b.*,

        r.post_low_date,
        r.post_low

    FROM base_origin b

    LEFT JOIN LATERAL
    (
        SELECT DISTINCT
            m.latest_swing_low_date AS post_low_date,
            m.latest_swing_low      AS post_low

        FROM ms m

        WHERE m.symbol = b.symbol
          AND m.latest_swing_low_date > b.base_low_date
          AND m.low_structure = 'HL'

        ORDER BY
            m.latest_swing_low_date

        LIMIT 1

    ) r ON TRUE
),

measurements AS
(
    SELECT
        r.symbol,
        p.evaluation_date AS trade_date,

        r.prior_swing_high_date,
        r.prior_swing_high,

        r.base_low_date,
        r.base_low,

        r.post_low_date,
        r.post_low,

        p.evaluation_date - r.base_low_date
            AS base_age_days,

        CASE
            WHEN r.post_low_date IS NOT NULL
            THEN r.post_low_date - r.base_low_date
        END AS post_low_days,

        ROUND(
            (
                (r.prior_swing_high - r.base_low)
                / NULLIF(r.prior_swing_high, 0)
                * 100
            )::numeric,
            2
        ) AS correction_depth_pct,

        CASE
            WHEN r.post_low IS NOT NULL
            THEN ROUND(
                (
                    (r.post_low - r.base_low)
                    / NULLIF(r.base_low, 0)
                    * 100
                )::numeric,
                2
            )
        END AS recovery_pct

    FROM recovery_structure r
    CROSS JOIN params p
)

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

FROM measurements

ORDER BY symbol;