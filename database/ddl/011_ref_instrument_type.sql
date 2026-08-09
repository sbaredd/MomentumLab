-- ============================================================================
-- Momentum Lab
-- Table       : ref.ref_instrument_type
-- File        : 011_ref_instrument_type.sql
-- Version     : 1.0
-- Description : Reference data for security/instrument types
-- ============================================================================

CREATE TABLE IF NOT EXISTS ref.ref_instrument_type
(
    instrument_type_code   VARCHAR(20)  NOT NULL,
    instrument_type_name   VARCHAR(100) NOT NULL,
    description            VARCHAR(250),
    is_active              BOOLEAN      NOT NULL DEFAULT TRUE,
    created_date           TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_ref_instrument_type
        PRIMARY KEY (instrument_type_code)
);
