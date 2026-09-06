-- ============================================================================
-- MomentumLab
-- SR10 - OUT-OF-SAMPLE H1 VALIDATION
--
-- Purpose:
--   Evaluate the first frozen SR10 out-of-sample cohort against the
--   previously frozen H1 hypothesis and canonical 10-session MFE outcome.
--
-- Frozen H1:
--   prebreakout_5d_return_pct > 0
--   AND recent_5_volume_vs_20d_pct >= 90
--
-- Frozen outcome:
--   MFE over the 10 trading sessions following breakout.
--   STRONG = MFE_10D >= 5%
--
-- OOS cohort 1:
--   Market-data extension: 2026-09-02 -> 2026-09-04
--   Episodes: 6
--
-- Observed result:
--   H1 BOTH      : 0
--   H1 NOT_BOTH  : 6
--   STRONG       : 2
--   OTHER        : 4
--
-- Validation conclusion:
--   INSUFFICIENT OOS EXPOSURE.
--
--   No H1-positive observations occurred in OOS cohort 1.
--   Therefore this cohort neither confirms nor rejects H1.
--
-- Research discipline:
--   H1 remains frozen.
--   Do not change the 90% volume threshold based on this cohort.
--   Do not optimize H1 using these observations.
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
        br.breakout_day_number,

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
        br.pivot_price,
        br.breakout_day_number
),

oos_cohort AS
(
    SELECT *
    FROM maturity
    WHERE sessions_by_sep02 < 10
      AND sessions_by_sep04 = 10
),

setup_features AS
(
    SELECT
        o.security_id,
        o.symbol,
        o.pivot_date,
        o.pivot_price,
        o.episode_start_date,
        o.breakout_date,
        o.breakout_day_number,

        s.prebreakout_5d_return_pct,
        s.recent_5_volume_vs_20d_pct

    FROM oos_cohort o

    JOIN trn.stock_setup_readiness_daily s
      ON s.security_id = o.security_id
     AND s.trade_date = o.breakout_date
     AND s.pivot_date = o.pivot_date
     AND s.pivot_price = o.pivot_price
),

breakout_price AS
(
    SELECT
        sf.*,
        b.adjusted_close_price AS breakout_close

    FROM setup_features sf

    JOIN trn.vw_nse_sec_bhavdata_adjusted b
      ON b.symbol = sf.symbol
     AND b.traded_date = sf.breakout_date
     AND b.series = 'EQ'
),

future_outcome AS
(
    SELECT
        bp.security_id,
        bp.symbol,
        bp.pivot_date,
        bp.pivot_price,
        bp.episode_start_date,
        bp.breakout_date,
        bp.prebreakout_5d_return_pct,
        bp.recent_5_volume_vs_20d_pct,
        bp.breakout_close,

        MAX(f.adjusted_high_price) AS max_high_10d,
        COUNT(f.traded_date) AS future_session_count

    FROM breakout_price bp

    JOIN ref.trading_calendar tc
      ON tc.trading_day_number
         BETWEEN bp.breakout_day_number + 1
             AND bp.breakout_day_number + 10

    JOIN trn.vw_nse_sec_bhavdata_adjusted f
      ON f.symbol = bp.symbol
     AND f.traded_date = tc.traded_date
     AND f.series = 'EQ'

    GROUP BY
        bp.security_id,
        bp.symbol,
        bp.pivot_date,
        bp.pivot_price,
        bp.episode_start_date,
        bp.breakout_date,
        bp.prebreakout_5d_return_pct,
        bp.recent_5_volume_vs_20d_pct,
        bp.breakout_close
)

SELECT
    symbol,
    pivot_date,
    pivot_price,
    episode_start_date,
    breakout_date,

    prebreakout_5d_return_pct,
    recent_5_volume_vs_20d_pct,

    CASE
        WHEN prebreakout_5d_return_pct > 0
         AND recent_5_volume_vs_20d_pct >= 90
        THEN 'BOTH'
        ELSE 'NOT_BOTH'
    END AS h1_classification,

    ROUND(breakout_close, 2) AS breakout_close,
    ROUND(max_high_10d, 2) AS max_high_10d,

    ROUND(
        ((max_high_10d / breakout_close) - 1) * 100,
        2
    ) AS mfe_10d_pct,

    CASE
        WHEN ((max_high_10d / breakout_close) - 1) * 100 >= 5
        THEN 'STRONG'
        ELSE 'OTHER'
    END AS outcome_class,

    future_session_count

FROM future_outcome

WHERE future_session_count = 10

ORDER BY breakout_date, symbol;