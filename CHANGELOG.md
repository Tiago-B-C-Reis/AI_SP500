# Changelog

All notable changes to **AI_SP500**.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project does not yet publish versioned releases; entries below are grouped
into development phases and dated from the git history.

---

## [Unreleased] — Architecture v0.4 "Hybrid Lakehouse" · 2026-08-01

The project's goals changed: alongside utility under hardware constraints, the repository
is now explicitly a **portfolio piece** demonstrating Medallion architecture, open table
formats, serverless orchestration and MLOps discipline. v0.3's "Postgres is the entire
warehouse" remains correct for a utility-only build and is preserved as the documented
fallback (ADR-001); v0.4 builds the lakehouse for real — on per-request-billed AWS
services, at ~€1–2/month, with the on-prem constraints (0 new resident MB on TrueNAS,
0 bytes to the ZFS pool) unchanged.

### Added
- **`docs/adr/`** — Architecture Decision Records: ADR-001 (a lakehouse for small data —
  and why that is a deliberate, documented trade), ADR-002 (Iceberg over Delta: Athena
  writes/MERGEs only Iceberg), ADR-003 (Athena + Step Functions over Databricks / MWAA /
  Glue Spark — the idle-floor test).
- **`infra/terraform/`** — the whole cloud footprint as code: S3 (versioned, lifecycle to
  Glacier IR, public-access-blocked), four Glue databases, Athena workgroup with an
  **enforced 1 GiB per-query scan cutoff**, least-privilege edge uploader (delete-DENIED
  on raw/), SNS → n8n webhook subscription, €5 budget alarm, EventBridge Scheduler, and
  the daily Step Functions state machine with logging.
- **`infra/stepfunctions/daily_pipeline.asl.json`** — the daily DAG: silver MERGEs →
  DQ gate → gold build → DQ gate (incl. the lookahead assertion) → scoring → alerting.
  Native Athena integration (no Lambda in the transform path); DQ gates read
  `ops.dq_results` and block promotion on any failed error-severity check; idempotent
  for any `run_date`.
- **`sql/athena/`** — the lakehouse as schemas-as-code: bronze external tables with
  **partition projection** (zero crawlers), silver/gold/ops **Iceberg** DDL, prepared
  statements for every MERGE and DQ suite, weekly `OPTIMIZE`/`VACUUM` maintenance.
- **`infra/scripts/athena_apply.sh`** + `infra/Makefile` — applies DDL and prepared
  statements idempotently (`make athena-apply LAKE_BUCKET=…`).
- `ops.ml_runs` schema records the **Iceberg snapshot ID** of gold at training time —
  exact model→data lineage via time travel.

### Changed
- **Warehouse: MP9 Postgres → Apache Iceberg on S3.** The MP9 Postgres demotes to a
  30-day landing buffer (news awaiting sync + edge control tables, ≤1 GB cap); market
  data streams straight to S3 without touching any local database.
- **Transforms: Postgres window functions → Athena (Trino) SQL**, ported from
  `sql/002_silver_to_gold.sql` (which remains in force as the v0.3 fallback).
- **Cloud orchestration: none → EventBridge + Step Functions.** Edge scheduling stays
  systemd; stages are now `ingest-daily`, `ingest-weekly`, `sync-lake`, `prune-landing`
  (gold-build and train moved to the cloud).
- **Data quality: assertions inside a transaction → named DQ gates between layers**,
  each run audited as rows in `ops.dq_results` with severity semantics.
- `README.md` — goals (adds the demonstration goal), status, hardware, architecture
  (v0.1→v0.4 table), layout, roadmap (phases A–I), principles, technology stack.
- `ARCHITECTURE.md` — rewritten as v0.4: verdict on the proposed 4-stage design,
  Databricks→open-serverless mapping, cost model with the cost-traps table, medallion
  spec, orchestration, the enterprise-patterns index, security.

### Unchanged (carried forward deliberately)
- All eleven catalogued code defects and their fixes; the ingestion-budget cuts
  (~44,968 → ~2,500 calls/week); TrueNAS memory reclamation (`deploy/truenas/TUNING.md`);
  local Ollama with pinned model + prompt hash; point-in-time rules; the
  naive-baseline-first evaluation ethic.

### Added — Spark (follow-up to the initial v0.4 entry)
- **`jobs/spark/backfill_prices.py`** — PySpark bulk backfill: reads the full `raw/`
  archive (tens of thousands of small nested-JSON files), flattens Alpha Vantage's
  date-keyed map with one `explode`, deduplicates via a window function, and
  `MERGE`s into Iceberg `silver.prices_daily` **from Spark** through the same Glue
  catalog Athena uses. Calls `rewrite_data_files` to compact its own output.
