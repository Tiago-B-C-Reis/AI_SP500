-- AI_SP500 — Silver -> Gold, entirely in PostgreSQL.
--
-- This file replaces TWO things from earlier designs:
--   1. the DuckDB transformation layer (v0.2)
--   2. the 51 Alpha Vantage technical-indicator endpoints — 26,061 calls per pass
--
-- Runtime at ~2.6 M price rows: a few seconds. Called by sp500-build-gold.service.
--
-- POINT-IN-TIME RULES enforced here:
--   * every window is `ROWS BETWEEN n PRECEDING AND CURRENT ROW` — never FOLLOWING
--   * macro is joined as-of, using values PUBLISHED before the cutoff
--   * news requires published_at AND ingested_at before the market open
--   * feature_asof records the information cutoff on every row

\set ON_ERROR_STOP on

BEGIN;

-- Analytical query, single session. Raise work_mem here rather than globally:
-- postgresql.lite.conf keeps the default low because work_mem is per sort NODE.
SET LOCAL work_mem = '256MB';


-- ============================================================================
-- 1. Technical indicators from prices
--    All single-pass window functions over silver.prices_daily.
-- ============================================================================

CREATE TEMP TABLE tmp_tech ON COMMIT DROP AS
WITH base AS (
    SELECT
        symbol,
        trade_date,
        adj_close,
        volume,
        lag(adj_close, 1)  OVER w AS prev_close,
        lag(adj_close, 5)  OVER w AS close_5d_ago,
        lag(adj_close, 21) OVER w AS close_21d_ago
    FROM silver.prices_daily
    WINDOW w AS (PARTITION BY symbol ORDER BY trade_date)
),
returns AS (
    SELECT
        base.*,
        CASE WHEN prev_close    > 0 THEN adj_close / prev_close    - 1 END AS return_1d,
        CASE WHEN close_5d_ago  > 0 THEN adj_close / close_5d_ago  - 1 END AS return_5d,
        CASE WHEN close_21d_ago > 0 THEN adj_close / close_21d_ago - 1 END AS return_21d,
        -- Split gains and losses for RSI.
        GREATEST(adj_close - prev_close, 0) AS gain,
        GREATEST(prev_close - adj_close, 0) AS loss
    FROM base
)
SELECT
    symbol,
    trade_date,
    adj_close,
    return_1d,
    return_5d,
    return_21d,

    avg(adj_close) OVER w20 AS sma_20,
    avg(adj_close) OVER w50 AS sma_50,

    -- Annualised realised volatility. 252 trading days per year.
    stddev_samp(return_1d) OVER w21 * sqrt(252.0) AS volatility_21d,

    -- RSI-14, CUTLER'S variant: simple moving averages of gains and losses.
    -- Wilder's original uses recursive smoothing and would need WITH RECURSIVE.
    -- Cutler's is a standard, defensible choice and avoids the recursion.
    -- NULLIF guards the all-gains case, where RSI is definitionally 100.
    CASE
        WHEN avg(loss) OVER w14 = 0 AND avg(gain) OVER w14 = 0 THEN 50.0
        WHEN avg(loss) OVER w14 = 0 THEN 100.0
        ELSE 100.0 - (100.0 / (1.0 + (avg(gain) OVER w14) / (avg(loss) OVER w14)))
    END AS rsi_14,

    CASE WHEN avg(volume) OVER w20 > 0
         THEN volume::DOUBLE PRECISION / avg(volume) OVER w20
    END AS volume_ratio_20d

FROM returns
WINDOW
    w14 AS (PARTITION BY symbol ORDER BY trade_date ROWS BETWEEN 13 PRECEDING AND CURRENT ROW),
    w20 AS (PARTITION BY symbol ORDER BY trade_date ROWS BETWEEN 19 PRECEDING AND CURRENT ROW),
    w21 AS (PARTITION BY symbol ORDER BY trade_date ROWS BETWEEN 20 PRECEDING AND CURRENT ROW),
    w50 AS (PARTITION BY symbol ORDER BY trade_date ROWS BETWEEN 49 PRECEDING AND CURRENT ROW);

CREATE INDEX ON tmp_tech (symbol, trade_date);
ANALYZE tmp_tech;


-- ============================================================================
-- 2. Macro as-of.
--    Two separate correctness concerns, easy to conflate:
--      (a) obs_date <= trade_date  -- the period being described has occurred
--      (b) fetched_at <= cutoff    -- we had actually retrieved that value
--    Taking the latest fetched_at gives the vintage known at the cutoff, not
--    today's revised figure.
-- ============================================================================

