# ADR-004 — PySpark on EMR Serverless for bulk backfill only

**Status:** accepted · 2026-08-01
**Refines:** [ADR-003](ADR-003-serverless-over-cluster.md), which rejected Spark wholesale

## Context

ADR-003 removed Spark on the idle-floor test: a cluster costs more sitting still
than this pipeline costs running. That reasoning holds for the **daily increment**
(~2 MB), which stays in Athena SQL.

Two facts reopened the question:

1. **A workload genuinely shaped for Spark exists.** The historical backfill reads
   the entire `raw/` archive — tens of thousands of small gzipped JSON objects
   whose time series is a *dynamic map keyed by date*. Athena's JSON SerDe needs a
   static column per key and degrades badly on many-small-files reads. Spark
   flattens the map with one `explode` and parallelises the read.
2. **The portfolio goal (ADR-001) makes the omission expensive.** Spark/PySpark is
   the most frequently listed skill in data-engineering postings. "I used a
   distributed SQL engine" is true of Athena/Trino but does not survive a keyword
   filter or the question "have you written PySpark?"

Rejecting Spark for the daily path was right. Rejecting it *everywhere* left a real
gap for no architectural gain.

## Decision

One PySpark job — [`jobs/spark/backfill_prices.py`](../../jobs/spark/backfill_prices.py)
— on **EMR Serverless**, run on demand for the initial load and after any parsing
change. The daily incremental path is unchanged and remains Athena SQL.

The split is a genuine architectural pattern, not a pretext: **bulk historical load
on Spark, incremental merge on SQL.** It is what production systems actually do,
and it means each engine is used where it wins.

## Why EMR Serverless

| Option | Idle cost | Per run (~5 min) | Notes |
|---|---|---|---|
| **EMR Serverless** ✅ | **€0** (no pre-initialised capacity) | a few cents | Vanilla OSS Spark — the job file runs unmodified locally, on Databricks, anywhere |
| AWS Glue Spark | €0 | ~2× EMR (2-DPU floor) | Simpler setup; Glue's forked runtime, less portable code |
| Databricks Free Edition | €0 | €0 | Sandbox: good for notebook literacy, cannot be an automation target |
| Local PySpark on the MP9 | €0 | €0 | Violates the "no JVM on owned hardware" constraint; kept only as a `--dry-run` escape hatch |

EMR Serverless preserves the property that makes v0.4 affordable — **nothing is
billed while nothing is running** — while giving portable, real Spark.

Glue remains a one-resource swap if setup friction outweighs the per-run saving.

## Consequences

- (+) Closes the Spark gap with a job that is genuinely better as Spark, so the
  repo never has to claim Spark was necessary when it was not.
- (+) Demonstrates the DataFrame API, window-function dedupe, `MERGE INTO` on
  Iceberg *from Spark*, and `rewrite_data_files` compaction — through the same
  Glue catalog Athena uses, so both engines write one table with one schema.
- (+) Still €0 idle; the v0.4 cost model is unchanged in steady state.
- (−) A second execution engine to keep working: Iceberg runtime JAR versions must
  track the Spark version, and Spark's MERGE semantics must be kept aligned with
  the Athena prepared statement. Both are pinned and commented.
- (−) Spark's writes need compaction; the job calls `rewrite_data_files` itself
  rather than leaving it to the weekly maintenance machine.
