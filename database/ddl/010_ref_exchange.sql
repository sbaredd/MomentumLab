-- ============================================================================
-- Momentum Lab
-- Table       : ref.ref_exchange
-- File        : 010_ref_exchange.sql
-- Version     : 1.0
-- Description : Reference data for supported exchanges
-- ============================================================================

CREATE TABLE IF NOT EXISTS ref.ref_exchange
(
    exchange_code   VARCHAR(10)  NOT NULL,
    exchange_name   VARCHAR(100) NOT NULL,
    country         VARCHAR(100) NOT NULL,
    currency_code   VARCHAR(10)  NOT NULL,
    time_zone       VARCHAR(50)  NOT NULL,
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
    created_date    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_ref_exchange
        PRIMARY KEY (exchange_code)
);
