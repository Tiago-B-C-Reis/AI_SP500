-- Iceberg table maintenance — run weekly (Sunday machine, or `make athena-maintain`).
-- OPTIMIZE compacts small files from daily MERGEs; VACUUM expires snapshots older
-- than each table's vacuum_max_snapshot_age_seconds (90 days — the time-travel
-- window that model->data lineage in ops.ml_runs relies on; never shorten it
-- below the retraining cadence).

OPTIMIZE ai_sp500_silver.prices_daily REWRITE DATA USING BIN_PACK;
OPTIMIZE ai_sp500_silver.news         REWRITE DATA USING BIN_PACK;
OPTIMIZE ai_sp500_silver.macro_series REWRITE DATA USING BIN_PACK;
OPTIMIZE ai_sp500_gold.features_daily REWRITE DATA USING BIN_PACK;
OPTIMIZE ai_sp500_gold.labels         REWRITE DATA USING BIN_PACK;
OPTIMIZE ai_sp500_gold.predictions    REWRITE DATA USING BIN_PACK;
OPTIMIZE ai_sp500_ops.dq_results      REWRITE DATA USING BIN_PACK;

VACUUM ai_sp500_silver.prices_daily;
VACUUM ai_sp500_silver.news;
VACUUM ai_sp500_silver.macro_series;
VACUUM ai_sp500_gold.features_daily;
VACUUM ai_sp500_gold.labels;
VACUUM ai_sp500_gold.predictions;
VACUUM ai_sp500_ops.dq_results;
