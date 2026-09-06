-- ============================================================================
-- MomentumLab
-- SR10 - 10-TRADING-SESSION MFE OUTCOME
--
-- Purpose:
--   Construct the canonical SR10 post-breakout outcome.
--
-- Outcome:
--   Maximum Favorable Excursion (MFE) over the 10 trading sessions
--   following a RESOLVED_BREAKOUT episode.
--
-- Strong-breakout research label:
--   MFE_10D >= 5%
--
-- Price basis:
--   Corporate-action-adjusted OHLC.
--
-- Maturity requirement:
--   Exactly 10 future trading sessions must be available.
-- ============================================================================

WITH breakout AS
(
    SELECT
        e.security_id,
        r.symbol,
        e.pivot_date,
        e.episode_start_date,
        e.episode_end_date AS breakout_date,
        tc.trading_day_number AS breakout_day_number,
        b.adjusted_close_price AS breakout_close

    FROM trn.stock_setup_episode e

    JOIN ref.ref_nse_equity_security r
      ON r.security_id = e.security_id

    JOIN ref.trading_calendar tc
      ON tc.traded_date = e.episode_end_date

    JOIN trn.vw_nse_sec_bhavdata_adjusted b
      ON b.symbol = r.symbol
     AND b.traded_date = e.episode_end_date
     AND b.series = 'EQ'

    WHERE e.episode_status = 'RESOLVED_BREAKOUT'
),

future_10 AS
(
    SELECT
        br.security_id,
        br.symbol,
        br.pivot_date,
        br.episode_start_date,
        br.breakout_date,
        br.breakout_close,

        COUNT(*) AS future_session_count,

        MAX(f.adjusted_high_price) AS max_future_high

    FROM breakout br

    JOIN ref.trading_calendar tc
      ON tc.trading_day_number
         BETWEEN br.breakout_day_number + 1
             AND br.breakout_day_number + 10

    JOIN trn.vw_nse_sec_bhavdata_adjusted f
      ON f.symbol = br.symbol
     AND f.traded_date = tc.traded_date
     AND f.series = 'EQ'

    GROUP BY
        br.security_id,
        br.symbol,
        br.pivot_date,
        br.episode_start_date,
        br.breakout_date,
        br.breakout_close
)

SELECT
    COUNT(*) AS mature_breakouts,

    ROUND(
        AVG(
            (
                max_future_high / breakout_close
                - 1
            ) * 100
        ),
        2
    ) AS avg_mfe_10d_pct,

    COUNT(*) FILTER
    (
        WHERE
            (
                max_future_high / breakout_close
                - 1
            ) * 100 >= 5
    ) AS strong_breakouts

FROM future_10

WHERE future_session_count = 10;