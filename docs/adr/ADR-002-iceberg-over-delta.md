# ADR-002 — Apache Iceberg over Delta Lake

**Status:** accepted · 2026-08-01

## Context

The lakehouse needs an open table format providing ACID upserts (`MERGE`), schema
evolution and time travel on S3. The two serious candidates are Delta Lake and Apache
Iceberg. The transform engine is Athena (engine v3, Trino-based), chosen in ADR-003.

## Decision

Apache Iceberg for all silver, gold and ops tables.

## Rationale

1. **Engine capability is the deciding fact:** Athena can *read* Delta tables but can
   only *write, `MERGE INTO`, `OPTIMIZE` and `VACUUM`* Iceberg. With Athena as the only
   transform engine, Delta would require adding Spark (Glue ETL) purely to write —
   reintroducing the JVM cost and complexity this architecture exists to avoid.
2. Iceberg is the vendor-neutral signal (Netflix/Apple/AWS lineage; native support in
   Athena, Trino, Snowflake, BigQuery, DuckDB), whereas Delta's center of gravity is
   Databricks.
3. Feature parity for our needs is complete: hidden partitioning (`month(trade_date)`),
   snapshot time travel (used for model–data lineage in `ops.ml_runs`), and
   metadata-level schema evolution.

## Consequences

- (+) Single-engine architecture; all DML stays in Athena SQL.
- (+) Snapshot IDs give exact, cheap training-data lineage.
- (−) Delta-specific tooling (e.g. Databricks UniForm demos) is out of scope.
- (−) Iceberg tables need scheduled `OPTIMIZE`/`VACUUM`; handled by the weekly
  maintenance state machine — and demonstrating table maintenance is itself a skill.
