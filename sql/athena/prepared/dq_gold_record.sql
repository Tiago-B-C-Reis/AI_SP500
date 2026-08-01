-- Prepared statement: dq_gold_record — parameter ?1 = run_date (used once;
-- the params CTE fans it out so EXECUTE ... USING takes exactly one value).
-- The gate that matters most is gold_no_lookahead: a feature row whose
-- information cutoff is after its market open would backtest beautifully and
-- fail live. It is severity='error' and can never be waived.

INSERT INTO ai_sp500_ops.dq_results
    (run_date, layer, check_name, severity, violations, status, run_ts)
WITH params AS (
    SELECT CAST(? AS date) AS run_date
),
checks AS (
    -- 1. THE lookahead assertion
    SELECT 'gold_no_lookahead' AS check_name, 'error' AS severity,
           count(*) AS violations
    FROM ai_sp500_gold.features_daily f
    JOIN ai_sp500_silver.trading_days d ON d.trade_date = f.trade_date
    WHERE f.feature_asof > d.market_open_utc

    UNION ALL
    -- 2. Labels must never leak into the features table (schema guard)
    SELECT 'gold_labels_separate', 'error',
           count(*)
    FROM information_schema.columns
    WHERE table_schema = 'ai_sp500_gold'
      AND table_name   = 'features_daily'
      AND column_name LIKE 'fwd_%'

    UNION ALL
    -- 3. Feature completeness on recent rows (NULL macro is legitimate early in
    --    history, never in the last 30 days)
    SELECT 'gold_recent_complete', 'error',
           count_if(return_1d IS NULL OR volatility_21d IS NULL OR rsi_14 IS NULL)
    FROM ai_sp500_gold.features_daily
    WHERE trade_date >  date_add('day', -30, (SELECT run_date FROM params))
      AND trade_date >  (SELECT min(trade_date) + INTERVAL '60' DAY
                         FROM ai_sp500_gold.features_daily)

    UNION ALL
    -- 4. Calendar completeness: every trading day in the last 30 has features
    SELECT 'gold_calendar_complete', 'warn',
           count(*)
    FROM ai_sp500_silver.trading_days d
    LEFT JOIN (SELECT DISTINCT trade_date FROM ai_sp500_gold.features_daily) f
           ON f.trade_date = d.trade_date
    WHERE d.trade_date BETWEEN date_add('day', -30, (SELECT run_date FROM params))
                           AND date_add('day', -1,  (SELECT run_date FROM params))
      AND f.trade_date IS NULL

    UNION ALL
    -- 5. RSI bounds
    SELECT 'gold_rsi_bounded', 'error',
           count_if(rsi_14 NOT BETWEEN 0 AND 100)
    FROM ai_sp500_gold.features_daily
)
SELECT p.run_date, 'gold', c.check_name, c.severity, c.violations,
       IF(c.violations > 0, 'fail', 'pass'), current_timestamp
FROM checks c CROSS JOIN params p
