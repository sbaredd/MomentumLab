-- ============================================================================
-- MomentumLab
-- File        : 001_corporate_action_adjustment_validation.sql
-- Area        : Corporate Action Diagnostics
-- Purpose     : Validate deterministic historical price adjustment factors
--               for simple NSE bonus and stock-split events.
--
-- IMPORTANT
-- ----------
-- 1. trn.nse_sec_bhavdata remains immutable raw NSE data.
-- 2. This script is diagnostic/research only.
-- 3. Only explicit SIMPLE BONUS and STOCK SPLIT events are considered.
-- 4. Dividends, demergers, rights issues and complex schemes are excluded.
-- 5. This script does NOT modify any data.
-- ============================================================================


-- ============================================================================
-- 01. IDENTIFY DETERMINISTIC ADJUSTMENT EVENTS
-- ============================================================================
--
-- Supported:
--
--   Bonus X:Y
--       Historical price factor = Y / (X + Y)
--
--       Example:
--           Bonus 1:1 -> 1 / 2 = 0.50
--           Bonus 2:1 -> 1 / 3 = 0.33333333
--           Bonus 4:1 -> 1 / 5 = 0.20
--
--   Face Value Split
--       Historical price factor = new face value / old face value
--
--       Example:
--           Rs 10 -> Rs 2 = 0.20
--           Rs 5  -> Re 1 = 0.20
--
-- Complex strings such as:
--
--   Scheme Of Arrangement - Bonus NCRPS 4:1
--
-- are intentionally excluded.
-- ============================================================================

WITH event_factor AS
(
    SELECT
        corporate_action_id,
        symbol,
        company_name,
        series,
        purpose,
        ex_date,

        CASE
            -------------------------------------------------------------------
            -- SIMPLE BONUS
            -------------------------------------------------------------------
            WHEN purpose ~* '^Bonus[[:space:]]+[0-9]+:[0-9]+[[:space:]]*$'
            THEN 'BONUS'

            -------------------------------------------------------------------
            -- STOCK SPLIT
            -------------------------------------------------------------------
            WHEN purpose ~* '^Face Value Split[[:space:]]*\(Sub-Division\)'
            THEN 'STOCK_SPLIT'
        END AS adjustment_type,

        CASE
            -------------------------------------------------------------------
            -- Bonus X:Y
            -- factor = Y / (X + Y)
            -------------------------------------------------------------------
            WHEN purpose ~* '^Bonus[[:space:]]+[0-9]+:[0-9]+[[:space:]]*$'
            THEN
                (
                    (regexp_match(
                        purpose,
                        '([0-9]+):([0-9]+)'
                    ))[2]::numeric
                    /
                    (
                        (regexp_match(
                            purpose,
                            '([0-9]+):([0-9]+)'
                        ))[1]::numeric
                        +
                        (regexp_match(
                            purpose,
                            '([0-9]+):([0-9]+)'
                        ))[2]::numeric
                    )
                )

            -------------------------------------------------------------------
            -- Stock Split
            -- factor = new face value / old face value
            -------------------------------------------------------------------
            WHEN purpose ~* '^Face Value Split[[:space:]]*\(Sub-Division\)'
            THEN
                (
                    (regexp_match(
                        purpose,
                        'To (?:Rs|Re)[[:space:]]*([0-9]+)'
                    ))[1]::numeric
                    /
                    (regexp_match(
                        purpose,
                        'From Rs[[:space:]]*([0-9]+)'
                    ))[1]::numeric
                )
        END AS expected_factor

    FROM trn.nse_corporate_action

    WHERE
           purpose ~* '^Bonus[[:space:]]+[0-9]+:[0-9]+[[:space:]]*$'
        OR purpose ~* '^Face Value Split[[:space:]]*\(Sub-Division\)'
),

event_dates AS
(
    SELECT
        ef.*,

        (
            SELECT MAX(b.traded_date)
            FROM trn.nse_sec_bhavdata b
            WHERE b.symbol = ef.symbol
              AND b.series = 'EQ'
              AND b.traded_date < ef.ex_date
        ) AS previous_price_date,

        (
            SELECT MAX(b.close_price)
            FROM trn.nse_sec_bhavdata b
            WHERE b.symbol = ef.symbol
              AND b.series = 'EQ'
              AND b.traded_date =
                  (
                      SELECT MAX(b2.traded_date)
                      FROM trn.nse_sec_bhavdata b2
                      WHERE b2.symbol = ef.symbol
                        AND b2.series = 'EQ'
                        AND b2.traded_date < ef.ex_date
                  )
        ) AS previous_close,

        (
            SELECT b.close_price
            FROM trn.nse_sec_bhavdata b
            WHERE b.symbol = ef.symbol
              AND b.series = 'EQ'
              AND b.traded_date = ef.ex_date
            LIMIT 1
        ) AS ex_date_close,

        (
            SELECT MIN(b.traded_date)
            FROM trn.nse_sec_bhavdata b
            WHERE b.symbol = ef.symbol
              AND b.series = 'EQ'
              AND b.traded_date > ef.ex_date
        ) AS next_price_date

    FROM event_factor ef
),

