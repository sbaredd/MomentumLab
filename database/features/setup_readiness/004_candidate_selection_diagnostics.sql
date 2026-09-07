-- ============================================================================
-- MomentumLab
-- Candidate Selection Diagnostics
-- File        : 004_candidate_selection_diagnostics.sql
-- Purpose     : Research diagnostics for candidate selection / ranking
-- Scope       : Read-only analysis only; no production scoring or gating
--
-- Current research findings:
--
-- 1. SR02 pivot proximity is a strong ordinal breakout-readiness signal.
--    Historical 5-session breakout conversion by first actionable proximity:
--
--      0 to 1% below pivot : 46.88%   (15 / 32)
--      1 to 2% below pivot : 29.79%   (14 / 47)
--      2 to 3% below pivot : 26.53%   (13 / 49)
--      3 to 4% below pivot : 19.51%   ( 8 / 41)
--
--    Canonical population:
--      169 first-actionable setup episodes
--      50 five-session breakouts
--      29.59% baseline breakout rate
--
-- 2. SR02A pivot proximity direction is a useful trajectory discriminator,
--    but must not be used as a hard Candidate Selection gate.
--
--    First actionable observation where SR02A is available:
--
--      APPROACHING_PIVOT      : 35.71%   (25 / 70)
--      RETREATING_FROM_PIVOT  : 20.63%   (13 / 63)
--      UNCHANGED              : 33.33%   ( 1 /  3) -- tiny sample
--
--    SR02A therefore answers a different question from SR02:
--      SR02  -> Where is the setup relative to the pivot?
--      SR02A -> Is the setup currently moving toward or away from the pivot?
--
-- 3. H1_PASS must not be used as a Candidate Selection gate.
--    Some H1_FAIL + APPROACHING setups produced strong breakout conversion.
--
-- 4. SR05 close tightness does not show a monotonic "tighter is better"
--    relationship. Do not use it as a ranking bonus yet.
--
-- 5. Absolute recent_5_range_pct is strongly related to ATR.
--    Therefore raw range should not be interpreted without volatility
--    normalization.
--
-- 6. Promising research hypothesis:
--
--      pivot_proximity_pct >= -2
--      AND recent_5_range_pct / atr_pct between 2.5 and 3.0
--
--    Observed result:
--      10 episodes
--      8 breakouts within 5 trading sessions
--      80.00% conversion
--
--    IMPORTANT:
--      - Sample size is small.
--      - All observations come from readiness history beginning 2026-08-03.
--      - This result is NOT temporally validated.
--      - Do not promote to production threshold or ranking weight yet.
--
-- Architecture principle:
--   Eligibility  -> whether setup should be considered
--   Quality      -> structural/readiness context
--   Trajectory   -> what setup is doing now
--   Ranking      -> later stage; do not collapse all features into one score
--
-- ============================================================================
-- ============================================================================
-- DIAGNOSTIC 1
-- First actionable observation per setup episode
--
-- Definition:
--   First readiness observation within:
--       -4% <= pivot_proximity_pct < 0%
--
-- Method:
--   One row per natural setup episode:
--       security_id
--       pivot_date
--       pivot_price
--       episode_start_date
--
-- Outcome:
--   Breakout within the next 5 trading sessions if breakout_state becomes:
--       INTRADAY_CROSS_ONLY
--       CROSSED_AND_CLOSED_ABOVE
--
-- Important:
--   Classification is performed AFTER selecting the first actionable
--   observation. This avoids repeatedly counting the same setup as it evolves.
-- ============================================================================

WITH actionable AS
(
    SELECT
        e.security_id,
        e.pivot_date,
        e.pivot_price,
        e.episode_start_date,
        e.episode_end_date,

        r.trade_date,
        r.pivot_proximity_pct,
        r.recent_5_range_pct,
        r.atr_pct,
        r.recent_5_close_tightness_pct,
        r.pivot_proximity_direction,

        ROW_NUMBER() OVER
        (
            PARTITION BY
                e.security_id,
                e.pivot_date,
                e.pivot_price,
                e.episode_start_date
            ORDER BY
                r.trade_date
        ) AS rn

    FROM trn.stock_setup_episode e

    JOIN trn.stock_setup_readiness_daily r
      ON r.security_id = e.security_id
     AND r.pivot_date   = e.pivot_date
     AND r.pivot_price  = e.pivot_price
     AND r.trade_date  >= e.episode_start_date
     AND
        (
            e.episode_end_date IS NULL
            OR r.trade_date <= e.episode_end_date
        )

    WHERE r.pivot_proximity_pct >= -4
      AND r.pivot_proximity_pct < 0
),
first_actionable AS
(
    SELECT *
    FROM actionable
    WHERE rn = 1
)
SELECT
    COUNT(*) AS first_actionable_episodes,
    MIN(trade_date) AS first_observation_date,
    MAX(trade_date) AS last_observation_date
