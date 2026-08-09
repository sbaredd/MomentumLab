-- ============================================================================
-- Momentum Lab
-- Table       : trn.security_price
-- File        : 014_trn_security_price.sql
-- Version     : 1.0
-- Description : Daily OHLCV price data for securities
-- ============================================================================

CREATE TABLE IF NOT EXISTS trn.security_price
(
    security_id    BIGINT NOT NULL,
    traded_date    DATE NOT NULL,

    open_price     NUMERIC(18,6) NOT NULL,
    high_price     NUMERIC(18,6) NOT NULL,
    low_price      NUMERIC(18,6) NOT NULL,
    close_price    NUMERIC(18,6) NOT NULL,
    volume         BIGINT NOT NULL,

    created_date   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_security_price
        PRIMARY KEY (security_id, traded_date),

    CONSTRAINT fk_security_price_security
        FOREIGN KEY (security_id)
        REFERENCES ref.ref_security (security_id),

    CONSTRAINT ck_security_price_high
        CHECK (high_price >= open_price
            AND high_price >= close_price
            AND high_price >= low_price),

    CONSTRAINT ck_security_price_low
        CHECK (low_price <= open_price
            AND low_price <= close_price
            AND low_price <= high_price),

    CONSTRAINT ck_security_price_volume
        CHECK (volume >= 0)
);
