-- ============================================================================
-- MomentumLab
-- Base Quality Validation
-- Diagnostic 1E: Post-Low Volume Behaviour
--
-- Purpose:
--   Determine whether volume behaviour becomes constructive after the
--   base low as the stock develops the right side of the base.
--
-- Definition:
--   Post-Low Session = sessions AFTER base_low_date
--                      through as_of_date inclusive
--
-- Interpretation:
--   We want to know whether advancing sessions attract stronger volume
--   than declining sessions.
--
-- NO SCORING YET
-- ============================================================================

WITH current_candidates
(
    symbol,
    base_start_date,
    base_start_high,
    base_low_date,
    base_low
) AS
(
    VALUES
        ('5PAISA',     DATE '2026-07-27', 381.95,  DATE '2026-07-30', 344.00),
        ('CHENNPETRO', DATE '2026-07-23', 1354.00, DATE '2026-07-28', 1150.00),
        ('DEEPINDS',   DATE '2026-07-20', 487.00,  DATE '2026-07-24', 453.60),
        ('KTKBANK',    DATE '2026-07-15', 280.00,  DATE '2026-07-17', 268.35)
),

post_low_data AS
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

    JOIN trn.nse_sec_bhavdata b
      ON b.symbol = c.symbol
     AND b.series = 'EQ'
     AND b.traded_date >= c.base_low_date
     AND b.traded_date <= DATE '2026-08-13'
),

classified_data AS
(
    SELECT
        symbol,
        traded_date,
        close_price,
        traded_quantity,

        CASE
            WHEN close_price > prev_close THEN 'UP'
            WHEN close_price < prev_close THEN 'DOWN'
            ELSE 'FLAT'
        END AS day_direction

    FROM post_low_data

    -- Removes base-low session itself.
    -- It is included above only so LAG() can provide the
    -- correct previous close for the first post-low session.
    WHERE traded_date > base_low_date
)

SELECT
    symbol,

    COUNT(*) AS post_low_sessions,

    COUNT(*) FILTER
        (WHERE day_direction = 'UP') AS up_days,

    COUNT(*) FILTER
        (WHERE day_direction = 'DOWN') AS down_days,

    COUNT(*) FILTER
        (WHERE day_direction = 'FLAT') AS flat_days,

    ROUND(
        AVG(traded_quantity)
        FILTER (WHERE day_direction = 'UP'),
        0
    ) AS avg_up_volume,

    ROUND(
        AVG(traded_quantity)
        FILTER (WHERE day_direction = 'DOWN'),
        0
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
        2
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
        2
    ) AS up_vs_down_volume_ratio

FROM classified_data

GROUP BY symbol

ORDER BY symbol;