FROM first_actionable;

-- ============================================================================
-- DIAGNOSTIC 2
-- Five-trading-session breakout outcome from first actionable observation
--
-- Population:
--   One first actionable observation per setup episode from Diagnostic 1.
--
-- Outcome:
--   BREAKOUT if the same pivot records either:
--       INTRADAY_CROSS_ONLY
--       CROSSED_AND_CLOSED_ABOVE
--   during trading sessions +1 through +5.
-- ============================================================================

WITH actionable AS
(
    SELECT
        e.security_id,
        e.pivot_date,
        e.pivot_price,
        e.episode_start_date,
        e.episode_end_date,

        r.trade_date,
        r.pivot_proximity_pct,
        r.recent_5_range_pct,
        r.atr_pct,
        r.recent_5_close_tightness_pct,
        r.pivot_proximity_direction,

        ROW_NUMBER() OVER
        (
            PARTITION BY
                e.security_id,
                e.pivot_date,
                e.pivot_price,
                e.episode_start_date
            ORDER BY r.trade_date
        ) AS rn

    FROM trn.stock_setup_episode e

    JOIN trn.stock_setup_readiness_daily r
      ON r.security_id = e.security_id
     AND r.pivot_date  = e.pivot_date
     AND r.pivot_price = e.pivot_price
     AND r.trade_date >= e.episode_start_date
     AND
        (
            e.episode_end_date IS NULL
            OR r.trade_date <= e.episode_end_date
        )

    WHERE r.pivot_proximity_pct >= -4
      AND r.pivot_proximity_pct < 0
),
first_actionable AS
(
    SELECT *
    FROM actionable
    WHERE rn = 1
),
entry_calendar AS
(
    SELECT
        f.*,
        c.trading_day_number AS entry_trading_day_number
    FROM first_actionable f
    JOIN ref.trading_calendar c
      ON c.traded_date = f.trade_date
),
outcomes AS
(
    SELECT
        e.*,

        EXISTS
        (
            SELECT 1
            FROM trn.stock_setup_readiness_daily future_r

            JOIN ref.trading_calendar future_c
              ON future_c.traded_date = future_r.trade_date

            WHERE future_r.security_id = e.security_id
              AND future_r.pivot_date  = e.pivot_date
              AND future_r.pivot_price = e.pivot_price

              AND future_c.trading_day_number
                    BETWEEN e.entry_trading_day_number + 1
                        AND e.entry_trading_day_number + 5

              AND future_r.breakout_state IN
                  (
                      'INTRADAY_CROSS_ONLY',
                      'CROSSED_AND_CLOSED_ABOVE'
                  )
        ) AS breakout_within_5_sessions

    FROM entry_calendar e
)
SELECT
    COUNT(*) AS total_episodes,

    COUNT(*) FILTER
    (
        WHERE breakout_within_5_sessions
    ) AS breakout_episodes,

    COUNT(*) FILTER
    (
        WHERE NOT breakout_within_5_sessions
    ) AS no_breakout_episodes,

    ROUND
    (
        100.0 *
        COUNT(*) FILTER (WHERE breakout_within_5_sessions)
        / NULLIF(COUNT(*), 0),
        2
    ) AS breakout_rate_pct

FROM outcomes;

-- ============================================================================
-- DIAGNOSTIC 3
-- SR02 pivot proximity vs five-session breakout probability
--
-- Question:
--   Does proximity to the pivot discriminate breakout probability?
--
-- Method:
--   - Same first-actionable episode population as Diagnostics 1 and 2.
--   - Classify proximity only AFTER selecting the first actionable row.
--   - Same +1 through +5 trading-session breakout definition.
--
-- Expected reconciliation:
--   Total episode count across all four bands should equal Diagnostic 2's
--   canonical population of 169 episodes.
-- ============================================================================

