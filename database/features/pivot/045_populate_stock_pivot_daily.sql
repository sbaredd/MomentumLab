-- ============================================================================
-- MomentumLab
-- Table       : trn.stock_pivot_daily
-- File        : 045_populate_stock_pivot_daily.sql
-- Version     : 1.0
-- Description : Identifies the actionable structural pivot for each security.
--
-- Pivot resolution:
--   1. Highest unresolved confirmed right-side swing high
--   2. Otherwise unresolved prior swing high
--   3. Otherwise NO_ACTIVE_PIVOT
--
-- Anti-lookahead:
--   Pivot is determined using information strictly before evaluation_date.
--   The evaluation session is then tested against that frozen pivot.
-- ============================================================================

WITH params AS
(
    SELECT CAST(:evaluation_date AS DATE) AS evaluation_date
),

-- ============================================================================
-- 1. Selected universe
-- ============================================================================
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

-- ============================================================================
-- 2. Active base episode
-- ============================================================================
episodes AS
(
    SELECT
        e.security_id,
        u.symbol,
        e.trade_date,
        e.base_low_date,
        e.prior_swing_high_date,
        e.prior_swing_high
    FROM trn.stock_base_episode_daily e
    JOIN universe u
        ON u.security_id = e.security_id
    CROSS JOIN params p
    WHERE e.trade_date = p.evaluation_date
),

-- ============================================================================
-- 3. Confirmed right-side swing-high candidates
-- ============================================================================
right_side_candidates AS
(
    SELECT DISTINCT
        e.security_id,
        e.symbol,
        ms.latest_swing_high_date AS candidate_date,
        ms.latest_swing_high      AS candidate_price

    FROM episodes e
    JOIN trn.stock_market_structure_daily ms
        ON ms.symbol = e.symbol
    CROSS JOIN params p

    WHERE ms.trade_date < p.evaluation_date
      AND ms.latest_swing_high_date > e.base_low_date
      AND ms.latest_swing_high_date < p.evaluation_date
),

-- ============================================================================
-- 4. Test whether each candidate was subsequently cleared before evaluation
-- ============================================================================
right_side_test AS
(
    SELECT
        c.security_id,
        c.symbol,
        c.candidate_date,
        c.candidate_price,
        MAX(b.high_price) AS max_high_after_candidate

    FROM right_side_candidates c
    CROSS JOIN params p

    LEFT JOIN trn.nse_sec_bhavdata b
        ON b.symbol = c.symbol
       AND b.traded_date > c.candidate_date
       AND b.traded_date < p.evaluation_date

    GROUP BY
        c.security_id,
        c.symbol,
        c.candidate_date,
        c.candidate_price
),

-- ============================================================================
-- 5. Retain unresolved right-side resistance
-- ============================================================================
unresolved_right_side AS
(
    SELECT
        *
    FROM right_side_test
    WHERE max_high_after_candidate IS NULL
       OR max_high_after_candidate <= candidate_price
),

-- ============================================================================
-- 6. Highest unresolved right-side resistance wins
-- ============================================================================
ranked_right_side AS
(
    SELECT
        u.*,

        ROW_NUMBER() OVER
        (
            PARTITION BY u.security_id
            ORDER BY
                u.candidate_price DESC,
                u.candidate_date DESC
        ) AS rn

    FROM unresolved_right_side u
),

selected_right_side AS
(
    SELECT
        security_id,
        candidate_date,
        candidate_price
    FROM ranked_right_side
    WHERE rn = 1
),

-- ============================================================================
-- 7. Determine whether original prior swing high is still unresolved
-- ============================================================================
prior_high_test AS
(
    SELECT
        e.security_id,
        MAX(b.high_price) AS max_high_after_prior

    FROM episodes e
    CROSS JOIN params p

    LEFT JOIN trn.nse_sec_bhavdata b
        ON b.symbol = e.symbol
       AND b.traded_date > e.prior_swing_high_date
       AND b.traded_date < p.evaluation_date

    GROUP BY
        e.security_id
),

