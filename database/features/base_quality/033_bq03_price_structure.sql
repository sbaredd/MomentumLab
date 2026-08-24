-- ============================================================================
-- MomentumLab
-- Feature     : BQ03 - Post-Low Price Structure
-- File        : 033_bq03_price_structure.sql
-- Version     : 1.0
--
-- Purpose:
--   Calculate and persist raw BQ03 post-low price-structure features
--   for the selected base episode.
--
-- V1 Test Scope:
--   Uses four previously validated base candidates.
--   trade_date = 2026-08-13
--
-- IMPORTANT:
--   - Raw features only
--   - No scoring
--   - Requires at least 6 post-low sessions
-- ============================================================================

WITH params AS
(
    SELECT DATE '2026-08-13' AS trade_date
),

current_candidates
(
    symbol,
    prior_swing_high_date,
    prior_swing_high,
    base_low_date,
    base_low
) AS
(
    VALUES
        ('5PAISA',     DATE '2026-07-27', 381.95::numeric,
                       DATE '2026-07-30', 344.00::numeric),

        ('CHENNPETRO', DATE '2026-07-23', 1354.00::numeric,
                       DATE '2026-07-28', 1150.00::numeric),

        ('DEEPINDS',   DATE '2026-07-20', 487.00::numeric,
                       DATE '2026-07-24', 453.60::numeric),

        ('KTKBANK',    DATE '2026-07-15', 280.00::numeric,
                       DATE '2026-07-17', 268.35::numeric)
),

post_low_data AS
(
    SELECT
        c.symbol,
        c.base_low_date,
        c.base_low,

        b.traded_date,
        b.high_price,
        b.low_price,
        b.close_price,

        LAG(b.high_price) OVER
        (
            PARTITION BY c.symbol
            ORDER BY b.traded_date
        ) AS prev_high,

        LAG(b.low_price) OVER
        (
            PARTITION BY c.symbol
            ORDER BY b.traded_date
        ) AS prev_low

    FROM current_candidates c

    CROSS JOIN params p

    JOIN trn.nse_sec_bhavdata b
      ON b.symbol = c.symbol
     AND b.series = 'EQ'
     AND b.traded_date >= c.base_low_date
     AND b.traded_date <= p.trade_date
),

classified AS
(
    SELECT
        symbol,
        base_low_date,
        base_low,
        traded_date,
        high_price,
        low_price,
        close_price,
        prev_high,
        prev_low,

        CASE
            WHEN high_price > prev_high THEN 1
            ELSE 0
        END AS is_higher_high,

        CASE
            WHEN low_price > prev_low THEN 1
            ELSE 0
        END AS is_higher_low,

        CASE
            WHEN high_price < prev_high THEN 1
            ELSE 0
        END AS is_lower_high,

        CASE
            WHEN low_price < prev_low THEN 1
            ELSE 0
        END AS is_lower_low

    FROM post_low_data

    -- Exclude the base-low session itself.
    -- It is retained in post_low_data only to provide the first LAG reference.
    WHERE traded_date > base_low_date
),

bq03 AS
(
    SELECT
        symbol,

        COUNT(*) AS post_low_sessions,

        SUM(is_higher_high) AS higher_high_days,
        SUM(is_higher_low)  AS higher_low_days,
        SUM(is_lower_high)  AS lower_high_days,
        SUM(is_lower_low)   AS lower_low_days,

        ROUND(
            (
                SUM(is_higher_high) * 100.0
                / NULLIF(COUNT(*), 0)
            )::numeric,
            4
        ) AS higher_high_ratio_pct,

        ROUND(
            (
                SUM(is_higher_low) * 100.0
                / NULLIF(COUNT(*), 0)
            )::numeric,
            4
        ) AS higher_low_ratio_pct,

        ROUND(
            (
                SUM(is_lower_low) * 100.0
                / NULLIF(COUNT(*), 0)
            )::numeric,
            4
        ) AS lower_low_ratio_pct,

        ROUND(
            (
                (
                    MAX(close_price) - MAX(base_low)
                )
                / NULLIF(MAX(base_low), 0)
                * 100
            )::numeric,
            4
        ) AS max_close_recovery_pct,

        ROUND(
            (
                (
                    MAX(high_price) - MAX(base_low)
                )
                / NULLIF(MAX(base_low), 0)
                * 100
            )::numeric,
            4
        ) AS max_price_recovery_pct

    FROM classified

    GROUP BY symbol
),

resolved AS
(
    SELECT
        s.security_id,
        p.trade_date,
        q.*

    FROM bq03 q

    JOIN ref.ref_nse_equity_security s
      ON s.symbol = q.symbol

    CROSS JOIN params p

    WHERE q.post_low_sessions >= 6
)

UPDATE trn.stock_base_quality_daily t

SET
    higher_high_days =
        r.higher_high_days,

    higher_low_days =
        r.higher_low_days,

    lower_high_days =
        r.lower_high_days,

    lower_low_days =
        r.lower_low_days,

    higher_high_ratio_pct =
        r.higher_high_ratio_pct,

    higher_low_ratio_pct =
        r.higher_low_ratio_pct,

    lower_low_ratio_pct =
        r.lower_low_ratio_pct,

    max_close_recovery_pct =
        r.max_close_recovery_pct,

    max_price_recovery_pct =
        r.max_price_recovery_pct

FROM resolved r

WHERE t.security_id = r.security_id
  AND t.trade_date = r.trade_date;