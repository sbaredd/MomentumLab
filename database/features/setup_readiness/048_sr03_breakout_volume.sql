-- ============================================================================
-- MomentumLab
-- Feature     : SR03 - Breakout Volume
-- File        : 048_sr03_breakout_volume.sql
-- Version     : 1.1
-- Description : Carries the evaluation session's Relative Volume (20D)
--               into Setup Readiness.
--
-- Historicalization changes:
--   - evaluation_date supplied externally.
--   - security_id mapped to stock_daily_features through security symbol.
--
-- SR03 measurement logic remains unchanged.
-- ============================================================================

WITH params AS
(
    SELECT CAST(:evaluation_date AS DATE) AS evaluation_date
)

UPDATE trn.stock_setup_readiness_daily r

SET
    relative_volume_20 = f.relative_volume_20,
    created_date       = CURRENT_TIMESTAMP

FROM ref.ref_nse_equity_security s,
     trn.stock_daily_features f,
     params p

WHERE r.trade_date = p.evaluation_date

  AND s.security_id = r.security_id

  AND f.symbol = s.symbol
  AND f.trade_date = p.evaluation_date;