- **`infra/terraform/spark.tf`** — EMR Serverless application with **no
  pre-initialised capacity** (so idle cost stays at zero), a capacity ceiling, 5-minute
  auto-stop, and a least-privilege job role scoped to the lake bucket and Glue commits.
- **`docs/adr/ADR-004-spark-for-bulk-backfill.md`** — records the split: bulk historical
  load on Spark, incremental merge on SQL. Partially supersedes ADR-003, whose rejection
  of Spark *as the daily transform engine* stands.
- **ARCHITECTURE.md §5b** — "Where the lake, the catalog and Spark actually are":
  states explicitly that S3 `raw/` + `bronze/` **is** the data lake (lakehouse = lake +
  table format + catalog + engine), maps Unity Catalog → Glue Data Catalog with an
  honest capability gap table (row/column ACLs would need Lake Formation), and explains
  the Spark scoping.

### Notes
- Terraform, ASL and Athena SQL are **written and structurally validated but not yet
  applied against a live AWS account** — no AWS access from the authoring environment.
  The ASL passed a referential-integrity check (19 states, no dangling targets); the SQL
  follows Athena engine v3 syntax but must be smoke-tested on first `make athena-apply`.
- The `ai-sp500-score` Lambda referenced by the state machine is Phase H; deploy a stub
  (or remove the state) until then.
- `backfill_prices.py` compiles and its structure was checked, but it has **not been run
  against real data or a live Spark**. The Iceberg runtime JAR in the run command must
  match the EMR release (`emr-7.1.0` ships Spark 3.5 → `iceberg-spark-runtime-3.5_2.12`).

---

## [Unreleased] — Architecture v0.3 "Lite" · 2026-08-01

A hardware audit showed v0.2 was not deployable. The TrueNAS node's 16 GB DDR3 is fully
committed to the existing homelab, and the ZFS pool sits at 81% — past the threshold where
OpenZFS switches its block allocator and write performance degrades. Airflow, MLflow and
DuckDB would have required ~4–8 GB of resident memory that does not exist.

The redesign removes a tier rather than shrinking one.

### Added
- **`deploy/`** — full infrastructure configuration.
  - `deploy/mp9/docker-compose.yml` — analytics Postgres (3 GB cap) plus a `migrated`
    profile for three stateless UIs moved off the TrueNAS.
  - `deploy/mp9/postgresql.lite.conf` — tuned for 16 GB and analytical queries; low global
    `work_mem` with a per-session override in the Gold transform.
  - `deploy/mp9/systemd/` — four timer/service pairs plus a templated `sp500-alert@`
    failure handler. Every unit carries a `MemoryMax=` cgroup ceiling, `Nice=10` and
    `IOSchedulingClass=idle`.
  - `deploy/truenas/TUNING.md` — ZFS ARC and MongoDB WiredTiger cache caps, pool health
    triage, dataset properties for database workloads.
  - `deploy/README.md` — deployment and operations guide.
- **`sql/001_schema.sql`** — `platform` / `silver` / `gold` / `ml` schemas, plus
  `v_feed_health` and `v_staleness` views that replace what the Airflow UI would have shown.
- **`sql/002_silver_to_gold.sql`** — technical indicators and features computed in
  PostgreSQL window functions. Replaces both the DuckDB layer and the 51 Alpha Vantage
  technical-indicator endpoints. Includes the lookahead assertion as a hard failure.

### Changed
- **Orchestration: Airflow → systemd timers + n8n.** Zero resident memory; `Persistent=true`
  survives reboots; `OnFailure=` posts to an n8n webhook; `MemoryMax=` is a real kernel
  ceiling rather than an advisory pool slot.
- **Processing: DuckDB + Parquet lakehouse → PostgreSQL alone.** At ~3.5 M rows fully
  backfilled and ~2 MB/day incremental, Postgres window functions complete in seconds. The
  Parquet tier is deleted, not relocated — which also removes every pipeline write from the
  81% ZFS pool.
- **Warehouse: TrueNAS Postgres → dedicated Postgres on the HP MP9 G2.** All analytical
  load leaves the constrained node.
- **Experiment tracking: MLflow → `ml.experiment_run` table.**
- **LLM enrichment: OpenRouter/Gemini → local Ollama on the RTX 3060.** Zero API cost, no
  rate limits, full reproducibility. Must be switched *before* backfilling — changing model
  mid-series creates a discontinuity a model will read as a genuine market signal.
