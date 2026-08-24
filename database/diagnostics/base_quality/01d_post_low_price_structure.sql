-- ============================================================================
-- MomentumLab
-- Base Quality Validation
-- Diagnostic 1D: Post-Low Price Structure
--
-- Purpose:
--   Determine whether price structure improves after the base low
--   as the stock develops the right side of the base.
--
-- Important:
--   The base-low session is included ONLY as the LAG reference.
--   It is NOT counted as a post-low observation.
--
-- Status:
--   VALIDATION / BUG-FIX
--
-- Scoring:
--   None - diagnostic research only
-- ============================================================================

WITH current_candidates
(
    symbol,
    prior_swing_high_date,
    prior_swing_high,
    base_low_date,
    base_low
) AS
(
    VALUES
        ('5PAISA',
         DATE '2026-07-27',
         381.95::numeric,
         DATE '2026-07-30',
         344.00::numeric),

        ('CHENNPETRO',
         DATE '2026-07-23',
         1354.00::numeric,
         DATE '2026-07-28',
         1150.00::numeric),

        ('DEEPINDS',
         DATE '2026-07-20',
         487.00::numeric,
         DATE '2026-07-24',
         453.60::numeric),

        ('KTKBANK',
         DATE '2026-07-15',
         280.00::numeric,
         DATE '2026-07-17',
         268.35::numeric)
),

-- ============================================================================
-- Step 1
-- Include the base-low session.
--
-- This is necessary because the first session AFTER the base low must be
-- compared with the base-low session itself.
-- ============================================================================

post_low_with_anchor AS
(
    SELECT
        c.symbol,
        c.base_low_date,
        c.base_low,

        b.traded_date,
        b.high_price,
        b.low_price,
        b.close_price,

        LAG(b.high_price) OVER
        (
            PARTITION BY c.symbol
            ORDER BY b.traded_date
        ) AS prev_high,

        LAG(b.low_price) OVER
        (
            PARTITION BY c.symbol
            ORDER BY b.traded_date
        ) AS prev_low

    FROM current_candidates c

    JOIN trn.nse_sec_bhavdata b
      ON b.symbol = c.symbol
     AND b.series = 'EQ'

     -- IMPORTANT:
     -- >= includes the base-low session as the LAG anchor.
     AND b.traded_date >= c.base_low_date

     AND b.traded_date <= DATE '2026-08-13'
),

-- ============================================================================
-- Step 2
-- Remove the base-low session from the observation population.
--
-- The anchor is used for comparison but is not itself counted.
-- ============================================================================

post_low_data AS
(
    SELECT
        symbol,
        base_low_date,
        base_low,
        traded_date,
        high_price,
        low_price,
        close_price,
        prev_high,
        prev_low

    FROM post_low_with_anchor

    WHERE traded_date > base_low_date
),

-- ============================================================================
-- Step 3
-- Classify each post-low session relative to the immediately preceding
-- trading session.
-- ============================================================================

classified AS
(
    SELECT
        *,

        CASE
            WHEN high_price > prev_high THEN 1
            ELSE 0
        END AS is_higher_high,

        CASE
            WHEN low_price > prev_low THEN 1
            ELSE 0
        END AS is_higher_low,

        CASE
            WHEN high_price < prev_high THEN 1
            ELSE 0
        END AS is_lower_high,

        CASE
            WHEN low_price < prev_low THEN 1
            ELSE 0
        END AS is_lower_low

    FROM post_low_data
)

-- ============================================================================
-- Final Diagnostic
-- ============================================================================

SELECT
    symbol,

    COUNT(*) AS post_low_sessions,

    SUM(is_higher_high) AS higher_high_days,
    SUM(is_higher_low)  AS higher_low_days,

    SUM(is_lower_high)  AS lower_high_days,
    SUM(is_lower_low)   AS lower_low_days,

    ROUND(
        (
            SUM(is_higher_low) * 100.0
            / NULLIF(COUNT(*), 0)
        )::numeric,
        2
    ) AS higher_low_ratio_pct,

    ROUND(
        (
            SUM(is_higher_high) * 100.0
            / NULLIF(COUNT(*), 0)
        )::numeric,
        2
    ) AS higher_high_ratio_pct,

    ROUND(
        (
            SUM(is_lower_low) * 100.0
            / NULLIF(COUNT(*), 0)
        )::numeric,
        2
    ) AS lower_low_ratio_pct,

    ROUND(
        (
            (
                MAX(close_price) - MAX(base_low)
            )
            / NULLIF(MAX(base_low), 0)
            * 100
        )::numeric,
        2
    ) AS max_close_recovery_pct,

    ROUND(
        (
            (
                MAX(high_price) - MAX(base_low)
            )
            / NULLIF(MAX(base_low), 0)
            * 100
        )::numeric,
        2
    ) AS max_price_recovery_pct

FROM classified

GROUP BY symbol

ORDER BY symbol;