WITH actionable AS
(
    SELECT
        e.security_id,
        e.pivot_date,
        e.pivot_price,
        e.episode_start_date,
        e.episode_end_date,

        r.trade_date,
        r.pivot_proximity_pct,

        ROW_NUMBER() OVER
        (
            PARTITION BY
                e.security_id,
                e.pivot_date,
                e.pivot_price,
                e.episode_start_date
            ORDER BY r.trade_date
        ) AS rn

    FROM trn.stock_setup_episode e

    JOIN trn.stock_setup_readiness_daily r
      ON r.security_id = e.security_id
     AND r.pivot_date  = e.pivot_date
     AND r.pivot_price = e.pivot_price
     AND r.trade_date >= e.episode_start_date
     AND
        (
            e.episode_end_date IS NULL
            OR r.trade_date <= e.episode_end_date
        )

    WHERE r.pivot_proximity_pct >= -4
      AND r.pivot_proximity_pct < 0
),
first_actionable AS
(
    SELECT *
    FROM actionable
    WHERE rn = 1
),
entry_calendar AS
(
    SELECT
        f.*,
        c.trading_day_number AS entry_trading_day_number
    FROM first_actionable f

    JOIN ref.trading_calendar c
      ON c.traded_date = f.trade_date
),
outcomes AS
(
    SELECT
        e.*,

        EXISTS
        (
            SELECT 1

            FROM trn.stock_setup_readiness_daily future_r

            JOIN ref.trading_calendar future_c
              ON future_c.traded_date = future_r.trade_date

            WHERE future_r.security_id = e.security_id
              AND future_r.pivot_date  = e.pivot_date
              AND future_r.pivot_price = e.pivot_price

              AND future_c.trading_day_number
                    BETWEEN e.entry_trading_day_number + 1
                        AND e.entry_trading_day_number + 5

              AND future_r.breakout_state IN
                  (
                      'INTRADAY_CROSS_ONLY',
                      'CROSSED_AND_CLOSED_ABOVE'
                  )
        ) AS breakout_within_5_sessions

    FROM entry_calendar e
),
classified AS
(
    SELECT
        *,
        CASE
            WHEN pivot_proximity_pct >= -1
                THEN '0_TO_1PCT'

            WHEN pivot_proximity_pct >= -2
                THEN '1_TO_2PCT'

            WHEN pivot_proximity_pct >= -3
                THEN '2_TO_3PCT'

            ELSE '3_TO_4PCT'
        END AS proximity_band

    FROM outcomes
)
SELECT
    proximity_band,

    COUNT(*) AS episodes,

    COUNT(*) FILTER
    (
        WHERE breakout_within_5_sessions
    ) AS breakouts,

    COUNT(*) FILTER
    (
        WHERE NOT breakout_within_5_sessions
    ) AS no_breakouts,

    ROUND
    (
        100.0 *
        COUNT(*) FILTER (WHERE breakout_within_5_sessions)
        / NULLIF(COUNT(*), 0),
        2
    ) AS breakout_rate_pct

FROM classified

GROUP BY proximity_band

ORDER BY
    CASE proximity_band
        WHEN '0_TO_1PCT' THEN 1
        WHEN '1_TO_2PCT' THEN 2
        WHEN '2_TO_3PCT' THEN 3
        WHEN '3_TO_4PCT' THEN 4
    END;
-- ============================================================================
-- DIAGNOSTIC 4
-- SR02A pivot proximity direction vs five-session breakout probability
--
-- Question:
--   At the first actionable observation, does the direction of movement
--   relative to the pivot discriminate five-session breakout probability?
--
-- Method:
--   - Same canonical first-actionable episode population.
--   - SR02A direction is taken from the first actionable row.
--   - Same +1 through +5 trading-session breakout definition.
--   - NULL direction is retained explicitly rather than discarded.
-- ============================================================================

