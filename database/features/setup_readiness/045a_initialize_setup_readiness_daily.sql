-- ============================================================================
-- MomentumLab
-- Table       : trn.stock_setup_readiness_daily
-- File        : 045a_initialize_setup_readiness_daily.sql
-- Description : Initialize daily setup-readiness rows from structural pivot
-- ============================================================================

WITH params AS
(
    SELECT CAST(:evaluation_date AS DATE) AS evaluation_date
),

universe AS
(
    SELECT
        s.security_id
    FROM ref.security_universe_membership um
    JOIN ref.ref_nse_equity_security s
        ON s.security_id = um.security_id
    WHERE um.universe_code = 'NIFTY_100'
),

pivot_context AS
(
    SELECT
        p.security_id,
        p.pivot_date,
        p.pivot_price,
        p.pivot_type
    FROM trn.stock_pivot_daily p
    CROSS JOIN params x
    WHERE p.trade_date = x.evaluation_date
)

INSERT INTO trn.stock_setup_readiness_daily
(
    security_id,
    trade_date,
    pivot_date,
    pivot_price,
    pivot_type
)

SELECT
    u.security_id,
    x.evaluation_date,
    p.pivot_date,
    p.pivot_price,
    p.pivot_type

FROM universe u

CROSS JOIN params x

LEFT JOIN pivot_context p
    ON p.security_id = u.security_id

ON CONFLICT
(
    security_id,
    trade_date
)

DO UPDATE SET

    pivot_date =
        EXCLUDED.pivot_date,

    pivot_price =
        EXCLUDED.pivot_price,

    pivot_type =
        EXCLUDED.pivot_type,

    created_date =
        CURRENT_TIMESTAMP;