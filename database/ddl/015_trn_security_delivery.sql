-- ================================================================
-- Momentum Lab
-- Table       : trn.security_delivery
-- File        : 015_trn_security_delivery.sql
-- Version     : 1.0
-- Description : Daily delivery data for securities
-- ================================================================

CREATE TABLE IF NOT EXISTS trn.security_delivery
(
    security_id         BIGINT NOT NULL,
    traded_date         DATE NOT NULL,

    delivery_quantity   BIGINT NOT NULL,
    delivery_percentage NUMERIC(7,4) NOT NULL,

    created_date        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_security_delivery
        PRIMARY KEY (security_id, traded_date),

    CONSTRAINT fk_security_delivery_security
        FOREIGN KEY (security_id)
        REFERENCES ref.ref_security (security_id),

    CONSTRAINT ck_security_delivery_quantity
        CHECK (delivery_quantity >= 0),

    CONSTRAINT ck_security_delivery_percentage
        CHECK (
            delivery_percentage >= 0
            AND delivery_percentage <= 100
        )
);
