-- ============================================================================
-- MomentumLab
-- Seed        : Security Universes
-- File        : 006_ref_security_universe_seed.sql
-- Version     : 1.0
-- ============================================================================

INSERT INTO ref.ref_security_universe
(
    universe_code,
    universe_name
)
VALUES
    ('NIFTY_100',          'NIFTY 100'),
    ('NIFTY_500',          'NIFTY 500'),
    ('NIFTY_MIDCAP_250',   'NIFTY Midcap 250'),
    ('NIFTY_SMALLCAP_250', 'NIFTY Smallcap 250'),
    ('FO',                 'F&O Securities')

ON CONFLICT (universe_code)

DO UPDATE SET
    universe_name = EXCLUDED.universe_name,
    is_active     = TRUE;