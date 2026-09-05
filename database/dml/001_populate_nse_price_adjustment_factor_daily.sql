-- ============================================================================
-- MomentumLab
-- File        : 001_populate_nse_price_adjustment_factor_daily.sql
-- Purpose     : Rebuild sparse daily cumulative historical price-adjustment
--               factors from deterministic corporate-action events.
--
-- Semantics:
--   For a trading date D, include all adjustment events where:
--
--       D < ex_date
--
--   Multiple applicable events are compounded multiplicatively.
--
--   Only stock-dates with at least one contributing future adjustment event
--   are stored. Missing rows are interpreted downstream as factor = 1.
--
--   This script is intended to be idempotent.
-- ============================================================================

BEGIN;

TRUNCATE TABLE trn.nse_price_adjustment_factor_daily;

INSERT INTO trn.nse_price_adjustment_factor_daily
(
    traded_date,
    symbol,
    price_adjustment_factor,
    contributing_event_count,
    calculated_date
)
SELECT
    b.traded_date,
    b.symbol,

    ROUND(
        EXP(
            SUM(
                LN(e.price_factor)
            )
        )::numeric,
        10
    ) AS price_adjustment_factor,

    COUNT(*)::integer AS contributing_event_count,

    CURRENT_TIMESTAMP AS calculated_date

FROM trn.nse_sec_bhavdata b

JOIN trn.nse_price_adjustment_event e
  ON e.symbol = b.symbol
 AND b.traded_date < e.ex_date

WHERE b.series = 'EQ'

GROUP BY
    b.traded_date,
    b.symbol

ORDER BY
    b.traded_date,
    b.symbol;

COMMIT;