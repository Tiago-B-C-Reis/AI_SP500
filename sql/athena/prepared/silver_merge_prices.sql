-- Prepared statement: silver_merge_prices
-- Parameter ?1 = run_date ('YYYY-MM-DD', the bronze dt partition to promote).
-- Idempotent: re-running any date is a no-op unless the source changed.
-- Dedupe = last-write-wins per (symbol, trade_date) on fetched_at.

MERGE INTO ai_sp500_silver.prices_daily t
USING (
    SELECT symbol, trade_date, open, high, low, close, adj_close, volume, source, fetched_at
    FROM (
        SELECT
            symbol,
            CAST(trade_date AS date)                                    AS trade_date,
            TRY_CAST(open      AS double)                               AS open,
            TRY_CAST(high      AS double)                               AS high,
            TRY_CAST(low       AS double)                               AS low,
            TRY_CAST(close     AS double)                               AS close,
            CAST(adj_close AS double)                                   AS adj_close,
            TRY_CAST(volume    AS bigint)                               AS volume,
            source,
            CAST(from_iso8601_timestamp(fetched_at) AS timestamp)       AS fetched_at,
            row_number() OVER (
                PARTITION BY symbol, CAST(trade_date AS date)
                ORDER BY fetched_at DESC
            ) AS rn
        FROM ai_sp500_bronze.prices
        WHERE dt = ?
    )
    WHERE rn = 1
) s
ON t.symbol = s.symbol AND t.trade_date = s.trade_date
WHEN MATCHED THEN UPDATE SET
    open = s.open, high = s.high, low = s.low, close = s.close,
    adj_close = s.adj_close, volume = s.volume,
    source = s.source, fetched_at = s.fetched_at
WHEN NOT MATCHED THEN INSERT
    (symbol, trade_date, open, high, low, close, adj_close, volume, source, fetched_at)
    VALUES (s.symbol, s.trade_date, s.open, s.high, s.low, s.close,
            s.adj_close, s.volume, s.source, s.fetched_at)
