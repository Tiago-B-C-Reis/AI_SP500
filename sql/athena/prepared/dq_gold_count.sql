-- Prepared statement: dq_gold_count — parameter ?1 = run_date.
-- One row, one column: failed error-severity gold checks in the latest batch.
-- Non-zero blocks scoring/publication.

WITH latest AS (
    SELECT max(run_ts) AS ts
    FROM ai_sp500_ops.dq_results
    WHERE layer = 'gold' AND run_date = CAST(? AS date)
)
SELECT CAST(coalesce(
    sum(IF(r.status = 'fail' AND r.severity = 'error', 1, 0)), 0) AS varchar) AS failed
FROM ai_sp500_ops.dq_results r
JOIN latest ON r.run_ts = latest.ts
WHERE r.layer = 'gold'
