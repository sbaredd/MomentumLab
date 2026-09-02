-- ============================================================================
-- MomentumLab
-- Table       : ref.security_universe_membership
-- File        : 029_ref_security_universe_membership.sql
-- Version     : 1.0
--
-- Purpose:
--   Stores current security membership for each supported stock universe.
--
-- Examples:
--   NIFTY_100
--   NIFTY_500
--   NIFTY_MIDCAP_250
--   NIFTY_SMALLCAP_250
--   FO
--
-- Important:
--   Current-state membership only.
--   Historical effective dates are intentionally not maintained.
-- ============================================================================

CREATE TABLE IF NOT EXISTS ref.security_universe_membership
(
    universe_code   VARCHAR(50) NOT NULL,
    security_id     BIGINT      NOT NULL,
    created_date    TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_security_universe_membership
        PRIMARY KEY (universe_code, security_id),

    CONSTRAINT fk_security_universe_membership_universe
        FOREIGN KEY (universe_code)
        REFERENCES ref.ref_security_universe(universe_code),

    CONSTRAINT fk_security_universe_membership_security
        FOREIGN KEY (security_id)
        REFERENCES ref.ref_nse_equity_security(security_id)
);