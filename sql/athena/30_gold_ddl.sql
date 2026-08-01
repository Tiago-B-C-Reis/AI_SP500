-- Gold: the only layer ML reads. Labels live apart from features so training
-- on the future requires a deliberate, visible join.
-- Ops: the audit trail (pipeline runs, DQ results, ML runs with snapshot lineage).

CREATE TABLE IF NOT EXISTS ai_sp500_gold.features_daily (
    trade_date        date,
    symbol            string,
    adj_close         double,
    return_1d         double,
    return_5d         double,
    return_21d        double,
    sma_20            double,
    sma_50            double,
    px_over_sma50     double,
    volatility_21d    double,
    rsi_14            double,      -- Cutler's variant (SMA-based)
    volume_ratio_20d  double,
    cpi_yoy           double,
    fed_funds_rate    double,
    treasury_10y      double,
    unemployment_rate double,
    news_sentiment_1d double,
    news_volume_1d    integer,
    geopolitical_risk double,
    feature_asof      timestamp,   -- information cutoff; audited by dq gold_no_lookahead
    computed_at       timestamp
)
PARTITIONED BY (month(trade_date))
LOCATION 's3://${LAKE_BUCKET}/gold/features_daily/'
TBLPROPERTIES ('table_type'='ICEBERG', 'format'='parquet',
               'vacuum_max_snapshot_age_seconds'='7776000');

CREATE TABLE IF NOT EXISTS ai_sp500_gold.labels (
    trade_date        date,
    symbol            string,
    fwd_return_1d     double,
    fwd_return_5d     double,
    fwd_direction_1d  integer,
    fwd_volatility_5d double
)
PARTITIONED BY (month(trade_date))
LOCATION 's3://${LAKE_BUCKET}/gold/labels/'
TBLPROPERTIES ('table_type'='ICEBERG', 'format'='parquet');

CREATE TABLE IF NOT EXISTS ai_sp500_gold.predictions (
    trade_date    date,
    symbol        string,
    model_name    string,
    model_version string,
    prediction    double,
    probability   double,
    predicted_at  timestamp
)
LOCATION 's3://${LAKE_BUCKET}/gold/predictions/'
TBLPROPERTIES ('table_type'='ICEBERG', 'format'='parquet');

CREATE TABLE IF NOT EXISTS ai_sp500_ops.dq_results (
    run_date    date,
    layer       string,      -- 'silver' | 'gold'
    check_name  string,
    severity    string,      -- 'error' gates promotion; 'warn' is recorded only
    violations  bigint,
    status      string,      -- 'pass' | 'fail'
    run_ts      timestamp
)
LOCATION 's3://${LAKE_BUCKET}/ops/dq_results/'
TBLPROPERTIES ('table_type'='ICEBERG', 'format'='parquet');

CREATE TABLE IF NOT EXISTS ai_sp500_ops.ml_runs (
    run_id           string,
    model_name       string,
    model_version    string,
    params           string,     -- JSON
    metrics          string,     -- JSON: accuracy, auc, sharpe, vs_baseline
    feature_list     array<string>,
    train_start      date,
    train_end        date,
    test_start       date,
    test_end         date,
    embargo_days     integer,
    gold_snapshot_id bigint,     -- Iceberg snapshot of features_daily at training time:
                                 -- exact model->data lineage via time travel
    artifact_s3      string,
    git_sha          string,
    created_at       timestamp
)
LOCATION 's3://${LAKE_BUCKET}/ops/ml_runs/'
TBLPROPERTIES ('table_type'='ICEBERG', 'format'='parquet');