WITH actionable AS
(
    SELECT
        e.security_id,
        e.pivot_date,
        e.pivot_price,
        e.episode_start_date,
        e.episode_end_date,

        r.trade_date,
        r.pivot_proximity_pct,
        r.pivot_proximity_change_1d_pct,
        r.pivot_proximity_direction,

        ROW_NUMBER() OVER
        (
            PARTITION BY
                e.security_id,
                e.pivot_date,
                e.pivot_price,
                e.episode_start_date
            ORDER BY r.trade_date
        ) AS rn

    FROM trn.stock_setup_episode e

    JOIN trn.stock_setup_readiness_daily r
      ON r.security_id = e.security_id
     AND r.pivot_date  = e.pivot_date
     AND r.pivot_price = e.pivot_price
     AND r.trade_date >= e.episode_start_date
     AND
        (
            e.episode_end_date IS NULL
            OR r.trade_date <= e.episode_end_date
        )

    WHERE r.pivot_proximity_pct >= -4
      AND r.pivot_proximity_pct < 0
),
first_actionable AS
(
    SELECT *
    FROM actionable
    WHERE rn = 1
),
entry_calendar AS
(
    SELECT
        f.*,
        c.trading_day_number AS entry_trading_day_number

    FROM first_actionable f

    JOIN ref.trading_calendar c
      ON c.traded_date = f.trade_date
),
outcomes AS
(
    SELECT
        e.*,

        EXISTS
        (
            SELECT 1

            FROM trn.stock_setup_readiness_daily future_r

            JOIN ref.trading_calendar future_c
              ON future_c.traded_date = future_r.trade_date

            WHERE future_r.security_id = e.security_id
              AND future_r.pivot_date  = e.pivot_date
              AND future_r.pivot_price = e.pivot_price

              AND future_c.trading_day_number
                    BETWEEN e.entry_trading_day_number + 1
                        AND e.entry_trading_day_number + 5

              AND future_r.breakout_state IN
                  (
                      'INTRADAY_CROSS_ONLY',
                      'CROSSED_AND_CLOSED_ABOVE'
                  )
        ) AS breakout_within_5_sessions

    FROM entry_calendar e
)
SELECT
    COALESCE
    (
        pivot_proximity_direction,
        'NO_COMPARABLE_PREVIOUS_SESSION'
    ) AS direction,

    COUNT(*) AS episodes,

    COUNT(*) FILTER
    (
        WHERE breakout_within_5_sessions
    ) AS breakouts,

    COUNT(*) FILTER
    (
        WHERE NOT breakout_within_5_sessions
    ) AS no_breakouts,

    ROUND
    (
        100.0 *
        COUNT(*) FILTER (WHERE breakout_within_5_sessions)
        / NULLIF(COUNT(*), 0),
        2
    ) AS breakout_rate_pct

FROM outcomes

GROUP BY
    COALESCE
    (
        pivot_proximity_direction,
        'NO_COMPARABLE_PREVIOUS_SESSION'
    )

ORDER BY episodes DESC;
-- ============================================================================
-- DIAGNOSTIC 5
-- SR02A direction from first actionable observation where direction is available
--
-- Question:
--   Once trajectory becomes observable, does APPROACHING_PIVOT have a higher
--   five-session breakout probability than RETREATING_FROM_PIVOT?
--
-- Method:
--   - Remain inside actionable zone: -4% <= proximity < 0%.
--   - Require SR02A direction to be non-NULL.
--   - Select the FIRST such observation per natural setup episode.
--   - Count each episode only once.
--   - Measure breakout during sessions +1 through +5 from that observation.
-- ============================================================================

WITH direction_available AS
(
    SELECT
        e.security_id,
        e.pivot_date,
        e.pivot_price,
        e.episode_start_date,
        e.episode_end_date,

        r.trade_date,
        r.pivot_proximity_pct,
        r.pivot_proximity_change_1d_pct,
        r.pivot_proximity_direction,

        ROW_NUMBER() OVER
        (
            PARTITION BY
                e.security_id,
                e.pivot_date,
                e.pivot_price,
                e.episode_start_date
            ORDER BY r.trade_date
        ) AS rn

    FROM trn.stock_setup_episode e

    JOIN trn.stock_setup_readiness_daily r
      ON r.security_id = e.security_id
     AND r.pivot_date  = e.pivot_date
     AND r.pivot_price = e.pivot_price
     AND r.trade_date >= e.episode_start_date
     AND (
            e.episode_end_date IS NULL
            OR r.trade_date <= e.episode_end_date
         )

    WHERE r.pivot_proximity_pct >= -4
      AND r.pivot_proximity_pct < 0
      AND r.pivot_proximity_direction IS NOT NULL
),
first_direction_observation AS
(
    SELECT *
    FROM direction_available
    WHERE rn = 1
),
entry_calendar AS
(
    SELECT
        f.*,
        c.trading_day_number AS entry_trading_day_number

    FROM first_direction_observation f

    JOIN ref.trading_calendar c
      ON c.traded_date = f.trade_date
),
outcomes AS
(
    SELECT
        e.*,

        EXISTS
        (
            SELECT 1
            FROM trn.stock_setup_readiness_daily future_r

            JOIN ref.trading_calendar future_c
              ON future_c.traded_date = future_r.trade_date

            WHERE future_r.security_id = e.security_id
              AND future_r.pivot_date  = e.pivot_date
              AND future_r.pivot_price = e.pivot_price

              AND future_c.trading_day_number
                    BETWEEN e.entry_trading_day_number + 1
                        AND e.entry_trading_day_number + 5

              AND future_r.breakout_state IN
                  (
                      'INTRADAY_CROSS_ONLY',
                      'CROSSED_AND_CLOSED_ABOVE'
                  )
        ) AS breakout_within_5_sessions

    FROM entry_calendar e
)
SELECT
    pivot_proximity_direction AS direction,

    COUNT(*) AS episodes,

    COUNT(*) FILTER
    (
        WHERE breakout_within_5_sessions
    ) AS breakouts,

    COUNT(*) FILTER
    (
        WHERE NOT breakout_within_5_sessions
    ) AS no_breakouts,

    ROUND
    (
        100.0 *
        COUNT(*) FILTER (WHERE breakout_within_5_sessions)
        / NULLIF(COUNT(*), 0),
        2
    ) AS breakout_rate_pct

