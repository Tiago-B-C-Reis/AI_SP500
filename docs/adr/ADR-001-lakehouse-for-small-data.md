# ADR-001 — A cloud lakehouse for 2 MB/day

**Status:** accepted · 2026-08-01
**Supersedes:** the v0.3 decision "Postgres is the entire warehouse"

## Context

The dataset is ~3.5 M rows fully backfilled (~1 GB), growing ~2 MB/day. Architecture v0.3
correctly concluded that this fits a single PostgreSQL instance and that a lakehouse tier
would be over-engineering **for a pure-utility build**. That analysis stands.

The project's requirements changed: alongside utility, the repository is now explicitly a
**portfolio piece** demonstrating Medallion architecture, open table formats, serverless
orchestration and MLOps practice. A Postgres schema — however correct — does not
demonstrate those skills.

## Decision

Build the Medallion lakehouse on serverless, per-request-billed services only
(S3 + Iceberg + Glue Catalog + Athena + Step Functions + Lambda), with a hard cost
ceiling of ~€2/month enforced by workgroup scan cutoffs, lifecycle rules and a budget
alarm. Keep the edge (ingestion, buffering) on owned hardware. Preserve v0.3's
Postgres-only design in this record as the documented fallback for a utility-only fork.

## Consequences

- (+) Every enterprise pattern the portfolio must show — MERGE-based idempotency,
  time travel, DQ gates, snapshot-pinned ML lineage, IaC — becomes executable, not
  hypothetical.
- (+) Cost stays within a homelab budget; nothing in the cloud is always-on.
- (−) Two control planes (edge systemd + cloud Step Functions) instead of one.
- (−) Athena round-trips are slower than local Postgres for interactive work; mitigated
  by result reuse and the Streamlit cache.
- (±) The repo must state openly that the volume does not require this architecture.
  That admission is the point: knowing the difference is the senior skill on display.
