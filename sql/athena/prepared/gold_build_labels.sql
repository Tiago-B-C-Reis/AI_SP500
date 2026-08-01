-- Prepared statement: gold_build_labels (no parameters)
-- The ONLY legitimate FOLLOWING windows in the codebase: labels look forward
-- by definition. Kept in a separate table so training on the future requires
-- an explicit join. Daily return materialised in its own CTE because nesting
-- one window function inside another's arguments is invalid SQL.

MERGE INTO ai_sp500_gold.labels t
USING (
    WITH r AS (
        SELECT symbol, trade_date, adj_close,
               adj_close / nullif(lag(adj_close) OVER w, 0) - 1 AS ret_1d
        FROM ai_sp500_silver.prices_daily
        WINDOW w AS (PARTITION BY symbol ORDER BY trade_date)
    )
    SELECT symbol, trade_date, fwd_1d, fwd_5d,
           IF(fwd_1d > 0, 1, 0) AS fwd_direction_1d,
           fwd_vol_5d
    FROM (
        SELECT symbol, trade_date,
            lead(adj_close, 1) OVER w / nullif(adj_close, 0) - 1 AS fwd_1d,
            lead(adj_close, 5) OVER w / nullif(adj_close, 0) - 1 AS fwd_5d,
            stddev_samp(ret_1d) OVER (
                PARTITION BY symbol ORDER BY trade_date
                ROWS BETWEEN 1 FOLLOWING AND 5 FOLLOWING
            ) * sqrt(252.0) AS fwd_vol_5d
        FROM r
        WINDOW w AS (PARTITION BY symbol ORDER BY trade_date)
    )
    WHERE fwd_1d IS NOT NULL
) s
ON t.trade_date = s.trade_date AND t.symbol = s.symbol
WHEN MATCHED THEN UPDATE SET
    fwd_return_1d = s.fwd_1d, fwd_return_5d = s.fwd_5d,
    fwd_direction_1d = s.fwd_direction_1d, fwd_volatility_5d = s.fwd_vol_5d
WHEN NOT MATCHED THEN INSERT
    (trade_date, symbol, fwd_return_1d, fwd_return_5d, fwd_direction_1d, fwd_volatility_5d)
    VALUES (s.trade_date, s.symbol, s.fwd_1d, s.fwd_5d, s.fwd_direction_1d, s.fwd_vol_5d)
