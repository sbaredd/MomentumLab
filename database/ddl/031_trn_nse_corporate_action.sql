-- ============================================================================
-- MomentumLab
-- Table       : trn.nse_corporate_action
-- File        : 031_trn_nse_corporate_action.sql
-- Description : Raw NSE corporate-action events
--
-- Design:
--   1. Preserve NSE corporate-action data in source form.
--   2. Do not derive price-adjustment semantics in this table.
--   3. BONUS / STOCK_SPLIT interpretation belongs to the downstream
--      price-adjustment event layer.
--   4. Natural uniqueness supports idempotent ingestion.
-- ============================================================================

CREATE TABLE IF NOT EXISTS trn.nse_corporate_action
(
    corporate_action_id       BIGSERIAL NOT NULL,
    symbol                    VARCHAR(50) NOT NULL,
    company_name              VARCHAR(250),
    series                    VARCHAR(20),
    purpose                   VARCHAR(500) NOT NULL,
    face_value                NUMERIC(15,4),
    ex_date                   DATE NOT NULL,
    record_date               DATE,
    book_closure_start_date   DATE,
    book_closure_end_date     DATE,
    source                    VARCHAR(50) NOT NULL DEFAULT 'NSE',
    loaded_date               TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT nse_corporate_action_pkey
        PRIMARY KEY (corporate_action_id),

    CONSTRAINT uq_nse_corporate_action
        UNIQUE (symbol, series, purpose, ex_date)
);

COMMENT ON TABLE trn.nse_corporate_action IS
'Raw corporate-action events sourced from NSE. Adjustment interpretation is handled downstream.';