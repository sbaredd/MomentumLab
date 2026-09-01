-- ============================================================================
-- MomentumLab
-- Feature     : SR01 - Breakout State
-- File        : 046_sr01_breakout_state.sql
-- Version     : 1.0
-- Description : Classifies the evaluation session's behaviour relative
--               to the frozen structural pivot.
--
-- States:
--   NO_ACTIVE_PIVOT
--   BELOW_PIVOT
--   AT_PIVOT
--   INTRADAY_CROSS_ONLY
--   CROSSED_AND_CLOSED_ABOVE
-- ============================================================================

WITH params AS
(
    SELECT DATE '2026-08-13' AS evaluation_date
),

source_data AS
(
    SELECT
        p.security_id,
        p.trade_date,
        p.pivot_date,
        p.pivot_price,
        p.pivot_type,

        b.high_price,
        b.close_price,

        CASE
            WHEN p.pivot_price IS NULL
                THEN NULL

            ELSE
                ROUND(
                    ((b.high_price - p.pivot_price)
                    / NULLIF(p.pivot_price, 0)) * 100,
                    4
                )
        END AS high_vs_pivot_pct,

        CASE
            WHEN p.pivot_price IS NULL
                THEN NULL

            ELSE
                ROUND(
                    ((b.close_price - p.pivot_price)
                    / NULLIF(p.pivot_price, 0)) * 100,
                    4
                )
        END AS close_vs_pivot_pct

    FROM trn.stock_pivot_daily p

    JOIN ref.ref_nse_equity_security s
        ON s.security_id = p.security_id

    JOIN ref.security_universe_membership u
        ON u.security_id = p.security_id
       AND u.universe_code = 'NIFTY_100'

    JOIN trn.nse_sec_bhavdata b
        ON b.symbol = s.symbol
       AND b.traded_date = p.trade_date

    CROSS JOIN params x

    WHERE p.trade_date = x.evaluation_date
),

classified AS
(
    SELECT
        *,

        CASE
            WHEN pivot_price IS NULL
                THEN 'NO_ACTIVE_PIVOT'

            WHEN high_price < pivot_price
                THEN 'BELOW_PIVOT'

            WHEN high_price = pivot_price
                 AND close_price <= pivot_price
                THEN 'AT_PIVOT'

            WHEN high_price > pivot_price
                 AND close_price < pivot_price
                THEN 'INTRADAY_CROSS_ONLY'

            WHEN high_price >= pivot_price
                 AND close_price >= pivot_price
                THEN 'CROSSED_AND_CLOSED_ABOVE'

            ELSE 'BELOW_PIVOT'
        END AS breakout_state

    FROM source_data
)

INSERT INTO trn.stock_setup_readiness_daily
(
    security_id,
    trade_date,

    pivot_date,
    pivot_price,
    pivot_type,

    high_vs_pivot_pct,
    close_vs_pivot_pct,
    breakout_state,

    created_date
)

SELECT
    security_id,
    trade_date,

    pivot_date,
    pivot_price,
    pivot_type,

    high_vs_pivot_pct,
    close_vs_pivot_pct,
    breakout_state,

    CURRENT_TIMESTAMP

FROM classified

ON CONFLICT (security_id, trade_date)
DO UPDATE SET

    pivot_date =
        EXCLUDED.pivot_date,

    pivot_price =
        EXCLUDED.pivot_price,

    pivot_type =
        EXCLUDED.pivot_type,

    high_vs_pivot_pct =
        EXCLUDED.high_vs_pivot_pct,

    close_vs_pivot_pct =
        EXCLUDED.close_vs_pivot_pct,

    breakout_state =
        EXCLUDED.breakout_state,

    created_date =
        CURRENT_TIMESTAMP;