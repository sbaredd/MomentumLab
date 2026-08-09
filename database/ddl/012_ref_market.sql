CREATE TABLE IF NOT EXISTS ref.ref_market
(
    market_code     VARCHAR(20)  NOT NULL,
    market_name     VARCHAR(100) NOT NULL,
    exchange_code   VARCHAR(10)  NOT NULL,
    description     VARCHAR(250),
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
    created_date    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_ref_market
        PRIMARY KEY (market_code),

    CONSTRAINT fk_ref_market_exchange
        FOREIGN KEY (exchange_code)
        REFERENCES ref.ref_exchange (exchange_code)
);
