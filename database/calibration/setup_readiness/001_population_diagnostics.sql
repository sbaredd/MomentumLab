-- ============================================================================
-- MomentumLab
-- File        : 001_population_diagnostics.sql
-- Path        : database/calibration/setup_readiness/
-- Purpose     : Population, pivot persistence and episode-grain diagnostics
-- Schema      : trn
-- Source      : trn.stock_setup_readiness_daily
--
-- IMPORTANT
-- ----------
-- This file is diagnostic/calibration SQL.
-- It does NOT modify data.
-- It does NOT define production thresholds.
--
-- Objectives
-- ----------
-- 1. Understand the population represented in stock_setup_readiness_daily.
-- 2. Validate the persistence of structural pivots across trading days.
-- 3. Determine whether securities can have multiple structural pivots.
-- 4. Test whether pivot_type is stable enough to form part of pivot identity.
-- 5. Detect pivots that disappear and later become active again.
-- 6. Validate the distinction:
--
--       STRUCTURAL PIVOT
--              !=
--       ACTIVE-PIVOT EPISODE
--
-- Current working structural pivot identity:
--
--       (security_id, pivot_date, pivot_price)
--
-- pivot_type is intentionally NOT included in structural identity until
-- diagnostics prove that it is stable.
--
-- NOTE
-- ----
-- Execute each diagnostic/result section independently in DBeaver when
-- investigating results.
-- ============================================================================


-- ============================================================================
-- RESULT 1
-- BASIC POPULATION SUMMARY
-- ============================================================================

SELECT
    COUNT(*) AS observation_rows,
    COUNT(DISTINCT security_id) AS securities,
    MIN(trade_date) AS first_trade_date,
    MAX(trade_date) AS last_trade_date,

    COUNT(*) FILTER
    (
        WHERE pivot_date IS NOT NULL
          AND pivot_price IS NOT NULL
    ) AS rows_with_active_pivot,

    COUNT(*) FILTER
    (
        WHERE pivot_date IS NULL
           OR pivot_price IS NULL
    ) AS rows_without_active_pivot

FROM trn.stock_setup_readiness_daily;


-- ============================================================================
-- RESULT 2
-- BREAKOUT-STATE POPULATION
--
-- Useful as a basic sanity check of the readiness population.
-- ============================================================================

SELECT
    breakout_state,
    COUNT(*) AS observation_count,

    ROUND
    (
        100.0 * COUNT(*) /
        NULLIF
        (
            SUM(COUNT(*)) OVER (),
            0
        ),
        2
    ) AS population_pct

FROM trn.stock_setup_readiness_daily

GROUP BY breakout_state

ORDER BY
    observation_count DESC,
    breakout_state;


-- ============================================================================
-- RESULT 3
-- STRUCTURAL PIVOT POPULATION
--
-- Structural identity deliberately excludes pivot_type.
--
-- One row represents:
--
--     security_id + pivot_date + pivot_price
--
-- This tells us how many distinct structural pivot levels are represented
-- in the current readiness population.
-- ============================================================================

WITH structural_pivots AS
(
    SELECT
        security_id,
        pivot_date,
        pivot_price,

        MIN(trade_date) AS first_observation_date,
        MAX(trade_date) AS last_observation_date,

        COUNT(*) AS observation_count,

        COUNT(DISTINCT pivot_type) AS pivot_type_count

    FROM trn.stock_setup_readiness_daily

    WHERE pivot_date IS NOT NULL
      AND pivot_price IS NOT NULL

    GROUP BY
        security_id,
        pivot_date,
        pivot_price
)

SELECT
    COUNT(*) AS structural_pivots,

    COUNT(DISTINCT security_id) AS securities_with_pivots,

    ROUND
    (
        AVG(observation_count)::numeric,
        2
    ) AS avg_observations_per_pivot,

    MIN(observation_count) AS min_observations_per_pivot,

    MAX(observation_count) AS max_observations_per_pivot,

    COUNT(*) FILTER
    (
        WHERE pivot_type_count > 1
    ) AS pivots_with_multiple_types

FROM structural_pivots;


-- ============================================================================
-- RESULT 4
-- NUMBER OF STRUCTURAL PIVOTS PER SECURITY
--
-- This validates whether:
--
--     one security = one pivot
--
-- is a valid assumption.
--
-- Previous investigation showed that many securities contain more than one
-- structural pivot during the observation window.
-- ============================================================================

WITH structural_pivots AS
(
    SELECT DISTINCT
        security_id,
        pivot_date,
        pivot_price

    FROM trn.stock_setup_readiness_daily

    WHERE pivot_date IS NOT NULL
      AND pivot_price IS NOT NULL
),

