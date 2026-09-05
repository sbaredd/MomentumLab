-- ============================================================================
-- MomentumLab
-- Table       : trn.nse_price_adjustment_event
-- File        : 032_trn_nse_price_adjustment_event.sql
-- Description : Deterministic price-adjustment events derived from raw NSE
--               corporate actions.
--
-- Supported adjustment types:
--   BONUS
--   STOCK_SPLIT
--
-- Design:
--   1. One adjustment event per raw corporate-action record.
--   2. Multiple events may exist for the same symbol/ex-date.
--   3. Same-day events are compounded downstream.
--   4. Raw NSE corporate-action data remains unchanged.
-- ============================================================================

CREATE TABLE IF NOT EXISTS trn.nse_price_adjustment_event
(
    price_adjustment_event_id  BIGSERIAL NOT NULL,
    corporate_action_id        BIGINT NOT NULL,
    symbol                     VARCHAR(50) NOT NULL,
    ex_date                    DATE NOT NULL,
    adjustment_type            VARCHAR(30) NOT NULL,
    numerator                  NUMERIC(15,6),
    denominator                NUMERIC(15,6),
    price_factor               NUMERIC(18,10) NOT NULL,
    created_date               TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT nse_price_adjustment_event_pkey
        PRIMARY KEY (price_adjustment_event_id),

    CONSTRAINT fk_price_adjustment_corporate_action
        FOREIGN KEY (corporate_action_id)
        REFERENCES trn.nse_corporate_action (corporate_action_id),

    CONSTRAINT uq_price_adjustment_corporate_action
        UNIQUE (corporate_action_id),

    CONSTRAINT ck_price_adjustment_factor
        CHECK (
            price_factor > 0
            AND price_factor <= 1
        ),

    CONSTRAINT ck_price_adjustment_type
        CHECK (
            adjustment_type IN ('BONUS', 'STOCK_SPLIT')
        )
);

COMMENT ON TABLE trn.nse_price_adjustment_event IS
'Deterministic price-adjustment events derived from raw NSE corporate actions.';