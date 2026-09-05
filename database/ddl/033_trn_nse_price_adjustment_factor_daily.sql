-- ============================================================================
-- MomentumLab
-- Table       : trn.nse_price_adjustment_factor_daily
-- File        : 033_trn_nse_price_adjustment_factor_daily.sql
-- Description : Daily cumulative historical price-adjustment factor by symbol.
--
-- Design:
--   1. One row per symbol / trading date.
--   2. price_adjustment_factor represents the cumulative factor required to
--      restate that historical price onto the current post-action price basis.
--   3. Multiple qualifying future corporate-action events are compounded.
--   4. contributing_event_count records how many adjustment events contribute
--      to the factor for that stock-date.
-- ============================================================================

CREATE TABLE IF NOT EXISTS trn.nse_price_adjustment_factor_daily
(
    traded_date               DATE NOT NULL,
    symbol                    VARCHAR(50) NOT NULL,
    price_adjustment_factor   NUMERIC(20,10) NOT NULL,
    contributing_event_count  INTEGER NOT NULL,
    calculated_date           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_nse_price_adjustment_factor_daily
        PRIMARY KEY (traded_date, symbol),

    CONSTRAINT ck_nse_price_adjustment_factor_positive
        CHECK (price_adjustment_factor > 0),

    CONSTRAINT ck_nse_price_adjustment_event_count
        CHECK (contributing_event_count >= 0)
);

COMMENT ON TABLE trn.nse_price_adjustment_factor_daily IS
'Daily cumulative historical price-adjustment factor derived from deterministic corporate-action events.';