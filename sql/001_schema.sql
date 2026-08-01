-- AI_SP500 — architecture v0.3 "Lite" schema
--
-- One PostgreSQL instance on the MP9 is the ENTIRE warehouse: no Parquet tier,
-- no query engine, no catalog service. At ~3.5 M fully-backfilled rows this is
-- not a compromise — it is the right size of tool.
--
--   psql -h mp9.lan -U sp500 -d aisp500 -f sql/001_schema.sql

BEGIN;

CREATE SCHEMA IF NOT EXISTS platform;  -- control plane: what ran, how far it got
CREATE SCHEMA IF NOT EXISTS silver;    -- typed, deduplicated source data
CREATE SCHEMA IF NOT EXISTS gold;      -- features, labels, predictions
CREATE SCHEMA IF NOT EXISTS ml;        -- experiment tracking (replaces MLflow)


-- ============================================================================
-- platform — the single control plane for BOTH feeds
--   * Python ingestion jobs on the MP9
--   * the n8n News_MultiAgent workflow on the TrueNAS
-- One table means one query answers "is the platform healthy?".
-- ============================================================================

CREATE TABLE IF NOT EXISTS platform.ingestion_log (
    id              BIGSERIAL   PRIMARY KEY,
    run_id          UUID        NOT NULL,
    feed            TEXT        NOT NULL,   -- alpha_vantage | yfinance | n8n_news
    source          TEXT        NOT NULL,   -- API function name or RSS topic
    entity          TEXT,                   -- ticker / series id, NULL for index-level
    status          TEXT        NOT NULL
                    CHECK (status IN ('success','failed','skipped','partial')),
    destination     TEXT,                   -- s3://... or schema.table
    record_count    INTEGER,
    bytes           BIGINT,
    duration_ms     INTEGER,
    error_message   TEXT,                   -- TEXT: real stack traces do not fit VARCHAR(255)
    started_at      TIMESTAMPTZ NOT NULL,
    finished_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_ingestion_log_feed_time
    ON platform.ingestion_log (feed, started_at DESC);
-- Partial index: failures are rare, and this is the query n8n's watchdog runs.
CREATE INDEX IF NOT EXISTS ix_ingestion_log_failures
    ON platform.ingestion_log (started_at DESC)
    WHERE status <> 'success';


-- Resumability. Replaces Data/year_quarter_List.json, which lived on a container
-- filesystem, could not be read concurrently, and was invisible to any dashboard.
CREATE TABLE IF NOT EXISTS platform.watermark (
    feed            TEXT        NOT NULL,
    source          TEXT        NOT NULL,
    entity          TEXT        NOT NULL DEFAULT '',
    last_value      TEXT        NOT NULL,   -- ISO week, date, or quarter
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (feed, source, entity)
);


-- NYSE calendar. Required for point-in-time correctness: features must be cut
-- at the market open of the day they predict, not at midnight UTC.
CREATE TABLE IF NOT EXISTS platform.trading_days (
    trade_date      DATE        PRIMARY KEY,
    market_open_utc TIMESTAMPTZ NOT NULL,
    market_close_utc TIMESTAMPTZ NOT NULL,
    is_half_day     BOOLEAN     NOT NULL DEFAULT false
);


-- ============================================================================
-- silver — typed and deduplicated. Postgres tables, not Parquet files.
-- Same columns and keys as v0.2 specified; only the storage medium changed.
-- ============================================================================

CREATE TABLE IF NOT EXISTS silver.prices_daily (
    symbol          TEXT        NOT NULL,
    trade_date      DATE        NOT NULL,
    open            DOUBLE PRECISION,
    high            DOUBLE PRECISION,
    low             DOUBLE PRECISION,
    close           DOUBLE PRECISION,
    adj_close       DOUBLE PRECISION NOT NULL,
    volume          BIGINT,
    source          TEXT        NOT NULL DEFAULT 'alpha_vantage',
    fetched_at      TIMESTAMPTZ NOT NULL,   -- when WE retrieved it (vintage tracking)
    PRIMARY KEY (symbol, trade_date)
);
CREATE INDEX IF NOT EXISTS ix_prices_date ON silver.prices_daily (trade_date);


CREATE TABLE IF NOT EXISTS silver.fundamentals (
    symbol          TEXT        NOT NULL,
    period_end      DATE        NOT NULL,   -- the quarter this describes
    statement       TEXT        NOT NULL,   -- income | balance | cashflow | earnings
    -- Alpha Vantage's field set varies by statement type; JSONB avoids 200 sparse
    -- columns. Extract into typed columns in gold only for fields actually used.
    payload         JSONB       NOT NULL,
    reported_at     DATE,                   -- when the FILING became public
    fetched_at      TIMESTAMPTZ NOT NULL,   -- when we retrieved it
    PRIMARY KEY (symbol, period_end, statement, fetched_at)
);
-- NOTE: fetched_at is in the PK on purpose. Alpha Vantage returns the CURRENT
-- value of a historical quarter, so restatements arrive as new rows rather than
-- overwriting history. Filter on reported_at <= prediction date when building
-- features, or the model learns from figures that did not exist yet.
CREATE INDEX IF NOT EXISTS ix_fundamentals_lookup
    ON silver.fundamentals (symbol, period_end, reported_at);


CREATE TABLE IF NOT EXISTS silver.macro_series (
    series_id       TEXT        NOT NULL,   -- CPI, REAL_GDP, FEDERAL_FUNDS_RATE, ...
    obs_date        DATE        NOT NULL,   -- period the observation describes
    value           DOUBLE PRECISION,
    unit            TEXT,
    fetched_at      TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (series_id, obs_date, fetched_at)
);
-- Same vintage logic: GDP and payrolls are revised for months after first release.
-- FRED publishes vintages (ALFRED); Alpha Vantage does not, so we build our own
-- vintage history from today forward. Past vintages cannot be recovered.
CREATE INDEX IF NOT EXISTS ix_macro_lookup
    ON silver.macro_series (series_id, obs_date DESC, fetched_at DESC);


CREATE TABLE IF NOT EXISTS silver.commodities (
    commodity       TEXT        NOT NULL,   -- WTI, BRENT, COPPER, ...
    obs_date        DATE        NOT NULL,
    value           DOUBLE PRECISION,
    fetched_at      TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (commodity, obs_date)
);


-- Written by the n8n News_MultiAgent workflow over the LAN.
CREATE TABLE IF NOT EXISTS silver.news (
    -- md5(lower(trim(canonical_url))) — syndication means the same story arrives
    -- from many feeds; title matching is not enough.
    url_hash        TEXT        PRIMARY KEY,
    canonical_url   TEXT        NOT NULL,
    title           TEXT,
    topic           TEXT        NOT NULL,   -- financial_macro | geopolitical | technology | portugal_local
    source_feed     TEXT,

    -- Bounded numeric scores. Prose sentiment is not comparable across days.
    sentiment_score DOUBLE PRECISION CHECK (sentiment_score BETWEEN -1 AND 1),
    confidence      DOUBLE PRECISION CHECK (confidence      BETWEEN  0 AND 1),
    relevance_sp500 DOUBLE PRECISION CHECK (relevance_sp500 BETWEEN  0 AND 1),
    tickers         TEXT[],
    topics          TEXT[],
    event_type      TEXT,

    -- The two timestamps that prevent the most expensive backtest bug there is.
    published_at    TIMESTAMPTZ NOT NULL,   -- when the world learned it
    ingested_at     TIMESTAMPTZ NOT NULL,   -- when WE learned it

    -- Provenance. Changing model or prompt creates a discontinuity in the feature
    -- that a model will happily read as a real market signal.
    llm_model       TEXT        NOT NULL,   -- e.g. llama3.1:8b-instruct-q4_K_M
    prompt_hash     TEXT        NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_news_time  ON silver.news (published_at DESC, ingested_at DESC);
CREATE INDEX IF NOT EXISTS ix_news_topic ON silver.news (topic, published_at DESC);


-- ============================================================================
-- gold — the ONLY contract the ML layer sees. It never reads silver, never
-- reads S3, never re-derives a feature.
-- ============================================================================

CREATE TABLE IF NOT EXISTS gold.features_daily (
    trade_date          DATE        NOT NULL,
    symbol              TEXT        NOT NULL,   -- '^GSPC' for the index itself

    -- price & technical (computed in SQL — see 002_silver_to_gold.sql)
    adj_close           DOUBLE PRECISION,
    return_1d           DOUBLE PRECISION,
    return_5d           DOUBLE PRECISION,
    return_21d          DOUBLE PRECISION,
    sma_20              DOUBLE PRECISION,
    sma_50              DOUBLE PRECISION,
    px_over_sma50       DOUBLE PRECISION,
    volatility_21d      DOUBLE PRECISION,
    rsi_14              DOUBLE PRECISION,       -- Cutler's variant (SMA-based)
    volume_ratio_20d    DOUBLE PRECISION,

    -- macro: as-of, forward-filled from the last value PUBLISHED before the cutoff
    cpi_yoy             DOUBLE PRECISION,
    fed_funds_rate      DOUBLE PRECISION,
    treasury_10y        DOUBLE PRECISION,
    yield_curve_10y2y   DOUBLE PRECISION,
    unemployment_rate   DOUBLE PRECISION,
    wti_price           DOUBLE PRECISION,

    -- news: strictly articles published AND ingested before the open
    news_sentiment_1d   DOUBLE PRECISION,
    news_volume_1d      INTEGER,
    geopolitical_risk   DOUBLE PRECISION,

    -- provenance: the information cutoff this row was built under.
    -- Makes leakage auditable instead of a matter of trust.
    feature_asof        TIMESTAMPTZ NOT NULL,
    computed_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (trade_date, symbol)
);
CREATE INDEX IF NOT EXISTS ix_features_date ON gold.features_daily (trade_date DESC);


-- Deliberately a separate table. Physically separating labels from features
-- means training on the future requires an explicit, visible join.
CREATE TABLE IF NOT EXISTS gold.labels (
    trade_date          DATE NOT NULL,
    symbol              TEXT NOT NULL,
    fwd_return_1d       DOUBLE PRECISION,
    fwd_return_5d       DOUBLE PRECISION,
    fwd_direction_1d    SMALLINT CHECK (fwd_direction_1d IN (0,1)),
    fwd_volatility_5d   DOUBLE PRECISION,
    regime              TEXT CHECK (regime IN ('bull','bear','sideways')),
    PRIMARY KEY (trade_date, symbol)
);


CREATE TABLE IF NOT EXISTS gold.predictions (
    trade_date      DATE        NOT NULL,
    symbol          TEXT        NOT NULL,
    model_name      TEXT        NOT NULL,
    model_version   TEXT        NOT NULL,
    prediction      DOUBLE PRECISION NOT NULL,
    probability     DOUBLE PRECISION,
    predicted_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (trade_date, symbol, model_name, model_version)
);


-- ============================================================================
-- ml — replaces MLflow. One table, queryable with SQL, zero resident memory.
-- Add MLflow later ON THE MP9 if run comparison ever gets tedious.
-- ============================================================================

CREATE TABLE IF NOT EXISTS ml.experiment_run (
    run_id          UUID        PRIMARY KEY,
    model_name      TEXT        NOT NULL,
    model_version   TEXT        NOT NULL,
    params          JSONB       NOT NULL,   -- hyperparameters
    metrics         JSONB       NOT NULL,   -- accuracy, auc, sharpe, vs_baseline...
    feature_list    TEXT[]      NOT NULL,
    train_start     DATE        NOT NULL,
    train_end       DATE        NOT NULL,
    test_start      DATE        NOT NULL,
    test_end        DATE        NOT NULL,
    embargo_days    INTEGER     NOT NULL DEFAULT 0,   -- gap between train and test
    artifact_path   TEXT,                             -- /opt/ai_sp500/models/...
    git_sha         TEXT,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_experiment_model ON ml.experiment_run (model_name, created_at DESC);


-- ============================================================================
-- Operational views — what Airflow's UI would otherwise have shown you.
-- ============================================================================

-- "Is the platform healthy?" in one query. n8n emails this daily.
CREATE OR REPLACE VIEW platform.v_feed_health AS
SELECT
    feed,
    max(started_at)                                   AS last_run,
    now() - max(started_at)                           AS age,
    count(*) FILTER (WHERE status = 'success'
                       AND started_at > now() - INTERVAL '24 hours') AS ok_24h,
    count(*) FILTER (WHERE status = 'failed'
                       AND started_at > now() - INTERVAL '24 hours') AS failed_24h,
    sum(record_count) FILTER (WHERE started_at > now() - INTERVAL '24 hours') AS rows_24h
FROM platform.ingestion_log
GROUP BY feed;

-- The silent failure mode: a job that runs, reports success, and returns nothing.
-- A freshness check catches what a status check cannot.
CREATE OR REPLACE VIEW platform.v_staleness AS
SELECT 'silver.prices_daily' AS table_name,
       max(trade_date)::TIMESTAMPTZ AS newest,
       now() - max(trade_date)::TIMESTAMPTZ AS age
FROM silver.prices_daily
UNION ALL
SELECT 'silver.news', max(ingested_at), now() - max(ingested_at) FROM silver.news
UNION ALL
SELECT 'gold.features_daily', max(computed_at), now() - max(computed_at) FROM gold.features_daily;

COMMIT;
