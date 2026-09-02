CREATE OR REPLACE VIEW ref.vw_nse_equity_security_classification
AS
SELECT
    m.security_id,
    m.symbol,
    m.company_name,
    m.series,
    m.date_of_listing,
    m.paid_up_value,
    m.market_lot,
    m.isin,
    m.face_value,
    m.is_active,

    s.basic_industry,

    i.industry,
    i.sector,
    i.macro_economic_sector,

    CASE
        WHEN s.security_id IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS has_classification

FROM ref.ref_nse_equity_security m

LEFT JOIN ref.ref_stock_classification s
       ON s.security_id = m.security_id

LEFT JOIN ref.ref_industry_classification i
       ON i.basic_industry = s.basic_industry;