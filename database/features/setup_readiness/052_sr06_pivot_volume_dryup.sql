-- ============================================================================
-- MomentumLab
-- Feature     : SR06 - Pivot Volume Dry-Up
-- File        : 052_sr06_pivot_volume_dryup.sql
-- Version     : 1.1
-- Description : Measures pre-breakout volume contraction immediately before
--               the evaluation session.
--
-- Historicalization change:
--   - evaluation_date supplied externally.
--   - SR06 measurement logic unchanged from Version 1.0.
--
-- Measurements:
--   recent_5_avg_volume
--       Average volume of the 5 trading sessions immediately BEFORE
--       the evaluation date.
--
--   recent_5_volume_vs_20d_pct
--       Recent 5-session average volume as a percentage of the
--       prior 20-session average volume.
--
-- Important:
--   Evaluation / breakout session is EXCLUDED.
--
-- Raw measurements only.
-- No dry-up threshold or readiness state is imposed here.
-- ============================================================================

WITH params AS
(
    SELECT CAST(:evaluation_date AS DATE) AS evaluation_date
),

universe AS
(
    SELECT
        s.security_id,
        s.symbol

    FROM ref.security_universe_membership um

    JOIN ref.ref_nse_equity_security s
        ON s.security_id = um.security_id

    WHERE um.universe_code = 'NIFTY_100'
),

prior_sessions AS
(
    SELECT
        u.security_id,
        u.symbol,
        b.traded_date,
        b.traded_quantity,

        ROW_NUMBER() OVER
        (
            PARTITION BY u.security_id
            ORDER BY b.traded_date DESC
        ) AS rn

    FROM universe u

    JOIN trn.nse_sec_bhavdata b
        ON b.symbol = u.symbol
       AND b.series = 'EQ'

    CROSS JOIN params p

    WHERE b.traded_date < p.evaluation_date
),

measurements AS
(
    SELECT
        security_id,

        AVG(traded_quantity)
            FILTER (WHERE rn <= 5)
            AS recent_5_avg_volume,

        AVG(traded_quantity)
            FILTER (WHERE rn <= 20)
            AS prior_20_avg_volume,

        COUNT(*)
            FILTER (WHERE rn <= 5)
            AS recent_5_sessions,

        COUNT(*)
            FILTER (WHERE rn <= 20)
            AS prior_20_sessions

    FROM prior_sessions

    WHERE rn <= 20

    GROUP BY security_id
),

final_measurements AS
(
    SELECT
        security_id,

        recent_5_avg_volume,

        CASE
            WHEN prior_20_sessions = 20
             AND recent_5_sessions = 5
             AND prior_20_avg_volume > 0
            THEN
                (
                    recent_5_avg_volume
                    / prior_20_avg_volume
                ) * 100
            ELSE NULL
        END AS recent_5_volume_vs_20d_pct

    FROM measurements
)

UPDATE trn.stock_setup_readiness_daily r

SET
    recent_5_avg_volume =
        m.recent_5_avg_volume,

    recent_5_volume_vs_20d_pct =
        m.recent_5_volume_vs_20d_pct,

    created_date = CURRENT_TIMESTAMP

FROM final_measurements m
CROSS JOIN params p

WHERE r.security_id = m.security_id
  AND r.trade_date = p.evaluation_date;