security_pivot_counts AS
(
    SELECT
        security_id,
        COUNT(*) AS pivot_count

    FROM structural_pivots

    GROUP BY security_id
)

SELECT
    pivot_count,

    COUNT(*) AS security_count,

    ROUND
    (
        100.0 * COUNT(*) /
        NULLIF
        (
            SUM(COUNT(*)) OVER (),
            0
        ),
        2
    ) AS security_pct

FROM security_pivot_counts

GROUP BY pivot_count

ORDER BY pivot_count;


-- ============================================================================
-- RESULT 5
-- DETAIL: STRUCTURAL PIVOTS PER SECURITY
--
-- Shows the actual structural pivots rather than only the distribution.
-- Useful when manually validating securities with multiple pivots.
-- ============================================================================

SELECT
    security_id,
    pivot_date,
    pivot_price,

    MIN(trade_date) AS first_observation_date,
    MAX(trade_date) AS last_observation_date,

    COUNT(*) AS observation_count,

    COUNT(DISTINCT pivot_type) AS pivot_type_count

FROM trn.stock_setup_readiness_daily

WHERE pivot_date IS NOT NULL
  AND pivot_price IS NOT NULL

GROUP BY
    security_id,
    pivot_date,
    pivot_price

ORDER BY
    security_id,
    pivot_date,
    pivot_price;


-- ============================================================================
-- RESULT 6
-- PIVOT TYPE STABILITY
--
-- Question:
--
-- Can pivot_type safely form part of structural pivot identity?
--
-- If the same:
--
--     security_id + pivot_date + pivot_price
--
-- receives more than one pivot_type, then pivot_type is descriptive
-- classification rather than durable structural identity.
-- ============================================================================

SELECT
    security_id,
    pivot_date,
    pivot_price,

    COUNT(*) AS observation_rows,

    COUNT(DISTINCT pivot_type) AS pivot_types,

    STRING_AGG
    (
        DISTINCT pivot_type::text,
        ', '
        ORDER BY pivot_type::text
    ) AS observed_pivot_types,

    MIN(trade_date) AS first_seen,

    MAX(trade_date) AS last_seen

FROM trn.stock_setup_readiness_daily

WHERE pivot_date IS NOT NULL
  AND pivot_price IS NOT NULL

GROUP BY
    security_id,
    pivot_date,
    pivot_price

HAVING COUNT(DISTINCT pivot_type) > 1

ORDER BY
    security_id,
    pivot_date,
    pivot_price;


-- ============================================================================
-- RESULT 7
-- ACTIVE-PIVOT RUN CONSTRUCTION
--
-- A RUN is a continuous sequence of readiness observations during which
-- the same structural pivot remains selected for a security.
--
-- IMPORTANT:
--
-- run_id is a DIAGNOSTIC ordinal.
--
-- It should NOT yet be treated as a durable production episode_id because
-- historical inserts/backfills can change the ordinal numbering.
--
-- This result allows manual inspection of pivot switches.
-- ============================================================================

WITH pivot_rows AS
(
    SELECT
        security_id,
        trade_date,
        pivot_date,
        pivot_price,
        pivot_type,
        breakout_state,
        pivot_proximity_pct,

        LAG(pivot_date) OVER
        (
            PARTITION BY security_id
            ORDER BY trade_date
        ) AS prev_pivot_date,

        LAG(pivot_price) OVER
        (
            PARTITION BY security_id
            ORDER BY trade_date
        ) AS prev_pivot_price

    FROM trn.stock_setup_readiness_daily

    WHERE pivot_date IS NOT NULL
      AND pivot_price IS NOT NULL
),

run_flags AS
(
    SELECT
        *,

        CASE
            WHEN prev_pivot_date = pivot_date
             AND prev_pivot_price = pivot_price
            THEN 0
            ELSE 1
        END AS new_run

    FROM pivot_rows
),

runs AS
(
    SELECT
        *,

        SUM(new_run) OVER
        (
            PARTITION BY security_id
            ORDER BY trade_date
            ROWS UNBOUNDED PRECEDING
        ) AS run_id

    FROM run_flags
)

SELECT
    security_id,
    trade_date,
    pivot_date,
    pivot_price,
    pivot_type,
    breakout_state,

    ROUND
    (
        pivot_proximity_pct::numeric,
        2
    ) AS proximity_pct,

    run_id

FROM runs

ORDER BY
    security_id,
    trade_date;


-- ============================================================================
-- RESULT 8
-- ACTIVE-PIVOT RUN SUMMARY
--
-- One row per continuous active-pivot run.
--
-- This is the first approximation of an episode population.
--
-- Do NOT create the production episode table from this yet.
-- Lifecycle semantics must first be validated.
-- ============================================================================

