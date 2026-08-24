-- ============================================================================
-- MomentumLab
-- Feature     : BQ04 - Post-Low Volume Behaviour
-- File        : 034_bq04_volume_behaviour.sql
-- Version     : 1.0
--
-- Purpose:
--   Calculate and persist raw BQ04 post-low volume-behaviour features
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
--   - Base-low session is reference-only for LAG()
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

post_low_with_anchor AS
(
    SELECT
        c.symbol,
        c.base_low_date,

        b.traded_date,
        b.close_price,
        b.traded_quantity,

        LAG(b.close_price) OVER
        (
            PARTITION BY c.symbol
            ORDER BY b.traded_date
        ) AS prev_close

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
        traded_date,
        close_price,
        traded_quantity,

        CASE
            WHEN close_price > prev_close THEN 'UP'
            WHEN close_price < prev_close THEN 'DOWN'
            ELSE 'FLAT'
        END AS day_direction

    FROM post_low_with_anchor

    WHERE traded_date > base_low_date
),

bq04 AS
(
    SELECT
        symbol,

        COUNT(*) AS post_low_sessions,

        COUNT(*) FILTER
        (
            WHERE day_direction = 'UP'
        ) AS post_low_up_days,

        COUNT(*) FILTER
        (
            WHERE day_direction = 'DOWN'
        ) AS post_low_down_days,

        COUNT(*) FILTER
        (
            WHERE day_direction = 'FLAT'
        ) AS post_low_flat_days,

        ROUND(
            AVG(traded_quantity)
            FILTER (WHERE day_direction = 'UP')::numeric,
            2
        ) AS avg_up_volume,

        ROUND(
            AVG(traded_quantity)
            FILTER (WHERE day_direction = 'DOWN')::numeric,
            2
        ) AS avg_down_volume,

        ROUND(
            (
                AVG(traded_quantity)
                FILTER (WHERE day_direction = 'DOWN')
                /
                NULLIF(
                    AVG(traded_quantity)
                    FILTER (WHERE day_direction = 'UP'),
                    0
                )
            )::numeric,
            4
        ) AS down_vs_up_volume_ratio,

        ROUND(
            (
                AVG(traded_quantity)
                FILTER (WHERE day_direction = 'UP')
                /
                NULLIF(
                    AVG(traded_quantity)
                    FILTER (WHERE day_direction = 'DOWN'),
                    0
                )
            )::numeric,
            4
        ) AS up_vs_down_volume_ratio

    FROM classified

    GROUP BY symbol
),

resolved AS
(
    SELECT
        s.security_id,
        p.trade_date,
        q.*

    FROM bq04 q

    JOIN ref.ref_nse_equity_security s
      ON s.symbol = q.symbol

    CROSS JOIN params p

    WHERE q.post_low_sessions >= 6
)

UPDATE trn.stock_base_quality_daily t

SET
    post_low_up_days =
        r.post_low_up_days,

    post_low_down_days =
        r.post_low_down_days,

    post_low_flat_days =
        r.post_low_flat_days,

    avg_up_volume =
        r.avg_up_volume,

    avg_down_volume =
        r.avg_down_volume,

    down_vs_up_volume_ratio =
        r.down_vs_up_volume_ratio,

    up_vs_down_volume_ratio =
        r.up_vs_down_volume_ratio

FROM resolved r

WHERE t.security_id = r.security_id
  AND t.trade_date = r.trade_date;