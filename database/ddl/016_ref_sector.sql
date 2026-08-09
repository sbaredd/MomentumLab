-- ================================================================
-- Momentum Lab
-- Table       : ref.ref_sector
-- File        : 016_ref_sector.sql
-- Version     : 1.0
-- Description : Reference data for security sectors
-- ================================================================

CREATE TABLE IF NOT EXISTS ref.ref_sector
(
    sector_code     VARCHAR(30) NOT NULL,
    sector_name     VARCHAR(100) NOT NULL,
    description     VARCHAR(250),

    is_active       BOOLEAN NOT NULL DEFAULT TRUE,

    created_date    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_ref_sector
        PRIMARY KEY (sector_code),

    CONSTRAINT uq_ref_sector_name
        UNIQUE (sector_name)
);
