-- ============================================================================
-- MomentumLab
-- SR10 - OUTCOME MATURITY DIAGNOSTIC
--
-- Purpose:
--   Determine how many RESOLVED_BREAKOUT episodes have accumulated the
--   complete 10-trading-session future window required for SR10 MFE
--   outcome evaluation.
--
-- Use:
--   Run after loading new market data to determine whether additional
--   episodes are available for out-of-sample SR10 validation.
--
-- Maturity rule:
--   MATURE   = exactly 10 future stock trading sessions available
--   IMMATURE = fewer than 10 future stock trading sessions available
--
-- This diagnostic does not calculate or optimize any SR10 hypothesis.
-- It only measures outcome availability.
-- ============================================================================

WITH breakout AS
(
    SELECT
        e.security_id,
        r.symbol,
        e.episode_end_date AS breakout_date,
        tc.trading_day_number AS breakout_day_number

    FROM trn.stock_setup_episode e

    JOIN ref.ref_nse_equity_security r
      ON r.security_id = e.security_id

    JOIN ref.trading_calendar tc
      ON tc.traded_date = e.episode_end_date

    WHERE e.episode_status = 'RESOLVED_BREAKOUT'
),

maturity AS
(
    SELECT
        br.security_id,
        br.symbol,
        br.breakout_date,

        COUNT(f.traded_date) AS future_session_count

    FROM breakout br

    LEFT JOIN ref.trading_calendar tc
      ON tc.trading_day_number
         BETWEEN br.breakout_day_number + 1
             AND br.breakout_day_number + 10

    LEFT JOIN trn.vw_nse_sec_bhavdata_adjusted f
      ON f.symbol = br.symbol
     AND f.traded_date = tc.traded_date
     AND f.series = 'EQ'

    GROUP BY
        br.security_id,
        br.symbol,
        br.breakout_date
)

SELECT
    COUNT(*) AS total_resolved_breakouts,

    COUNT(*) FILTER (
        WHERE future_session_count = 10
    ) AS mature_breakouts,

    COUNT(*) FILTER (
        WHERE future_session_count < 10
    ) AS immature_breakouts

FROM maturity;