-- ============================================================================
-- 8. Resolve pivot before seeing evaluation session
-- ============================================================================
resolved_pivot AS
(
    SELECT
        e.security_id,
        e.symbol,
        e.trade_date,
        e.base_low_date,
        e.prior_swing_high_date,
        e.prior_swing_high,

        r.candidate_date  AS right_side_pivot_date,
        r.candidate_price AS right_side_pivot_price,

        CASE
            WHEN r.security_id IS NOT NULL
                THEN r.candidate_date

            WHEN ph.max_high_after_prior IS NULL
              OR ph.max_high_after_prior <= e.prior_swing_high
                THEN e.prior_swing_high_date

            ELSE NULL
        END AS pivot_date,

        CASE
            WHEN r.security_id IS NOT NULL
                THEN r.candidate_price

            WHEN ph.max_high_after_prior IS NULL
              OR ph.max_high_after_prior <= e.prior_swing_high
                THEN e.prior_swing_high

            ELSE NULL
        END AS pivot_price,

        CASE
            WHEN r.security_id IS NOT NULL
                THEN 'RIGHT_SIDE_PIVOT'

            WHEN ph.max_high_after_prior IS NULL
              OR ph.max_high_after_prior <= e.prior_swing_high
                THEN 'PRIOR_SWING_HIGH'

            ELSE 'NO_ACTIVE_PIVOT'
        END AS pivot_type

    FROM episodes e

    LEFT JOIN selected_right_side r
        ON r.security_id = e.security_id

    LEFT JOIN prior_high_test ph
        ON ph.security_id = e.security_id
),

-- ============================================================================
-- 9. Evaluation-day OHLC
-- ============================================================================
evaluation_price AS
(
    SELECT
        b.symbol,
        b.high_price,
        b.close_price
    FROM trn.nse_sec_bhavdata b
    CROSS JOIN params p
    WHERE b.traded_date = p.evaluation_date
),

-- ============================================================================
-- 10. Final values
-- ============================================================================
final_rows AS
(
    SELECT
        r.security_id,
        r.trade_date,

        r.base_low_date,
        r.prior_swing_high_date,
        r.prior_swing_high,

        r.right_side_pivot_date,
        r.right_side_pivot_price,

        r.pivot_date,
        r.pivot_price,
        r.pivot_type,

        ep.close_price,

        CASE
            WHEN r.pivot_price IS NOT NULL
             AND r.pivot_price <> 0
            THEN
                ((r.pivot_price - ep.close_price)
                    / r.pivot_price) * 100.0
            ELSE NULL
        END AS distance_to_pivot_pct,

        CASE
            WHEN r.pivot_price IS NULL
                THEN FALSE

            WHEN ep.high_price > r.pivot_price
                THEN TRUE

            ELSE FALSE
        END AS pivot_crossed,

        CASE
            WHEN r.pivot_price IS NOT NULL
             AND ep.high_price > r.pivot_price
                THEN r.trade_date
            ELSE NULL
        END AS pivot_crossed_date

    FROM resolved_pivot r

    LEFT JOIN evaluation_price ep
        ON ep.symbol = r.symbol
)

-- ============================================================================
-- 11. Persist
-- ============================================================================
INSERT INTO trn.stock_pivot_daily
(
    security_id,
    trade_date,

    base_low_date,
    prior_swing_high_date,
    prior_swing_high,

    right_side_pivot_date,
    right_side_pivot_price,

    pivot_date,
    pivot_price,
    pivot_type,

    close_price,
    distance_to_pivot_pct,

    pivot_crossed,
    pivot_crossed_date
)

SELECT
    security_id,
    trade_date,

    base_low_date,
    prior_swing_high_date,
    prior_swing_high,

    right_side_pivot_date,
    right_side_pivot_price,

    pivot_date,
    pivot_price,
    pivot_type,

    close_price,
    distance_to_pivot_pct,

    pivot_crossed,
    pivot_crossed_date

FROM final_rows

ON CONFLICT (security_id, trade_date)
DO UPDATE SET

    base_low_date =
        EXCLUDED.base_low_date,

    prior_swing_high_date =
        EXCLUDED.prior_swing_high_date,

    prior_swing_high =
        EXCLUDED.prior_swing_high,

    right_side_pivot_date =
        EXCLUDED.right_side_pivot_date,

    right_side_pivot_price =
        EXCLUDED.right_side_pivot_price,

    pivot_date =
        EXCLUDED.pivot_date,

    pivot_price =
        EXCLUDED.pivot_price,

    pivot_type =
        EXCLUDED.pivot_type,

    close_price =
        EXCLUDED.close_price,

    distance_to_pivot_pct =
        EXCLUDED.distance_to_pivot_pct,

    pivot_crossed =
        EXCLUDED.pivot_crossed,

    pivot_crossed_date =
        EXCLUDED.pivot_crossed_date,

    created_date =
        CURRENT_TIMESTAMP;