FROM outcomes

GROUP BY pivot_proximity_direction
ORDER BY episodes DESC;
-- ============================================================================
-- DIAGNOSTIC 6
-- SR02 proximity x SR02A direction interaction
--
-- Question:
--   Once SR02A direction is observable, does being closer to the pivot
--   strengthen the predictive value of APPROACHING_PIVOT?
--
-- Method:
--   - Use the first actionable observation per episode where SR02A is available.
--   - Classify proximity at that SAME observation.
--   - Proximity bands:
--         WITHIN_2PCT          : -2% <= proximity < 0%
--         BETWEEN_2_AND_4PCT   : -4% <= proximity < -2%
--   - Same +1 through +5 trading-session breakout outcome.
-- ============================================================================

WITH direction_available AS
(
    SELECT
        e.security_id,
        e.pivot_date,
        e.pivot_price,
        e.episode_start_date,
        e.episode_end_date,

        r.trade_date,
        r.pivot_proximity_pct,
        r.pivot_proximity_direction,

        ROW_NUMBER() OVER
        (
            PARTITION BY
                e.security_id,
                e.pivot_date,
                e.pivot_price,
                e.episode_start_date
            ORDER BY r.trade_date
        ) AS rn

    FROM trn.stock_setup_episode e

    JOIN trn.stock_setup_readiness_daily r
      ON r.security_id = e.security_id
     AND r.pivot_date  = e.pivot_date
     AND r.pivot_price = e.pivot_price
     AND r.trade_date >= e.episode_start_date
     AND
        (
            e.episode_end_date IS NULL
            OR r.trade_date <= e.episode_end_date
        )

    WHERE r.pivot_proximity_pct >= -4
      AND r.pivot_proximity_pct < 0
      AND r.pivot_proximity_direction IS NOT NULL
),
first_direction_observation AS
(
    SELECT *
    FROM direction_available
    WHERE rn = 1
),
entry_calendar AS
(
    SELECT
        f.*,
        c.trading_day_number AS entry_trading_day_number

    FROM first_direction_observation f

    JOIN ref.trading_calendar c
      ON c.traded_date = f.trade_date
),
outcomes AS
(
    SELECT
        e.*,

        EXISTS
        (
            SELECT 1

            FROM trn.stock_setup_readiness_daily future_r

            JOIN ref.trading_calendar future_c
              ON future_c.traded_date = future_r.trade_date

            WHERE future_r.security_id = e.security_id
              AND future_r.pivot_date  = e.pivot_date
              AND future_r.pivot_price = e.pivot_price

              AND future_c.trading_day_number
                    BETWEEN e.entry_trading_day_number + 1
                        AND e.entry_trading_day_number + 5

              AND future_r.breakout_state IN
                  (
                      'INTRADAY_CROSS_ONLY',
                      'CROSSED_AND_CLOSED_ABOVE'
                  )
        ) AS breakout_within_5_sessions

    FROM entry_calendar e
),
classified AS
(
    SELECT
        *,

        CASE
            WHEN pivot_proximity_pct >= -2
                THEN 'WITHIN_2PCT'
            ELSE 'BETWEEN_2_AND_4PCT'
        END AS proximity_band

    FROM outcomes
)
SELECT
    proximity_band,
    pivot_proximity_direction AS direction,

    COUNT(*) AS episodes,

    COUNT(*) FILTER
    (
        WHERE breakout_within_5_sessions
    ) AS breakouts,

    COUNT(*) FILTER
    (
        WHERE NOT breakout_within_5_sessions
    ) AS no_breakouts,

    ROUND
    (
        100.0 *
        COUNT(*) FILTER (WHERE breakout_within_5_sessions)
        / NULLIF(COUNT(*), 0),
        2
    ) AS breakout_rate_pct