price_check AS
(
    SELECT
        ed.*,

        (
            SELECT b.close_price
            FROM trn.nse_sec_bhavdata b
            WHERE b.symbol = ed.symbol
              AND b.series = 'EQ'
              AND b.traded_date = ed.next_price_date
            LIMIT 1
        ) AS next_close

    FROM event_dates ed
),

validated AS
(
    SELECT
        pc.*,

        CASE
            WHEN previous_close IS NULL
                THEN 'NO_PRICE_COMPARISON'

            WHEN ex_date_close IS NOT NULL
                THEN 'DIRECT_EX_DATE'

            WHEN next_price_date IS NULL
                THEN 'NO_PRICE_COMPARISON'

            WHEN next_price_date - ex_date <= 7
                THEN 'NEAR_EX_DATE'

            ELSE 'LONG_GAP_NON_COMPARABLE'
        END AS validation_class,

        CASE
            WHEN previous_close IS NULL
                THEN NULL

            WHEN ex_date_close IS NOT NULL
                THEN ex_date_close / NULLIF(previous_close, 0)

            WHEN next_price_date IS NOT NULL
                 AND next_price_date - ex_date <= 7
                THEN next_close / NULLIF(previous_close, 0)

            ELSE NULL
        END AS observed_factor

    FROM price_check pc
)

SELECT
    validation_class,

    COUNT(*) AS events,

    COUNT(DISTINCT symbol) AS symbols,

    MIN(ex_date) AS first_ex_date,

    MAX(ex_date) AS last_ex_date

FROM validated

GROUP BY validation_class

ORDER BY validation_class;


-- ============================================================================
-- EXPECTED VALIDATION POPULATION
-- ============================================================================
--
-- Research run: 05-Sep-2026
--
-- DIRECT_EX_DATE           : 101 events / 100 symbols
-- NEAR_EX_DATE             :   1 event  /   1 symbol
-- LONG_GAP_NON_COMPARABLE  :   6 events /   5 symbols
-- NO_PRICE_COMPARISON      :  45 events /  43 symbols
--
-- TOTAL                    : 153 adjustment events
--
-- Direct ex-date observations are the primary validation population.
-- Long-gap observations must NOT be interpreted as failed adjustment factors,
-- because intervening market movement makes the prices non-comparable.
-- ============================================================================


-- ============================================================================
-- 02. VALIDATE EXPECTED FACTOR AGAINST OBSERVED PRICE RESET
-- ============================================================================

WITH event_factor AS
(
    SELECT
        corporate_action_id,
        symbol,
        purpose,
        ex_date,

        CASE
            WHEN purpose ~* '^Bonus[[:space:]]+[0-9]+:[0-9]+[[:space:]]*$'
            THEN
                (
                    (regexp_match(
                        purpose,
                        '([0-9]+):([0-9]+)'
                    ))[2]::numeric
                    /
                    (
                        (regexp_match(
                            purpose,
                            '([0-9]+):([0-9]+)'
                        ))[1]::numeric
                        +
                        (regexp_match(
                            purpose,
                            '([0-9]+):([0-9]+)'
                        ))[2]::numeric
                    )
                )

            WHEN purpose ~* '^Face Value Split[[:space:]]*\(Sub-Division\)'
            THEN
                (
                    (regexp_match(
                        purpose,
                        'To (?:Rs|Re)[[:space:]]*([0-9]+)'
                    ))[1]::numeric
                    /
                    (regexp_match(
                        purpose,
                        'From Rs[[:space:]]*([0-9]+)'
                    ))[1]::numeric
                )
        END AS expected_factor

    FROM trn.nse_corporate_action

    WHERE
           purpose ~* '^Bonus[[:space:]]+[0-9]+:[0-9]+[[:space:]]*$'
        OR purpose ~* '^Face Value Split[[:space:]]*\(Sub-Division\)'
),

