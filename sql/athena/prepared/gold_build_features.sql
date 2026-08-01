-- Prepared statement: gold_build_features (no parameters)
--
-- Full deterministic recompute. At ~2.6M price rows this scans megabytes and
-- costs less than the engineering of incremental logic; revisit past ~50M rows.
-- Ported from sql/002_silver_to_gold.sql (Postgres) to Trino SQL.
--
-- Point-in-time rules:
--   * every indicator window is PRECEDING-only — FOLLOWING would be lookahead
--   * macro joins as-of: obs_date <= trade_date AND fetched_at < market open
--     (the fetched_at clause selects the VINTAGE known at the cutoff,
--      not today's revised figure)
--   * news requires published_at AND ingested_at before the open
--   * feature_asof = market_open_utc, audited by dq check gold_no_lookahead

MERGE INTO ai_sp500_gold.features_daily t
USING (
    WITH base AS (
        SELECT
            symbol, trade_date, adj_close, volume,
            lag(adj_close, 1)  OVER w AS prev_close,
            lag(adj_close, 5)  OVER w AS close_5d_ago,
            lag(adj_close, 21) OVER w AS close_21d_ago
        FROM ai_sp500_silver.prices_daily
        WINDOW w AS (PARTITION BY symbol ORDER BY trade_date)
    ),
    returns AS (
        SELECT base.*,
            IF(prev_close    > 0, adj_close / prev_close    - 1) AS return_1d,
            IF(close_5d_ago  > 0, adj_close / close_5d_ago  - 1) AS return_5d,
            IF(close_21d_ago > 0, adj_close / close_21d_ago - 1) AS return_21d,
            greatest(adj_close - prev_close, 0) AS gain,
            greatest(prev_close - adj_close, 0) AS loss
        FROM base
    ),
    tech AS (
        SELECT
            symbol, trade_date, adj_close, return_1d, return_5d, return_21d,
            avg(adj_close) OVER w20 AS sma_20,
            avg(adj_close) OVER w50 AS sma_50,
            stddev_samp(return_1d) OVER w21 * sqrt(252.0) AS volatility_21d,
            CASE
                WHEN avg(loss) OVER w14 = 0 AND avg(gain) OVER w14 = 0 THEN 50.0
                WHEN avg(loss) OVER w14 = 0 THEN 100.0
                ELSE 100.0 - (100.0 / (1.0 + (avg(gain) OVER w14) / (avg(loss) OVER w14)))
            END AS rsi_14,
            IF(avg(volume) OVER w20 > 0,
               CAST(volume AS double) / avg(volume) OVER w20) AS volume_ratio_20d
        FROM returns
        WINDOW
            w14 AS (PARTITION BY symbol ORDER BY trade_date ROWS BETWEEN 13 PRECEDING AND CURRENT ROW),
            w20 AS (PARTITION BY symbol ORDER BY trade_date ROWS BETWEEN 19 PRECEDING AND CURRENT ROW),
            w21 AS (PARTITION BY symbol ORDER BY trade_date ROWS BETWEEN 20 PRECEDING AND CURRENT ROW),
            w50 AS (PARTITION BY symbol ORDER BY trade_date ROWS BETWEEN 49 PRECEDING AND CURRENT ROW)
    ),
    macro_asof AS (
        -- Latest vintage of each series known before each day's market open.
        SELECT trade_date, series_id, value FROM (
            SELECT d.trade_date, m.series_id, m.value,
                   row_number() OVER (
                       PARTITION BY d.trade_date, m.series_id
                       ORDER BY m.obs_date DESC, m.fetched_at DESC
                   ) AS rn
            FROM ai_sp500_silver.trading_days d
            JOIN ai_sp500_silver.macro_series m
              ON m.obs_date   <= d.trade_date
             AND m.fetched_at <  d.market_open_utc
        ) WHERE rn = 1
    ),
    macro_pivot AS (
        SELECT trade_date,
            max(IF(series_id = 'CPI',                value)) AS cpi_yoy,
            max(IF(series_id = 'FEDERAL_FUNDS_RATE', value)) AS fed_funds_rate,
            max(IF(series_id = 'TREASURY_YIELD_10Y', value)) AS treasury_10y,
            max(IF(series_id = 'UNEMPLOYMENT',       value)) AS unemployment_rate
        FROM macro_asof GROUP BY trade_date
    ),
    news_agg AS (
        -- ingested_at < open is the anti-leakage clause: an article published
        -- Monday but scraped Wednesday was not tradable Monday.
        SELECT d.trade_date,
            avg(IF(n.topic <> 'portugal_local',
                   n.sentiment_score * n.relevance_sp500))       AS news_sentiment_1d,
            CAST(count_if(n.topic <> 'portugal_local') AS integer) AS news_volume_1d,
            avg(IF(n.topic = 'geopolitical', abs(n.sentiment_score))) AS geopolitical_risk
        FROM ai_sp500_silver.trading_days d
        LEFT JOIN ai_sp500_silver.news n
               ON n.published_at <  d.market_open_utc
              AND n.published_at >= d.market_open_utc - INTERVAL '24' HOUR
              AND n.ingested_at  <  d.market_open_utc
        GROUP BY d.trade_date
    )
    SELECT
        tech.trade_date, tech.symbol, tech.adj_close,
        tech.return_1d, tech.return_5d, tech.return_21d,
        tech.sma_20, tech.sma_50,
        IF(tech.sma_50 > 0, tech.adj_close / tech.sma_50 - 1) AS px_over_sma50,
        tech.volatility_21d, tech.rsi_14, tech.volume_ratio_20d,
        mp.cpi_yoy, mp.fed_funds_rate, mp.treasury_10y, mp.unemployment_rate,
        na.news_sentiment_1d, na.news_volume_1d, na.geopolitical_risk,
        d.market_open_utc AS feature_asof,
        current_timestamp AS computed_at
    FROM tech
    JOIN ai_sp500_silver.trading_days d ON d.trade_date = tech.trade_date
    LEFT JOIN macro_pivot mp ON mp.trade_date = tech.trade_date
    LEFT JOIN news_agg   na ON na.trade_date = tech.trade_date
) s
ON t.trade_date = s.trade_date AND t.symbol = s.symbol
WHEN MATCHED THEN UPDATE SET
    adj_close = s.adj_close, return_1d = s.return_1d, return_5d = s.return_5d,
    return_21d = s.return_21d, sma_20 = s.sma_20, sma_50 = s.sma_50,
    px_over_sma50 = s.px_over_sma50, volatility_21d = s.volatility_21d,
    rsi_14 = s.rsi_14, volume_ratio_20d = s.volume_ratio_20d,
    cpi_yoy = s.cpi_yoy, fed_funds_rate = s.fed_funds_rate,
    treasury_10y = s.treasury_10y, unemployment_rate = s.unemployment_rate,
    news_sentiment_1d = s.news_sentiment_1d, news_volume_1d = s.news_volume_1d,
    geopolitical_risk = s.geopolitical_risk,
    feature_asof = s.feature_asof, computed_at = s.computed_at
WHEN NOT MATCHED THEN INSERT
    (trade_date, symbol, adj_close, return_1d, return_5d, return_21d, sma_20, sma_50,
     px_over_sma50, volatility_21d, rsi_14, volume_ratio_20d, cpi_yoy, fed_funds_rate,
     treasury_10y, unemployment_rate, news_sentiment_1d, news_volume_1d,
     geopolitical_risk, feature_asof, computed_at)
    VALUES (s.trade_date, s.symbol, s.adj_close, s.return_1d, s.return_5d, s.return_21d,
            s.sma_20, s.sma_50, s.px_over_sma50, s.volatility_21d, s.rsi_14,
            s.volume_ratio_20d, s.cpi_yoy, s.fed_funds_rate, s.treasury_10y,
            s.unemployment_rate, s.news_sentiment_1d, s.news_volume_1d,
            s.geopolitical_risk, s.feature_asof, s.computed_at)