WITH pivot_rows AS
(
    SELECT
        security_id,
        trade_date,
        pivot_date,
        pivot_price,
        pivot_type,
        breakout_state,
        pivot_proximity_pct,

        LAG(pivot_date) OVER
        (
            PARTITION BY security_id
            ORDER BY trade_date
        ) AS prev_pivot_date,

        LAG(pivot_price) OVER
        (
            PARTITION BY security_id
            ORDER BY trade_date
        ) AS prev_pivot_price

    FROM trn.stock_setup_readiness_daily

    WHERE pivot_date IS NOT NULL
      AND pivot_price IS NOT NULL
),

run_flags AS
(
    SELECT
        *,

        CASE
            WHEN prev_pivot_date = pivot_date
             AND prev_pivot_price = pivot_price
            THEN 0
            ELSE 1
        END AS new_run

    FROM pivot_rows
),

runs AS
(
    SELECT
        *,

        SUM(new_run) OVER
        (
            PARTITION BY security_id
            ORDER BY trade_date
            ROWS UNBOUNDED PRECEDING
        ) AS run_id

    FROM run_flags
)

SELECT
    security_id,
    run_id,

    pivot_date,
    pivot_price,

    MIN(trade_date) AS run_start_date,
    MAX(trade_date) AS run_end_date,

    COUNT(*) AS observation_count,

    COUNT(DISTINCT pivot_type) AS pivot_type_count,

    MIN(pivot_proximity_pct) AS min_proximity_pct,
    MAX(pivot_proximity_pct) AS max_proximity_pct

FROM runs

GROUP BY
    security_id,
    run_id,
    pivot_date,
    pivot_price

ORDER BY
    security_id,
    run_id;


-- ============================================================================
-- RESULT 9
-- NUMBER OF ACTIVE-PIVOT RUNS PER SECURITY
--
-- Distinguishes:
--
--     number of structural pivots
--
-- from:
--
--     number of active-pivot runs
--
-- A structural pivot can potentially participate in multiple runs.
-- ============================================================================

WITH pivot_rows AS
(
    SELECT
        security_id,
        trade_date,
        pivot_date,
        pivot_price,

        LAG(pivot_date) OVER
        (
            PARTITION BY security_id
            ORDER BY trade_date
        ) AS prev_pivot_date,

        LAG(pivot_price) OVER
        (
            PARTITION BY security_id
            ORDER BY trade_date
        ) AS prev_pivot_price

    FROM trn.stock_setup_readiness_daily

    WHERE pivot_date IS NOT NULL
      AND pivot_price IS NOT NULL
),

run_flags AS
(
    SELECT
        *,

        CASE
            WHEN prev_pivot_date = pivot_date
             AND prev_pivot_price = pivot_price
            THEN 0
            ELSE 1
        END AS new_run

    FROM pivot_rows
),

runs AS
(
    SELECT
        *,

        SUM(new_run) OVER
        (
            PARTITION BY security_id
            ORDER BY trade_date
            ROWS UNBOUNDED PRECEDING
        ) AS run_id

    FROM run_flags
),

security_runs AS
(
    SELECT
        security_id,
        COUNT(DISTINCT run_id) AS run_count

    FROM runs

    GROUP BY security_id
)

SELECT
    run_count,

    COUNT(*) AS security_count,

    ROUND
    (
        100.0 * COUNT(*) /
        NULLIF
        (
            SUM(COUNT(*)) OVER (),
            0
        ),
        2
    ) AS security_pct

FROM security_runs

GROUP BY run_count

ORDER BY run_count;


-- ============================================================================
-- RESULT 10
-- REAPPEARING STRUCTURAL PIVOTS
--
-- Question:
--
-- Can the same structural pivot disappear as the active pivot and later
-- become active again?
--
-- If separate_runs > 1, the answer is YES.
--
-- This is important because:
--
--     STRUCTURAL PIVOT != ACTIVE-PIVOT EPISODE
--
-- A persistent structural level can participate in multiple episodes.
-- ============================================================================

WITH pivot_rows AS
(
    SELECT
        security_id,
        trade_date,
        pivot_date,
        pivot_price,

        LAG(pivot_date) OVER
        (
            PARTITION BY security_id
            ORDER BY trade_date
        ) AS prev_pivot_date,

        LAG(pivot_price) OVER
        (
            PARTITION BY security_id
            ORDER BY trade_date
        ) AS prev_pivot_price

    FROM trn.stock_setup_readiness_daily

    WHERE pivot_date IS NOT NULL
      AND pivot_price IS NOT NULL
),

run_flags AS
(
    SELECT
        *,

        CASE
            WHEN prev_pivot_date = pivot_date
             AND prev_pivot_price = pivot_price
            THEN 0
            ELSE 1
        END AS new_run

    FROM pivot_rows
),