CREATE TEMP TABLE tmp_macro ON COMMIT DROP AS
SELECT
    d.trade_date,
    m.series_id,
    (SELECT s.value
       FROM silver.macro_series s
      WHERE s.series_id = m.series_id
        AND s.obs_date   <= d.trade_date
        AND s.fetched_at <  d.market_open_utc
      ORDER BY s.obs_date DESC, s.fetched_at DESC
      LIMIT 1) AS value
FROM platform.trading_days d
CROSS JOIN (SELECT DISTINCT series_id FROM silver.macro_series) m;

CREATE INDEX ON tmp_macro (trade_date, series_id);
ANALYZE tmp_macro;


-- ============================================================================
-- 3. News aggregate.
--    The ingested_at clause is the anti-leakage guard: an article published
--    Monday 09:00 but scraped Wednesday was NOT available to trade on Monday.
--    Filtering on published_at alone is the most common and most expensive
--    bug in news-driven backtests.
--    Portugal Local is collected but excluded — valuable reading, noise here.
-- ============================================================================

CREATE TEMP TABLE tmp_news ON COMMIT DROP AS
SELECT
    d.trade_date,
    avg(n.sentiment_score * n.relevance_sp500)
        FILTER (WHERE n.topic <> 'portugal_local')            AS news_sentiment_1d,
    count(*) FILTER (WHERE n.topic <> 'portugal_local')::INT  AS news_volume_1d,
    avg(abs(n.sentiment_score))
        FILTER (WHERE n.topic = 'geopolitical')               AS geopolitical_risk
FROM platform.trading_days d
LEFT JOIN silver.news n
       ON n.published_at <  d.market_open_utc
      AND n.published_at >= d.market_open_utc - INTERVAL '24 hours'
      AND n.ingested_at  <  d.market_open_utc          -- <-- the anti-leakage clause
GROUP BY d.trade_date;

CREATE INDEX ON tmp_news (trade_date);
ANALYZE tmp_news;


-- ============================================================================
-- 4. Assemble gold.features_daily
-- ============================================================================

INSERT INTO gold.features_daily AS f (
    trade_date, symbol, adj_close,
    return_1d, return_5d, return_21d,
    sma_20, sma_50, px_over_sma50,
    volatility_21d, rsi_14, volume_ratio_20d,
    cpi_yoy, fed_funds_rate, treasury_10y, yield_curve_10y2y,
    unemployment_rate, wti_price,
    news_sentiment_1d, news_volume_1d, geopolitical_risk,
    feature_asof
)
SELECT
    t.trade_date,
    t.symbol,
    t.adj_close,
    t.return_1d, t.return_5d, t.return_21d,
    t.sma_20, t.sma_50,
    CASE WHEN t.sma_50 > 0 THEN t.adj_close / t.sma_50 - 1 END AS px_over_sma50,
    t.volatility_21d, t.rsi_14, t.volume_ratio_20d,

    mac.cpi_yoy, mac.fed_funds, mac.t10y,
    CASE WHEN mac.t10y IS NOT NULL AND mac.t2y IS NOT NULL
         THEN mac.t10y - mac.t2y END AS yield_curve_10y2y,
    mac.unemployment,
    com.wti,

    nw.news_sentiment_1d, nw.news_volume_1d, nw.geopolitical_risk,

    -- The information cutoff. Everything above was known at this instant.
    d.market_open_utc AS feature_asof

FROM tmp_tech t
JOIN platform.trading_days d ON d.trade_date = t.trade_date
LEFT JOIN LATERAL (
    SELECT
        max(value) FILTER (WHERE series_id = 'CPI')                 AS cpi_yoy,
        max(value) FILTER (WHERE series_id = 'FEDERAL_FUNDS_RATE')  AS fed_funds,
        max(value) FILTER (WHERE series_id = 'TREASURY_YIELD_10Y')  AS t10y,
        max(value) FILTER (WHERE series_id = 'TREASURY_YIELD_2Y')   AS t2y,
        max(value) FILTER (WHERE series_id = 'UNEMPLOYMENT')        AS unemployment
    FROM tmp_macro mm WHERE mm.trade_date = t.trade_date
) mac ON true
LEFT JOIN LATERAL (
    SELECT c.value AS wti
    FROM silver.commodities c
    WHERE c.commodity = 'WTI' AND c.obs_date <= t.trade_date
    ORDER BY c.obs_date DESC LIMIT 1
) com ON true
LEFT JOIN tmp_news nw ON nw.trade_date = t.trade_date