- **Training: EC2 GPU burst → MP9 CPU.** Tree models on 2.6 M rows train in seconds.
- `README.md` — added a Hardware section; architecture, roadmap, layout, design principles
  and technology stack updated to v0.3.
- `ARCHITECTURE.md` — rewritten as v0.3. Point-in-time correctness, the ingestion budget,
  the n8n integration requirements and the rejection of Spark/Delta/Unity/Aurora all carry
  over from v0.2 unchanged.

### Deprecated
- `AI_SP500_Airflow/` — superseded by `deploy/mp9/systemd/`. It never held a DAG.

### Notes
- The SQL has **not** been executed against a live PostgreSQL — no daemon was available in
  the authoring environment. It was reviewed instead, which caught one genuine defect: the
  labels query nested a window function inside another window function's arguments, which
  PostgreSQL rejects. Fixed by materialising the daily return in a CTE first.
- `pipeline/` does not exist yet. The systemd units reference the entry point specified in
  ARCHITECTURE.md Phase E; install them once that module lands.

---

## [Unreleased] — Documentation & architecture reset · 2026-08-01

The project had been dormant since 2026-01-31. This entry records the work done to
re-establish an accurate picture of the codebase before resuming development.

### Added
- `ARCHITECTURE.md` — architecture **v0.2**, replacing `InfaArquitecture_V0.1.png`.
  Consolidates the AWS S3 Python ingestion and the TrueNAS n8n/Postgres stack into a
  single design; drops Spark, Delta Lake, Unity Catalog, Amazon Aurora and always-on EC2
  in favour of DuckDB, Hive-partitioned Parquet, and the existing TrueNAS PostgreSQL.
- `CHANGELOG.md` — this file.

### Changed
- `README.md` — full rewrite. The previous version described components that do not
  exist and paths that were renamed. Now documents actual state, with an explicit
  separation between what works, what is scaffolded, and what has never run.

### Fixed (documentation)
- Corrected stale paths: `DataIngestion_&_BronzeLayer/getRequester.py` →
  `DataIngestion/getRequesterWeekly.py`; `create_table.sql` →
  `Logs_OLTP/ddl_queries.sql`.
- Removed the claim that `ingestion_dag.py` exists in `AI_SP500_Airflow/dags/`.
  That directory has never contained a DAG.

