-- ============================================================================
-- MomentumLab
-- SR10 - H2: 52-WEEK-HIGH PROXIMITY
--
-- Purpose:
--   Test whether proximity to the 52-week high at breakout is associated
--   with stronger post-breakout expansion.
--
-- Outcome:
--   Maximum Favorable Excursion (MFE) over the next 10 trading sessions.
--
-- Strong-breakout research label:
--   MFE_10D >= 5%
--
-- Price basis:
--   Corporate-action-adjusted OHLC.
--
-- Population:
--   Mature RESOLVED_BREAKOUT episodes with valid highest_high_252.
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
        b.adjusted_close_price AS breakout_close,
        f.highest_high_252,

        (
            b.adjusted_close_price
            / f.highest_high_252
            - 1
        ) * 100 AS pct_from_52w_high

    FROM trn.stock_setup_episode e

    JOIN ref.ref_nse_equity_security r
      ON r.security_id = e.security_id

    JOIN ref.trading_calendar tc
      ON tc.traded_date = e.episode_end_date

    JOIN trn.vw_nse_sec_bhavdata_adjusted b
      ON b.symbol = r.symbol
     AND b.traded_date = e.episode_end_date
     AND b.series = 'EQ'

    JOIN trn.stock_daily_features f
      ON f.symbol = r.symbol
     AND f.trade_date = e.episode_end_date

    WHERE e.episode_status = 'RESOLVED_BREAKOUT'
      AND f.highest_high_252 IS NOT NULL
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
        br.pct_from_52w_high,

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
        br.breakout_close,
        br.pct_from_52w_high
),

mature AS
(
    SELECT
        *,
        (
            max_future_high / breakout_close
            - 1
        ) * 100 AS mfe_10d_pct

    FROM future_10

    WHERE future_session_count = 10
)

SELECT
    symbol,
    breakout_date,

    ROUND(
        pct_from_52w_high,
        2
    ) AS pct_from_52w_high,

    ROUND(
        mfe_10d_pct,
        2
    ) AS mfe_10d_pct,

    CASE
        WHEN mfe_10d_pct >= 5
            THEN 'STRONG'
        ELSE 'OTHER'
    END AS outcome

FROM mature

ORDER BY mfe_10d_pct DESC;