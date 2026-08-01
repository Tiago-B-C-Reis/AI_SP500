-- Prepared statement: dq_silver_record — parameter ?1 = run_date (used once;
-- the params CTE fans it out so EXECUTE ... USING takes exactly one value).
-- Runs every silver check as one INSERT so the audit trail (ops.dq_results)
-- always shows the full suite for the batch, pass or fail.
-- severity='error' gates promotion to gold; 'warn' is recorded only.

INSERT INTO ai_sp500_ops.dq_results
    (run_date, layer, check_name, severity, violations, status, run_ts)
WITH params AS (
    SELECT CAST(? AS date) AS run_date
),
checks AS (
    -- 1. Primary-key integrity (MERGE should make this impossible — verify anyway)
    SELECT 'prices_pk_unique' AS check_name, 'error' AS severity,
           count(*) - count(DISTINCT symbol || cast(trade_date AS varchar)) AS violations
    FROM ai_sp500_silver.prices_daily

    UNION ALL
    -- 2. Price sanity
    SELECT 'prices_positive', 'error',
           count_if(adj_close IS NULL OR adj_close <= 0)
    FROM ai_sp500_silver.prices_daily

    UNION ALL
    -- 3. Freshness: newest bar within 5 calendar days of run_date (weekend-safe)
    SELECT 'prices_fresh', 'error',
           IF(max(trade_date) < date_add('day', -5, (SELECT run_date FROM params)), 1, 0)
    FROM ai_sp500_silver.prices_daily

    UNION ALL
    -- 4. Sentiment bounds (re-verify what the edge schema already promised)
    SELECT 'news_sentiment_bounded', 'error',
           count_if(sentiment_score NOT BETWEEN -1 AND 1
                    OR relevance_sp500 NOT BETWEEN 0 AND 1)
    FROM ai_sp500_silver.news

    UNION ALL
    -- 5. Dual-timestamp invariant: nothing may be ingested before it was
    --    published, beyond a clock-skew allowance
    SELECT 'news_timestamps_ordered', 'error',
           count_if(ingested_at < published_at - INTERVAL '1' HOUR)
    FROM ai_sp500_silver.news

    UNION ALL
    -- 6. Model provenance present on every scored row
    SELECT 'news_provenance', 'error',
           count_if(llm_model IS NULL OR prompt_hash IS NULL)
    FROM ai_sp500_silver.news

    UNION ALL
    -- 7. Volume plausibility (warn-only: quiet news days are legitimate)
    SELECT 'news_daily_volume', 'warn',
           IF(count_if(CAST(ingested_at AS date) = (SELECT run_date FROM params)) = 0, 1, 0)
    FROM ai_sp500_silver.news
)
SELECT p.run_date, 'silver', c.check_name, c.severity, c.violations,
       IF(c.violations > 0, 'fail', 'pass'), current_timestamp
FROM checks c CROSS JOIN params p