runs AS
(
    SELECT
        *,

        SUM(new_run) OVER
        (
            PARTITION BY security_id
            ORDER BY trade_date
            ROWS UNBOUNDED PRECEDING
        ) AS run_id

    FROM run_flags
)

SELECT
    security_id,
    pivot_date,
    pivot_price,

    COUNT(DISTINCT run_id) AS separate_runs,

    MIN(trade_date) AS first_seen,
    MAX(trade_date) AS last_seen

FROM runs

GROUP BY
    security_id,
    pivot_date,
    pivot_price

HAVING COUNT(DISTINCT run_id) > 1

ORDER BY
    security_id,
    pivot_date,
    pivot_price;


-- ============================================================================
-- RESULT 11
-- FULL HISTORY FOR SECURITIES CONTAINING REAPPEARING PIVOTS
--
-- This is the detailed diagnostic used to understand WHY a structural
-- pivot reappeared.
--
-- Rows belonging to a structural pivot that occurs in multiple runs are
-- marked:
--
--     REAPPEARING_PIVOT
--
-- The complete security history is returned so intermediate pivots can
-- also be inspected.
-- ============================================================================

WITH pivot_rows AS
(
    SELECT
        security_id,
        trade_date,
        pivot_date,
        pivot_price,
        pivot_type,
        breakout_state,
        pivot_proximity_pct,

        LAG(pivot_date) OVER
        (
            PARTITION BY security_id
            ORDER BY trade_date
        ) AS prev_pivot_date,

        LAG(pivot_price) OVER
        (
            PARTITION BY security_id
            ORDER BY trade_date
        ) AS prev_pivot_price

    FROM trn.stock_setup_readiness_daily

    WHERE pivot_date IS NOT NULL
      AND pivot_price IS NOT NULL
),

run_flags AS
(
    SELECT
        *,

        CASE
            WHEN prev_pivot_date = pivot_date
             AND prev_pivot_price = pivot_price
            THEN 0
            ELSE 1
        END AS new_run

    FROM pivot_rows
),

runs AS
(
    SELECT
        *,

        SUM(new_run) OVER
        (
            PARTITION BY security_id
            ORDER BY trade_date
            ROWS UNBOUNDED PRECEDING
        ) AS run_id

    FROM run_flags
),

reappearing AS
(
    SELECT
        security_id,
        pivot_date,
        pivot_price

    FROM runs

    GROUP BY
        security_id,
        pivot_date,
        pivot_price

    HAVING COUNT(DISTINCT run_id) > 1
)

SELECT
    r.security_id,
    r.trade_date,
    r.pivot_date,
    r.pivot_price,
    r.pivot_type,
    r.breakout_state,

    ROUND
    (
        r.pivot_proximity_pct::numeric,
        2
    ) AS proximity_pct,

    r.run_id,

    CASE
        WHEN rp.security_id IS NOT NULL
        THEN 'REAPPEARING_PIVOT'
        ELSE NULL
    END AS diagnostic_flag

FROM runs r

INNER JOIN
(
    SELECT DISTINCT security_id
    FROM reappearing
) affected
    ON affected.security_id = r.security_id

LEFT JOIN reappearing rp
    ON  rp.security_id = r.security_id
    AND rp.pivot_date  = r.pivot_date
    AND rp.pivot_price = r.pivot_price

ORDER BY
    r.security_id,
    r.trade_date;


-- ============================================================================
-- END OF FILE
--
-- CURRENT ARCHITECTURAL INTERPRETATION
-- ------------------------------------
--
-- 1. STRUCTURAL PIVOT
--
--    Candidate identity:
--
--        security_id
--        + pivot_date
--        + pivot_price
--
--
-- 2. ACTIVE PIVOT
--
--    The structural resistance currently relevant to the security.
--
--
-- 3. ACTIVE-PIVOT RUN / SETUP EPISODE
--
--    A continuous period during which the same structural pivot remains
--    active.
--
--    The same structural pivot may participate in multiple episodes.
--
--
-- 4. pivot_type
--
--    Currently treated as descriptive classification rather than structural
--    identity because the same structural pivot can receive multiple types.
--
--
-- 5. run_id
--
--    Diagnostic only.
--
--    Do not persist this ordinal directly as durable episode identity.
--
--
-- NEXT VALIDATION
-- ---------------
--
-- Before creating trn.stock_setup_episode, determine whether
--
--        CROSSED_AND_CLOSED_ABOVE
--
-- always occurs on the final observation of an active-pivot run.
--
-- This determines whether:
--
--     active-pivot run == setup episode
--
-- or whether an episode must be explicitly terminated/split at confirmed
-- breakout.
-- ============================================================================