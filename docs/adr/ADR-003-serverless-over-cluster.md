# ADR-003 — Athena + Step Functions over Databricks / MWAA / Glue Spark

**Status:** accepted · 2026-08-01

## Context

The proposal called for a "Databricks imitation" and floated Athena, Glue, Lambda or a
micro-Databricks cluster. The dataset is ~1 GB total, ~2 MB/day. The budget target is
single-digit euros per month. The portfolio goal requires the *patterns* (medallion,
ACID tables, orchestrated DAGs, DQ gates), not any particular vendor.

## Decision

- **Transforms:** Athena (engine v3) SQL on Iceberg — serverless, $5/TB scanned,
  10 MB/query minimum.
- **Orchestration:** EventBridge Scheduler + Step Functions (standard workflows, native
  Athena integration) — free tier covers ~5× our monthly volume.
- **Imperative steps only** (scoring, DQ assertion, training) in Lambda.
- **No clusters, no endpoints, nothing hourly-billed.**

## Rationale — the idle-floor test

Any component with an hourly floor costs more idling than the whole stack costs working:

| Rejected | Idle/min floor | Chosen instead |
|---|---|---|
| Micro-Databricks cluster | ~€30–60/mo | Athena + Iceberg |
| MWAA (managed Airflow) | ~€330/mo | Step Functions |
| Glue Spark ETL | 2-DPU minimum per run | Athena SQL |
| Glue crawlers | €0.44/hr + schema drift | DDL in git + partition projection |
| Redshift Serverless | 8-RPU floor when active | Athena |
| SageMaker endpoint | ~€50+/mo always-on | Batch Lambda → `gold.predictions` |

Skill transfer is preserved: Delta→Iceberg, Workflows→Step Functions, Unity→Glue
Catalog are 1:1 pattern mappings (documented in ARCHITECTURE.md §5), and the repo's
README states the mapping explicitly for reviewers.

## Consequences

- (+) Total cloud cost ~€1–2/month with guardrails enforced in config.
- (+) The Step Functions console gives the visual DAG/backfill story interviews ask about.
- (−) No Spark in the daily path. **Superseded in part by
  [ADR-004](ADR-004-spark-for-bulk-backfill.md)**, which restores PySpark on EMR
  Serverless for the bulk historical backfill — the one workload where a
  distributed engine genuinely wins, and still €0 when idle. The rejection of
  Spark *as the daily transform engine* stands.
- (−) Athena has no `QUALIFY`, prepared-statement quirks, and per-query latency of
  seconds — all acceptable at this scale.
