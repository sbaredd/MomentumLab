-- ============================================================================
-- MomentumLab
-- Table       : ref.ref_security_universe
-- File        : 028_ref_security_universe.sql
-- Version     : 1.0
--
-- Purpose:
--   Master list of supported stock universes used for screening and
--   feature calculations.
-- ============================================================================

CREATE TABLE IF NOT EXISTS ref.ref_security_universe
(
    universe_code   VARCHAR(50)  NOT NULL,
    universe_name   VARCHAR(100) NOT NULL,
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
    created_date    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_ref_security_universe
        PRIMARY KEY (universe_code),

    CONSTRAINT uq_ref_security_universe_name
        UNIQUE (universe_name)
);