price_check AS
(
    SELECT
        ef.*,

        (
            SELECT b.close_price
            FROM trn.nse_sec_bhavdata b
            WHERE b.symbol = ef.symbol
              AND b.series = 'EQ'
              AND b.traded_date =
                  (
                      SELECT MAX(b2.traded_date)
                      FROM trn.nse_sec_bhavdata b2
                      WHERE b2.symbol = ef.symbol
                        AND b2.series = 'EQ'
                        AND b2.traded_date < ef.ex_date
                  )
            LIMIT 1
        ) AS previous_close,

        (
            SELECT b.close_price
            FROM trn.nse_sec_bhavdata b
            WHERE b.symbol = ef.symbol
              AND b.series = 'EQ'
              AND b.traded_date = ef.ex_date
            LIMIT 1
        ) AS ex_date_close

    FROM event_factor ef
),

validated AS
(
    SELECT
        *,

        ex_date_close / NULLIF(previous_close, 0)
            AS observed_factor

    FROM price_check

    WHERE previous_close IS NOT NULL
      AND ex_date_close IS NOT NULL
),

residual AS
(
    SELECT
        *,

        (
            observed_factor / NULLIF(expected_factor, 0)
        ) - 1 AS residual_return

    FROM validated
)

SELECT
    COUNT(*) AS comparable_events,

    COUNT(*) FILTER
    (
        WHERE ABS(residual_return) <= 0.05
    ) AS within_5pct,

    COUNT(*) FILTER
    (
        WHERE ABS(residual_return) <= 0.10
    ) AS within_10pct,

    COUNT(*) FILTER
    (
        WHERE ABS(residual_return) > 0.20
    ) AS outside_20pct,

    ROUND(
        (
            AVG(ABS(residual_return))
            FILTER (WHERE residual_return IS NOT NULL)
            * 100
        )::numeric,
        2
    ) AS avg_abs_residual_pct

FROM residual;


-- ============================================================================
-- VALIDATION EVIDENCE
-- ============================================================================
--
-- Previous diagnostic result:
--
-- Adjustment dates examined : 153
-- Price-comparable events    : 101
-- Within +/- 5%              : 73
-- Within +/- 10%             : 91
-- Outside +/- 20%            : 0
-- Avg absolute residual      : 4.26%
--
-- Interpretation:
--
-- The deterministic factors derived from explicit NSE bonus and stock-split
-- descriptions closely reproduce the mechanical price reset observed in
-- raw NSE bhavcopy data.
--
-- This validates the factor methodology for SIMPLE BONUS and STOCK SPLIT
-- corporate actions.
--
-- It does NOT validate:
--
--   * dividends
--   * demergers
--   * rights issues
--   * complex schemes of arrangement
--   * NCRPS / non-equity bonus instruments
--
-- These require separate treatment.
-- ============================================================================


-- ============================================================================
-- 03. SAME-DAY MULTIPLE ADJUSTMENT EVENTS
-- ============================================================================
--
-- Multiple valid adjustment events may occur for the same symbol on the same
-- ex-date. Their factors must be COMPOUNDED, not treated independently.
--
-- Examples observed:
-- BAJFINANCE, NAZARA, FCL, BHARATRAS, BESTAGRO,
-- DELPHIFX, SILVERTUC, RNBDENIMS, AHCL.
--
-- Example:
--
--     Bonus factor = 0.50
--     Split factor = 0.20
--
--     Combined factor = 0.50 * 0.20 = 0.10
--
-- Therefore production adjustment-event design must support multiple
-- corporate actions per symbol/ex-date and derive a combined factor.
-- ============================================================================


-- ============================================================================
-- RESEARCH CONCLUSION
-- ============================================================================
--
-- STATUS: VALIDATED
--
-- 1. Raw NSE bhavcopy must remain immutable.
--
-- 2. Corporate-action adjustment must occur in a derived layer.
--
-- 3. Explicit simple Bonus X:Y events can be parsed deterministically:
--
--        factor = Y / (X + Y)
--
-- 4. Explicit Face Value Split events can be parsed deterministically:
--
--        factor = new_face_value / old_face_value
--
-- 5. Multiple adjustment events on the same ex-date must be compounded.
--
-- 6. Price validation should primarily use DIRECT_EX_DATE observations.
--
-- 7. Long trading gaps must not be classified as adjustment failures.
--
-- 8. Existing unadjusted rolling-price features such as highest_high_252
--    can cross incompatible price regimes and therefore must not be used
--    for SR10 until the adjusted-price feature layer is implemented.
--
-- NEXT ARCHITECTURAL STEP:
--
--    Design the production price-adjustment event layer and cumulative
--    historical adjustment-factor model.
--
-- ============================================================================
