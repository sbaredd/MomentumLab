-- ============================================================================
-- MomentumLab
-- Feature     : SR04 - Breakout Extension
-- File        : 050_sr04_breakout_extension.sql
-- Version     : 1.2
-- Description : Measures price extension from the structural pivot,
--               normalized by ATR.
--
-- Historicalization changes:
--   - evaluation_date supplied externally.
--   - close_price sourced from bhavdata.
--
-- SR04 formulas unchanged.
-- ============================================================================

WITH params AS
(
    SELECT CAST(:evaluation_date AS DATE) AS evaluation_date
)

UPDATE trn.stock_setup_readiness_daily r

SET
    atr_pct = f.atr_pct,

    extension_from_pivot_pct =
        CASE
            WHEN r.pivot_price IS NULL
              OR r.pivot_price = 0
              OR b.close_price IS NULL
            THEN NULL

            ELSE ROUND(
                (
                    (b.close_price - r.pivot_price)
                    / r.pivot_price
                    * 100
                )::numeric,
                4
            )
        END,

    extension_atr_multiple =
        CASE
            WHEN r.pivot_price IS NULL
              OR r.pivot_price = 0
              OR b.close_price IS NULL
              OR f.atr_pct IS NULL
              OR f.atr_pct = 0
            THEN NULL

            ELSE ROUND(
                (
                    (
                        (b.close_price - r.pivot_price)
                        / r.pivot_price
                        * 100
                    )
                    / f.atr_pct
                )::numeric,
                4
            )
        END,

    created_date = CURRENT_TIMESTAMP

FROM ref.ref_nse_equity_security s
JOIN trn.stock_daily_features f
    ON f.symbol = s.symbol
JOIN trn.nse_sec_bhavdata b
    ON b.symbol = s.symbol
CROSS JOIN params p

WHERE r.security_id = s.security_id
  AND r.trade_date = p.evaluation_date
  AND f.trade_date = p.evaluation_date
  AND b.traded_date = p.evaluation_date;