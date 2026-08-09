-- ================================================================
-- Momentum Lab
-- Table       : ref.ref_security_sector
-- File        : 017_ref_security_sector.sql
-- Version     : 1.0
-- Description : Historical mapping of securities to sectors
-- ================================================================

CREATE TABLE IF NOT EXISTS ref.ref_security_sector
(
    security_id     BIGINT NOT NULL,
    sector_code     VARCHAR(30) NOT NULL,

    effective_from  DATE NOT NULL,
    effective_to    DATE,

    is_primary      BOOLEAN NOT NULL DEFAULT TRUE,
    created_date    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_ref_security_sector
        PRIMARY KEY (security_id, sector_code, effective_from),

    CONSTRAINT fk_ref_security_sector_security
        FOREIGN KEY (security_id)
        REFERENCES ref.ref_security (security_id),

    CONSTRAINT fk_ref_security_sector_sector
        FOREIGN KEY (sector_code)
        REFERENCES ref.ref_sector (sector_code),

    CONSTRAINT ck_ref_security_sector_dates
        CHECK (
            effective_to IS NULL
            OR effective_to >= effective_from
        )
);
