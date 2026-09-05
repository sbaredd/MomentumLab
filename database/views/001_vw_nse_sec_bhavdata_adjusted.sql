-- ============================================================================
-- MomentumLab
-- View        : trn.vw_nse_sec_bhavdata_adjusted
-- Description : Corporate-action-adjusted NSE daily price view
--
-- Raw NSE bhavdata remains immutable.
-- Historical OHLC prices are adjusted using the cumulative daily
-- price-adjustment factor derived from deterministic corporate actions.
-- ============================================================================

CREATE OR REPLACE VIEW trn.vw_nse_sec_bhavdata_adjusted AS

SELECT
    b.traded_date,
    b.symbol,
    b.series,
    b.prev_close,
    b.open_price,
    b.high_price,
    b.low_price,
    b.last_price,
    b.close_price,
    b.avg_price,
    b.traded_quantity,
    b.turnover_lacs,
    b.no_of_trades,
    b.delivery_quantity,
    b.delivery_percent,

    COALESCE(
        f.price_adjustment_factor,
        1::numeric
    ) AS price_adjustment_factor,

    ROUND(
        b.open_price * COALESCE(f.price_adjustment_factor, 1::numeric),
        4
    ) AS adjusted_open_price,

    ROUND(
        b.high_price * COALESCE(f.price_adjustment_factor, 1::numeric),
        4
    ) AS adjusted_high_price,

    ROUND(
        b.low_price * COALESCE(f.price_adjustment_factor, 1::numeric),
        4
    ) AS adjusted_low_price,

    ROUND(
        b.close_price * COALESCE(f.price_adjustment_factor, 1::numeric),
        4
    ) AS adjusted_close_price

FROM trn.nse_sec_bhavdata b

LEFT JOIN trn.nse_price_adjustment_factor_daily f
       ON f.traded_date = b.traded_date
      AND f.symbol = b.symbol;