FROM classified

GROUP BY
    proximity_band,
    pivot_proximity_direction

ORDER BY
    CASE proximity_band
        WHEN 'WITHIN_2PCT' THEN 1
        ELSE 2
    END,
    pivot_proximity_direction;
-- Result:
--
--   WITHIN_2PCT
--     APPROACHING_PIVOT      : 53.85%   (14 / 26)
--     RETREATING_FROM_PIVOT  : 33.33%   ( 5 / 15)
--
--   BETWEEN_2_AND_4PCT
--     APPROACHING_PIVOT      : 25.00%   (11 / 44)
--     RETREATING_FROM_PIVOT  : 16.67%   ( 8 / 48)
--     UNCHANGED              : 33.33%   ( 1 /  3) -- tiny sample
--
-- Interpretation:
--   SR02 location and SR02A trajectory provide complementary information.
--   Near-pivot + approaching is the strongest observed combination.
--
-- Research status:
--   Promising ranking relationship only.
--   Do NOT convert the 2% boundary into a production threshold or score yet.
-- ============================================================================
-- DIAGNOSTIC 7
-- ATR-normalized recent 5-day range vs five-session breakout probability
--
-- Question:
--   Does recent structural expansion/compression, normalized by ATR,
--   discriminate five-session breakout probability?
--
-- Method:
--   - Same canonical first-actionable episode population.
--   - Require recent_5_range_pct and atr_pct to be available.
--   - Compute:
--         range_atr_ratio = recent_5_range_pct / atr_pct
--   - Classify only AFTER selecting the first actionable observation.
--   - Same +1 through +5 trading-session breakout definition.
-- ============================================================================

WITH actionable AS
(
    SELECT
        e.security_id,
        e.pivot_date,
        e.pivot_price,
        e.episode_start_date,
        e.episode_end_date,

        r.trade_date,
        r.pivot_proximity_pct,
        r.recent_5_range_pct,
        r.atr_pct,

        ROW_NUMBER() OVER
        (
            PARTITION BY
                e.security_id,
                e.pivot_date,
                e.pivot_price,
                e.episode_start_date
            ORDER BY r.trade_date
        ) AS rn

    FROM trn.stock_setup_episode e

    JOIN trn.stock_setup_readiness_daily r
      ON r.security_id = e.security_id
     AND r.pivot_date  = e.pivot_date
     AND r.pivot_price = e.pivot_price
     AND r.trade_date >= e.episode_start_date
     AND
        (
            e.episode_end_date IS NULL
            OR r.trade_date <= e.episode_end_date
        )

    WHERE r.pivot_proximity_pct >= -4
      AND r.pivot_proximity_pct < 0
      AND r.recent_5_range_pct IS NOT NULL
      AND r.atr_pct IS NOT NULL
      AND r.atr_pct > 0
),
first_actionable AS
(
    SELECT *
    FROM actionable
    WHERE rn = 1
),
entry_calendar AS
(
    SELECT
        f.*,
        f.recent_5_range_pct / f.atr_pct AS range_atr_ratio,
        c.trading_day_number AS entry_trading_day_number

    FROM first_actionable f

    JOIN ref.trading_calendar c
      ON c.traded_date = f.trade_date
),
outcomes AS
(
    SELECT
        e.*,

        EXISTS
        (
            SELECT 1

            FROM trn.stock_setup_readiness_daily future_r

            JOIN ref.trading_calendar future_c
              ON future_c.traded_date = future_r.trade_date

            WHERE future_r.security_id = e.security_id
              AND future_r.pivot_date  = e.pivot_date
              AND future_r.pivot_price = e.pivot_price

              AND future_c.trading_day_number
                    BETWEEN e.entry_trading_day_number + 1
                        AND e.entry_trading_day_number + 5

              AND future_r.breakout_state IN
                  (
                      'INTRADAY_CROSS_ONLY',
                      'CROSSED_AND_CLOSED_ABOVE'
                  )
        ) AS breakout_within_5_sessions

    FROM entry_calendar e
),
classified AS
(
    SELECT
        *,

        CASE
            WHEN range_atr_ratio < 1.5
                THEN 'LT_1_5X'

            WHEN range_atr_ratio < 2.0
                THEN '1_5_TO_2_0X'

            WHEN range_atr_ratio < 2.5
                THEN '2_0_TO_2_5X'

            WHEN range_atr_ratio < 3.0
                THEN '2_5_TO_3_0X'

            ELSE 'GE_3_0X'
        END AS range_atr_band

    FROM outcomes
)
SELECT
    range_atr_band,

    COUNT(*) AS episodes,

    COUNT(*) FILTER
    (
        WHERE breakout_within_5_sessions
    ) AS breakouts,

    COUNT(*) FILTER
    (
        WHERE NOT breakout_within_5_sessions
    ) AS no_breakouts,

    ROUND
    (
        100.0 *
        COUNT(*) FILTER (WHERE breakout_within_5_sessions)
        / NULLIF(COUNT(*), 0),
        2
    ) AS breakout_rate_pct

