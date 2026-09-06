-- ============================================================================
-- MomentumLab
-- SR10 - OUT-OF-SAMPLE COHORT
--
-- Purpose:
--   Identify RESOLVED_BREAKOUT episodes that were not outcome-mature at the
--   original SR10 research cutoff (2026-09-02), but became outcome-mature
--   after market data was extended through 2026-09-04.
--
-- Research discipline:
--   The original SR10 development population contained 32 mature episodes.
--   H1 was developed and frozen on that population.
--
--   This file defines the first out-of-sample (OOS) validation cohort.
--   The cohort must be identified and preserved BEFORE examining H1
--   classifications or MFE outcomes.
--
-- Expected cohort:
--   6 episodes
--
-- IMPORTANT:
--   Do not add H1 classification, MFE calculations, outcome labels,
--   or threshold optimization to this file.
-- ============================================================================

WITH breakout AS
(
    SELECT
        e.security_id,
        r.symbol,
        e.episode_start_date,
        e.episode_end_date AS breakout_date,
        e.pivot_date,
        e.pivot_price,
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
        br.episode_start_date,
        br.breakout_date,
        br.pivot_date,
        br.pivot_price,

        COUNT(f.traded_date) FILTER (
            WHERE f.traded_date <= DATE '2026-09-02'
        ) AS sessions_by_sep02,

        COUNT(f.traded_date) FILTER (
            WHERE f.traded_date <= DATE '2026-09-04'
        ) AS sessions_by_sep04

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
        br.episode_start_date,
        br.breakout_date,
        br.pivot_date,
        br.pivot_price
)

SELECT
    security_id,
    symbol,
    pivot_date,
    pivot_price,
    episode_start_date,
    breakout_date,
    sessions_by_sep02,
    sessions_by_sep04

FROM maturity

WHERE sessions_by_sep02 < 10
  AND sessions_by_sep04 = 10

ORDER BY breakout_date, symbol;