### Known issues catalogued
Eleven defects identified by reading and compiling the codebase — see
[README § Known Issues](README.md#known-issues). The two that block operation:

1. `getRequesterDailyAI.py:31` raises `AttributeError` before its `try` block
   (`datetime.date.today()` under a `from datetime import datetime` import).
   **The daily news ingestion has never completed a run.**
2. `s3_upload_message` is referenced before assignment in all three `except`
   handlers, raising `NameError` and masking the original error whenever an
   HTTP request fails.

---

## Phase 3 — Alpha Intelligence & containerisation · 2025-12-23 → 2026-01-31

### Added
- `getRequesterDailyAI.py` — daily ingestion of `NEWS_SENTIMENT` and
  `TOP_GAINERS_LOSERS`. *(Never successfully executed — see Known Issues.)*
- `getRequesterWeeklyAI.py` — `EARNINGS_CALL_TRANSCRIPT`, `INSIDER_TRANSACTIONS`
  and `ANALYTICS_FIXED_WINDOW`, with quarter-level checkpointing via
  `Data/year_quarter_List.json` so completed quarters are not re-fetched.
- `DataIngestion/Dockerfile` — Poetry-based image on `python:3.13-slim`.
  Published as `tiagobcr/sp500-data-ingestion_{arm64,amd64}`.
- `DataIngestion/docker-compose.yaml` — three ingestion services sharing a YAML
  anchor, plus a `postgres-logging` container with a healthcheck.
- `Data/alpha_intelligence.json` and `Data/alpha_intelligence_daily.json` —
  endpoint registries for the Intelligence APIs.
- `AWS_EC2.py` / `AWS_EC2.yaml` — EC2 provisioning notes.
  *(`AWS_EC2.py` is a console paste and does not compile.)*
- `AI_SP500_Airflow/` — Airflow scaffold: `docker-compose.yaml`, `airflow.cfg`.
  `dags/` left empty.

### Changed
- S3 destination path scheme refined to
  `raw/<category>/<function>/<ISO_year_week>/<function>_<symbol>_<timestamp>.json`,
  making the archive partition-friendly for later Parquet conversion.
- Ingestion split from a single script into daily and weekly cadences.

*Commits: `fc63db7`, `b7f55c1`, `efc5702`, `950a297`, `e9fbfb2`, `5c0725a`, `b7ef821`, `30b8164`*

---

## Phase 2 — Ingestion layer & observability · 2025-11-20 → 2025-12-05

The project restarted here after ten months dormant (`92abe3a restart`).

### Added
- `getRequesterWeekly.py` — the core ingestion loop: 511 S&P 500 tickers ×
  88 Alpha Vantage functions across five categories (Core Stock, Fundamentals,
  Commodities, Economic Indicators, Technical Indicators).
- `Helper_Functions/ingestion.py` — HTTP fetch with API-key injection, rate-limit
  sleep, and S3 upload orchestration with environment-variable validation.
- `Helper_Functions/aws_S3.py` — `boto3` helpers: `upload_to_s3` (DataFrame → CSV),
  `upload_json_to_s3` (dict → JSON), `read_from_s3` (most-recent-object fetch).
- `Helper_Functions/logger.py` — `log_to_postgres()`, writing one row per ingestion
  attempt with function, symbol, S3 path, byte size and status message.
- `Logs_OLTP/ddl_queries.sql` — `s3_ingestion_logger` table definition.
- `Data/alpha_vantage_urls.json` — declarative registry of 88 endpoints, making
  new sources a configuration change rather than a code change.
- `Data/sp500_tickers.csv` — 511 constituents with sector, sub-industry, CIK,
  headquarters and date added.
- `API_GeneralListCollector.py` — builds the ticker list from API Ninjas and the
  Alpha Vantage listing-status endpoint.
- `.env`-based secret management via `python-dotenv`, git-ignored.
- `InfaArquitecture_V0.1.png` and `SP500_ProjectDescription.md` — first
  architecture and scope documentation.

### Security
- No `.env` file or credential has ever been committed to git — verified across
  full history.

*Commits: `92abe3a`, `aacd814`, `56cfc70`, `1791ab4`, `112f121`, `8808b2b`, `b7d134f`, `fd47bc7`*

---

## Phase 1 — Early exploration · 2024-09-13 → 2025-01-03

### Added
- Initial repository, GPL-3.0 license, Poetry project definition.
- `data_yfinance.py` — Yahoo Finance intraday history probe.
- `SP500_Companies_Colector.py` — BeautifulSoup scraper for the S&P 500
  constituent list, uploading to S3.
- `Silver_Layer/SP500_CompaniesList.py` — PySpark reader for CSVs in S3 via `s3a://`.
  *(Now stale: hardcoded absolute path, mismatched env-var names.)*
- `AI_SP500_Source/` — historical macro CSVs downloaded from FRED and the World Bank:
  GDP (1960–2023), CPI (two series, 1955–2024), PPI all commodities (1913–2024),
  unemployment level and rate (1948–2024), interest rates, S&P 500 price history.
- Airflow added to the project structure for the first time.

*Commits: `0e344e9`, `011e521`, `7b29399`, `5125455`, `b236069`, `134a185`, `b949355`*

---

## Component status at a glance

| Component | First appeared | Status today |
|---|---|---|
| Alpha Vantage weekly ingestion | Phase 2 | Working |
| S3 Bronze landing | Phase 2 | Working |
| Postgres ingestion logging | Phase 2 | Working |
| Endpoint/ticker registry | Phase 2 | Working |
| Docker packaging | Phase 3 | Working |
| Weekly Intelligence ingestion | Phase 3 | Partially working — one endpoint unreachable |
| Daily news ingestion | Phase 3 | **Broken — has never run** |
| Airflow DAGs | Phase 1 (scaffold) | **Empty** |
| Bronze → Silver processing | — | Not started |
| Gold / feature store | — | Not started |
| ML models | — | Not started |
| Serving / dashboards | — | Not started |

---

## External components (not in this repository)

### n8n `News_MultiAgent` workflow — TrueNAS Scale, running daily

A four-branch multi-agent pipeline covering **Financial/Macro**, **Geopolitical**,
**Technology** and **Portugal Local News**. Per branch:

`Google Sheets (RSS registry)` → `RSS Read` → filter → `Remove Duplicates`
→ `Basic LLM Chain` → JS transform → **Bronze ingestion (Postgres)**
→ `Research Agent` (memory + tools, incl. `get_current_date`) → JSON parser
→ **Silver ingestion (Postgres)** → sentiment analysis & formatting → Gmail digest.

Models: OpenRouter Chat Model and Google Gemini.

Adopted as a **primary data feed** in architecture v0.2. Integration work — numeric
sentiment scores, `published_at`/`ingested_at` separation, ticker/entity extraction,
and writing to the shared `platform.ingestion_log` — is tracked in
[ARCHITECTURE.md § Next Steps](ARCHITECTURE.md#12-roadmap).
