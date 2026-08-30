-- ============================================================================
-- MomentumLab
-- Feature     : BQ06 - Setup Maturity
-- File        : 036_bq06_setup_maturity.sql
-- Version     : 2.0
--
-- Purpose:
--   Measure how developed the base is as of trade_date.
--
-- Raw features:
--   - base_age_sessions
--   - base_maturity_ratio_pct
--
-- Scope:
--   NIFTY_100
--   Selected evaluation date
-- ============================================================================

WITH params AS
(
    SELECT DATE '2026-08-13' AS evaluation_date
),

candidates AS
(
    SELECT
        q.security_id,
        s.symbol,
        q.trade_date,
        q.prior_swing_high_date,
        q.post_low_sessions

    FROM trn.stock_base_quality_daily q

    JOIN ref.ref_nse_equity_security s
      ON s.security_id = q.security_id

    JOIN ref.security_universe_membership um
      ON um.security_id = q.security_id
     AND um.universe_code = 'NIFTY_100'

    CROSS JOIN params p

    WHERE q.trade_date = p.evaluation_date
),

maturity AS
(
    SELECT
        c.security_id,
        c.trade_date,
        c.post_low_sessions,

        COUNT(*) AS base_age_sessions

    FROM candidates c

    JOIN trn.nse_sec_bhavdata b
      ON b.symbol = c.symbol
     AND b.series = 'EQ'
     AND b.traded_date BETWEEN c.prior_swing_high_date
                           AND c.trade_date

    GROUP BY
        c.security_id,
        c.trade_date,
        c.post_low_sessions
),

resolved AS
(
    SELECT
        security_id,
        trade_date,
        base_age_sessions,

        ROUND(
            (
                post_low_sessions * 100.0
                / NULLIF(base_age_sessions, 0)
            )::numeric,
            4
        ) AS base_maturity_ratio_pct

    FROM maturity
)

UPDATE trn.stock_base_quality_daily t

SET
    base_age_sessions =
        r.base_age_sessions,

    base_maturity_ratio_pct =
        r.base_maturity_ratio_pct

FROM resolved r

CROSS JOIN params p

WHERE t.security_id = r.security_id
  AND t.trade_date  = r.trade_date
  AND t.trade_date  = p.evaluation_date;