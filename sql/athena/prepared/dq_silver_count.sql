-- Prepared statement: dq_silver_count — parameter ?1 = run_date.
-- Returns ONE row, ONE column: the number of failed error-severity checks in
-- the latest silver batch. The state machine reads it via GetQueryResults and
-- a Choice state blocks promotion to gold unless it is exactly '0'.

WITH latest AS (
    SELECT max(run_ts) AS ts
    FROM ai_sp500_ops.dq_results
    WHERE layer = 'silver' AND run_date = CAST(? AS date)
)
SELECT CAST(coalesce(
    sum(IF(r.status = 'fail' AND r.severity = 'error', 1, 0)), 0) AS varchar) AS failed
FROM ai_sp500_ops.dq_results r
JOIN latest ON r.run_ts = latest.ts
WHERE r.layer = 'silver'