FROM classified

GROUP BY range_atr_band

ORDER BY
    CASE range_atr_band
        WHEN 'LT_1_5X'      THEN 1
        WHEN '1_5_TO_2_0X' THEN 2
        WHEN '2_0_TO_2_5X' THEN 3
        WHEN '2_5_TO_3_0X' THEN 4
        WHEN 'GE_3_0X'      THEN 5
    END;
-- Result:
--
--   < 1.5x ATR      : 28.13%   ( 9 / 32)
--   1.5 - 2.0x ATR  : 18.52%   (10 / 54)
--   2.0 - 2.5x ATR  : 31.71%   (13 / 41)
--   2.5 - 3.0x ATR  : 55.00%   (11 / 20)
--   >= 3.0x ATR     : 31.82%   ( 7 / 22)
--
--   Canonical total : 29.59%   (50 / 169)
--
-- Interpretation:
--   The relationship is non-monotonic.
--   The 2.5-3.0x ATR band shows the strongest observed conversion,
--   but higher Range/ATR is not generally better.
--
-- Research status:
--   Promising structural-context relationship only.
--   Do NOT promote 2.5-3.0x ATR to a production threshold or ranking
--   weight without independent temporal validation.
-- ============================================================================
-- DIAGNOSTIC 8
-- SR02 proximity x ATR-normalized recent 5-day range
--
-- Question:
--   Does the relationship between Range/ATR and breakout probability depend
--   on how close the setup is to its pivot?
--
-- Method:
--   - Same canonical first-actionable episode population.
--   - Select first actionable observation BEFORE classification.
--   - Proximity:
--         WITHIN_2PCT
--         BETWEEN_2_AND_4PCT
--   - Range/ATR:
--         <1.5x
--         1.5-2.0x
--         2.0-2.5x
--         2.5-3.0x
--         >=3.0x
--   - Same +1 through +5 trading-session breakout definition.
-- ============================================================================

