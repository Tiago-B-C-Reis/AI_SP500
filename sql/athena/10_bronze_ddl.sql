-- Bronze: external tables over normalized JSONL.gz written by the edge jobs.
-- Schema-on-read; typing happens in silver. NO crawlers — partition projection
-- resolves dt=YYYY-MM-DD prefixes at query time with zero catalog maintenance.
--
-- ${LAKE_BUCKET} is substituted by `make athena-apply` (envsubst).
-- Malformed JSON fails the query on purpose: bad data should be loud, then
-- quarantined by the edge job — never silently nulled.

CREATE EXTERNAL TABLE IF NOT EXISTS ai_sp500_bronze.prices (
    symbol       string,
    trade_date   string,
    open         string,
    high         string,
    low          string,
    close        string,
    adj_close    string,
    volume       string,
    source       string,
    fetched_at   string
)
PARTITIONED BY (dt string)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://${LAKE_BUCKET}/bronze/prices/'
TBLPROPERTIES (
    'projection.enabled'          = 'true',
    'projection.dt.type'          = 'date',
    'projection.dt.range'         = '2020-01-01,NOW',
    'projection.dt.format'        = 'yyyy-MM-dd',
    'storage.location.template'   = 's3://${LAKE_BUCKET}/bronze/prices/dt=${dt}/'
);

CREATE EXTERNAL TABLE IF NOT EXISTS ai_sp500_bronze.news (
    url_hash        string,
    canonical_url   string,
    title           string,
    topic           string,
    source_feed     string,
    sentiment_score string,
    confidence      string,
    relevance_sp500 string,
    tickers         array<string>,
    event_type      string,
    published_at    string,
    ingested_at     string,
    llm_model       string,
    prompt_hash     string
)
PARTITIONED BY (dt string)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://${LAKE_BUCKET}/bronze/news/'
TBLPROPERTIES (
    'projection.enabled'        = 'true',
    'projection.dt.type'        = 'date',
    'projection.dt.range'       = '2020-01-01,NOW',
    'projection.dt.format'      = 'yyyy-MM-dd',
    'storage.location.template' = 's3://${LAKE_BUCKET}/bronze/news/dt=${dt}/'
);

-- macro_series and commodities follow the prices pattern exactly:
-- (series_id/commodity, obs_date, value, unit, fetched_at) + dt projection.
