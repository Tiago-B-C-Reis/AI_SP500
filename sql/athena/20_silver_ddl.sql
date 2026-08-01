-- Silver: typed, deduplicated Iceberg tables. ACID MERGE targets.
-- Partitioning is deliberately coarse (month) or absent: daily partitions at
-- this volume would manufacture a small-files problem. See ARCHITECTURE.md §6.
-- vacuum_max_snapshot_age_seconds = 90 days: time travel window for lineage.

CREATE TABLE IF NOT EXISTS ai_sp500_silver.prices_daily (
    symbol      string,
    trade_date  date,
    open        double,
    high        double,
    low         double,
    close       double,
    adj_close   double,
    volume      bigint,
    source      string,
    fetched_at  timestamp
)
PARTITIONED BY (month(trade_date))
LOCATION 's3://${LAKE_BUCKET}/silver/prices_daily/'
TBLPROPERTIES ('table_type'='ICEBERG', 'format'='parquet',
               'vacuum_max_snapshot_age_seconds'='7776000');

CREATE TABLE IF NOT EXISTS ai_sp500_silver.news (
    url_hash        string,
    canonical_url   string,
    title           string,
    topic           string,
    source_feed     string,
    sentiment_score double,
    confidence      double,
    relevance_sp500 double,
    tickers         array<string>,
    event_type      string,
    published_at    timestamp,
    ingested_at     timestamp,
    llm_model       string,
    prompt_hash     string
)
LOCATION 's3://${LAKE_BUCKET}/silver/news/'
TBLPROPERTIES ('table_type'='ICEBERG', 'format'='parquet',
               'vacuum_max_snapshot_age_seconds'='7776000');

CREATE TABLE IF NOT EXISTS ai_sp500_silver.macro_series (
    series_id  string,
    obs_date   date,
    value      double,
    unit       string,
    fetched_at timestamp        -- vintage column: restatements arrive as new rows
)
LOCATION 's3://${LAKE_BUCKET}/silver/macro_series/'
TBLPROPERTIES ('table_type'='ICEBERG', 'format'='parquet',
               'vacuum_max_snapshot_age_seconds'='7776000');

-- NYSE calendar. Seeded once from a CSV (generated locally with
-- pandas_market_calendars, uploaded to s3://${LAKE_BUCKET}/seed/trading_days/,
-- inserted via a one-off CTAS). Point-in-time cutoffs depend on it.
CREATE TABLE IF NOT EXISTS ai_sp500_silver.trading_days (
    trade_date       date,
    market_open_utc  timestamp,
    market_close_utc timestamp,
    is_half_day      boolean
)
LOCATION 's3://${LAKE_BUCKET}/silver/trading_days/'
TBLPROPERTIES ('table_type'='ICEBERG', 'format'='parquet');