WITH actionable AS
(
    SELECT
        e.security_id,
        e.pivot_date,
        e.pivot_price,
        e.episode_start_date,
        e.episode_end_date,

        r.trade_date,
        r.pivot_proximity_pct,
        r.recent_5_range_pct,
        r.atr_pct,

        ROW_NUMBER() OVER
        (
            PARTITION BY
                e.security_id,
                e.pivot_date,
                e.pivot_price,
                e.episode_start_date
            ORDER BY r.trade_date
        ) AS rn

    FROM trn.stock_setup_episode e

    JOIN trn.stock_setup_readiness_daily r
      ON r.security_id = e.security_id
     AND r.pivot_date  = e.pivot_date
     AND r.pivot_price = e.pivot_price
     AND r.trade_date >= e.episode_start_date
     AND
        (
            e.episode_end_date IS NULL
            OR r.trade_date <= e.episode_end_date
        )

    WHERE r.pivot_proximity_pct >= -4
      AND r.pivot_proximity_pct < 0
      AND r.recent_5_range_pct IS NOT NULL
      AND r.atr_pct IS NOT NULL
      AND r.atr_pct > 0
),
first_actionable AS
(
    SELECT *
    FROM actionable
    WHERE rn = 1
),
entry_calendar AS
(
    SELECT
        f.*,
        f.recent_5_range_pct / f.atr_pct AS range_atr_ratio,
        c.trading_day_number AS entry_trading_day_number

    FROM first_actionable f

    JOIN ref.trading_calendar c
      ON c.traded_date = f.trade_date
),
outcomes AS
(
    SELECT
        e.*,

        EXISTS
        (
            SELECT 1

            FROM trn.stock_setup_readiness_daily future_r

            JOIN ref.trading_calendar future_c
              ON future_c.traded_date = future_r.trade_date

            WHERE future_r.security_id = e.security_id
              AND future_r.pivot_date  = e.pivot_date
              AND future_r.pivot_price = e.pivot_price

              AND future_c.trading_day_number
                    BETWEEN e.entry_trading_day_number + 1
                        AND e.entry_trading_day_number + 5

              AND future_r.breakout_state IN
                  (
                      'INTRADAY_CROSS_ONLY',
                      'CROSSED_AND_CLOSED_ABOVE'
                  )
        ) AS breakout_within_5_sessions

    FROM entry_calendar e
),
classified AS
(
    SELECT
        *,

        CASE
            WHEN pivot_proximity_pct >= -2
                THEN 'WITHIN_2PCT'
            ELSE 'BETWEEN_2_AND_4PCT'
        END AS proximity_band,

        CASE
            WHEN range_atr_ratio < 1.5
                THEN 'LT_1_5X'
            WHEN range_atr_ratio < 2.0
                THEN '1_5_TO_2_0X'
            WHEN range_atr_ratio < 2.5
                THEN '2_0_TO_2_5X'
            WHEN range_atr_ratio < 3.0
                THEN '2_5_TO_3_0X'
            ELSE 'GE_3_0X'
        END AS range_atr_band

    FROM outcomes
)
SELECT
    proximity_band,
    range_atr_band,

    COUNT(*) AS episodes,

    COUNT(*) FILTER
    (
        WHERE breakout_within_5_sessions
    ) AS breakouts,

    COUNT(*) FILTER
    (
        WHERE NOT breakout_within_5_sessions
    ) AS no_breakouts,

    ROUND
    (
        100.0 *
        COUNT(*) FILTER (WHERE breakout_within_5_sessions)
        / NULLIF(COUNT(*), 0),
        2
    ) AS breakout_rate_pct

FROM classified

GROUP BY
    proximity_band,
    range_atr_band

ORDER BY
    CASE proximity_band
        WHEN 'WITHIN_2PCT' THEN 1
        ELSE 2
    END,

    CASE range_atr_band
        WHEN 'LT_1_5X'      THEN 1
        WHEN '1_5_TO_2_0X' THEN 2
        WHEN '2_0_TO_2_5X' THEN 3
        WHEN '2_5_TO_3_0X' THEN 4
        WHEN 'GE_3_0X'      THEN 5
    END;
-- Result:
--
--   WITHIN_2PCT
--     < 1.5x ATR      : 25.00%   (4 / 16)
--     1.5 - 2.0x ATR  : 21.74%   (5 / 23)
--     2.0 - 2.5x ATR  : 40.00%   (8 / 20)
--     2.5 - 3.0x ATR  : 80.00%   (8 / 10)
--     >= 3.0x ATR     : 40.00%   (4 / 10)
--
--   BETWEEN_2_AND_4PCT
--     < 1.5x ATR      : 31.25%   (5 / 16)
--     1.5 - 2.0x ATR  : 16.13%   (5 / 31)
--     2.0 - 2.5x ATR  : 23.81%   (5 / 21)
--     2.5 - 3.0x ATR  : 30.00%   (3 / 10)
--     >= 3.0x ATR     : 25.00%   (3 / 12)
--
-- Interpretation:
--   Proximity and volatility-normalized recent range appear to interact.
--
--   The strongest observed cell is:
--       WITHIN_2PCT + 2.5-3.0x ATR
--       8 / 10 breakouts
--       80.00% five-session conversion
--
-- Research status:
--   PROMISING HYPOTHESIS ONLY.
--
--   The readiness history begins 2026-08-03 and the standout cell contains
--   only 10 episodes. It has not been independently or temporally validated.
--
--   STOP further threshold slicing on this sample.
--   Do NOT tune the ATR boundaries.
--   Do NOT add additional conditions to maximize the observed conversion.
--   Do NOT convert this combination into a production gate or ranking weight.