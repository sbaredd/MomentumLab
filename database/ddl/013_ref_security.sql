-- ============================================================================
-- Momentum Lab
-- Table       : ref.ref_security
-- File        : 013_ref_security.sql
-- Version     : 1.0
-- Description : Reference data for securities traded in supported markets
-- ============================================================================

CREATE TABLE IF NOT EXISTS ref.ref_security
(
    security_id        BIGSERIAL NOT NULL,
    security_code      VARCHAR(50) NOT NULL,
    security_name      VARCHAR(200) NOT NULL,
    exchange_code      VARCHAR(10) NOT NULL,
    market_code        VARCHAR(20) NOT NULL,
    instrument_type_code VARCHAR(20) NOT NULL,
    isin               VARCHAR(20),
    is_active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_date       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_ref_security
        PRIMARY KEY (security_id),

    CONSTRAINT uq_ref_security_exchange_code
        UNIQUE (exchange_code, security_code),

    CONSTRAINT fk_ref_security_exchange
        FOREIGN KEY (exchange_code)
        REFERENCES ref.ref_exchange (exchange_code),

    CONSTRAINT fk_ref_security_market
        FOREIGN KEY (market_code)
        REFERENCES ref.ref_market (market_code),

    CONSTRAINT fk_ref_security_instrument_type
        FOREIGN KEY (instrument_type_code)
        REFERENCES ref.ref_instrument_type (instrument_type_code)
);