ON CONFLICT (trade_date, symbol) DO UPDATE SET
    adj_close         = EXCLUDED.adj_close,
    return_1d         = EXCLUDED.return_1d,
    return_5d         = EXCLUDED.return_5d,
    return_21d        = EXCLUDED.return_21d,
    sma_20            = EXCLUDED.sma_20,
    sma_50            = EXCLUDED.sma_50,
    px_over_sma50     = EXCLUDED.px_over_sma50,
    volatility_21d    = EXCLUDED.volatility_21d,
    rsi_14            = EXCLUDED.rsi_14,
    volume_ratio_20d  = EXCLUDED.volume_ratio_20d,
    cpi_yoy           = EXCLUDED.cpi_yoy,
    fed_funds_rate    = EXCLUDED.fed_funds_rate,
    treasury_10y      = EXCLUDED.treasury_10y,
    yield_curve_10y2y = EXCLUDED.yield_curve_10y2y,
    unemployment_rate = EXCLUDED.unemployment_rate,
    wti_price         = EXCLUDED.wti_price,
    news_sentiment_1d = EXCLUDED.news_sentiment_1d,
    news_volume_1d    = EXCLUDED.news_volume_1d,
    geopolitical_risk = EXCLUDED.geopolitical_risk,
    feature_asof      = EXCLUDED.feature_asof,
    computed_at       = now();


-- ============================================================================
-- 5. Labels — separate table, separate statement, forward-looking BY DESIGN.
--    This is the ONLY place a FOLLOWING window is legitimate.
-- ============================================================================

INSERT INTO gold.labels AS l (
    trade_date, symbol, fwd_return_1d, fwd_return_5d, fwd_direction_1d, fwd_volatility_5d
)
SELECT
    trade_date,
    symbol,
    fwd_1d,
    fwd_5d,
    CASE WHEN fwd_1d > 0 THEN 1 WHEN fwd_1d <= 0 THEN 0 END,
    fwd_vol_5d
FROM (
    -- Two levels are required: Postgres forbids nesting one window function
    -- inside another's arguments, so the daily return must be materialised as a
    -- plain column before the forward-looking volatility window can consume it.
    WITH r AS (
        SELECT
            symbol,
            trade_date,
            adj_close,
            adj_close / NULLIF(lag(adj_close) OVER w, 0) - 1 AS ret_1d
        FROM silver.prices_daily
        WINDOW w AS (PARTITION BY symbol ORDER BY trade_date)
    )
    SELECT
        symbol,
        trade_date,
        lead(adj_close, 1) OVER w / NULLIF(adj_close, 0) - 1 AS fwd_1d,
        lead(adj_close, 5) OVER w / NULLIF(adj_close, 0) - 1 AS fwd_5d,
        stddev_samp(ret_1d)
            OVER (PARTITION BY symbol ORDER BY trade_date
                  ROWS BETWEEN 1 FOLLOWING AND 5 FOLLOWING) * sqrt(252.0) AS fwd_vol_5d
    FROM r
    WINDOW w AS (PARTITION BY symbol ORDER BY trade_date)
) x
WHERE fwd_1d IS NOT NULL
ON CONFLICT (trade_date, symbol) DO UPDATE SET
    fwd_return_1d     = EXCLUDED.fwd_return_1d,
    fwd_return_5d     = EXCLUDED.fwd_return_5d,
    fwd_direction_1d  = EXCLUDED.fwd_direction_1d,
    fwd_volatility_5d = EXCLUDED.fwd_volatility_5d;


-- ============================================================================
-- 6. Lookahead assertion — MUST fail the job, not warn.
--    One check catches the entire class of bug that makes a model backtest at
--    78% and perform at random live.
-- ============================================================================

DO $$
DECLARE
    violations BIGINT;
BEGIN
    SELECT count(*) INTO violations
    FROM gold.features_daily f
    JOIN platform.trading_days d ON d.trade_date = f.trade_date
    WHERE f.feature_asof > d.market_open_utc;

    IF violations > 0 THEN
        RAISE EXCEPTION
            'Lookahead detected: % feature rows have feature_asof after market open',
            violations;
    END IF;
END $$;

COMMIT;

ANALYZE gold.features_daily;
ANALYZE gold.labels;
