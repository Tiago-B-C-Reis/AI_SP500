# AI_SP500 — A Personal Data Platform for S&P 500 Research

**AI_SP500** collects economic, financial and geopolitical data that influence the S&P 500, refines it through a Bronze → Silver → Gold lakehouse, and serves it as a feature store for predictive modelling.

It is a personal research platform, deliberately built to run at near-zero marginal cost on **hardware that is already switched on 24/7** — a TrueNAS Scale home server — using AWS only where the cloud genuinely earns its keep (durable off-site raw archive, and burst compute on demand).

> **Status: active — rebuilding on the v0.4 "Hybrid Lakehouse" architecture.**
> The ingestion layer is the only production component today; everything downstream is being
> rebuilt as a capped on-prem edge feeding a serverless AWS lakehouse (S3 + Iceberg + Athena +
> Step Functions, ~€1–2/mo). See [Hardware](#hardware), [Current State](#current-state), and
> [Known Issues](#known-issues) for what is currently broken.

---

## Table of Contents

- [Goals](#goals)
- [Current State](#current-state)
- [Hardware](#hardware)
- [Architecture](#architecture)
- [Repository Layout](#repository-layout)
- [Data Sources](#data-sources)
- [Setup](#setup)
- [Running the Ingestion Layer](#running-the-ingestion-layer)
- [Known Issues](#known-issues)
- [Roadmap](#roadmap)
- [Design Principles](#design-principles)

---

## Goals

1. **Aggregate** high-quality global economic, financial and geopolitical data into one governed store.
2. **Refine** it into a point-in-time-correct daily feature table suitable for supervised learning.
3. **Model** S&P 500 index behaviour — direction, volatility, and market regime — with honest, backtested evaluation.
4. **Serve** insights through lightweight dashboards and alerting.
5. **Demonstrate** — as a first-class goal since v0.4 — production-grade Data Engineering and MLOps practice: Medallion architecture on an open table format, serverless orchestration with DQ gates, snapshot-pinned model lineage, IaC, and decision records. The repo is a portfolio piece as much as a platform.

Explicit non-goals: beating professional quant funds, running an enterprise-scale platform, or paying for always-on or hourly-billed cloud compute.

---

## Current State

### What actually works today

| Component | Status | Detail |
|---|---|---|
| **Alpha Vantage ingestion (weekly)** | Working | `DataIngestion/getRequesterWeekly.py` iterates 511 S&P 500 tickers × 88 API functions, writes raw JSON to S3 `raw/<category>/<function>/<YYYY_Www>/` and logs each attempt to Postgres. |
| **S3 Bronze landing** | Working | `Helper_Functions/aws_S3.py` uploads JSON/CSV via `boto3`. Path scheme is category- and ISO-week-partitioned. |
| **Postgres ingestion logging** | Working | Every attempt (success or failure) is inserted into `s3_ingestion_logger`. Schema in `DataIngestion/Logs_OLTP/ddl_queries.sql`. |
| **Containerisation** | Working | `DataIngestion/Dockerfile` (Poetry-based) plus a 3-service `docker-compose.yaml`. Images published as `tiagobcr/sp500-data-ingestion_{arm64,amd64}`. |
| **Ticker & endpoint registry** | Working | Endpoints are declarative JSON (`Data/alpha_vantage_urls.json`, `alpha_intelligence*.json`); tickers come from `Data/sp500_tickers.csv`. Adding a source is a config edit, not a code change. |
| **n8n news pipeline** *(external)* | Working | Runs on TrueNAS, independent of this repo. Daily multi-agent workflow across 4 topics → Bronze + Silver tables in the TrueNAS Postgres → email digest. Not yet integrated with this platform's schema. |

### What is scaffolded but not working

| Component | Status | Detail |
|---|---|---|
| **Daily news ingestion** | **Broken** | `getRequesterDailyAI.py` raises `AttributeError` on the first loop iteration, before its `try` block. It has never completed a run. See [Known Issues](#known-issues). |
| **Weekly AI/intelligence ingestion** | **Partially broken** | `getRequesterWeeklyAI.py` has an unreachable branch — `ANALYTICS_FIXED_WINDOW` is never fetched. |
| **Airflow** | **Empty scaffold** | `AI_SP500_Airflow/` has `docker-compose.yaml` and `airflow.cfg`, but `dags/` is empty. No DAG has ever been written. |
| **Bronze layer processing** | **Empty** | `BronzeLayer/` is an empty directory. Raw JSON lands in S3 and is never read back. |
| **Silver layer** | **Empty** | `Silver_Layer/` holds one exploratory PySpark script with a hardcoded path to a directory that no longer exists. |
| **Gold layer / feature store** | **Not started** | — |
| **ML models** | **Not started** | — |
| **Serving / dashboards** | **Not started** | — |
| **EC2 provisioning** | **Not valid code** | `AWS_EC2.py` is a pasted AWS console snippet, not runnable Python. |

### The honest summary

Raw data flows into S3 and is logged. **Nothing reads it back.** The project's centre of gravity for the next phase is the read path: S3 → typed Parquet → features → model.

---

## Hardware

The platform runs on two always-on machines plus a serverless cloud footprint. The nodes' asymmetry — and the ZFS pool at 81% — drives the whole design.

| Where | Spec | Role (v0.4) |
|---|---|---|
| **TrueNAS Scale** | i7-6700 (4C/8T) · **16 GB DDR3** · RTX 3060 12 GB · ZFS pool **81% used** | n8n + Ollama (LLM enrichment) only. **The pipeline adds 0 resident MB and 0 pool bytes** |
| **HP MP9 G2** | Ubuntu Server · **16 GB, largely idle** · 128 GB SSD | Edge node: capped ingest/sync jobs, 30-day landing Postgres buffer (≤1 GB), optional Streamlit |
| **AWS** | serverless only | The lakehouse: S3 + Iceberg + Glue + Athena + Step Functions + Lambda. Nothing hourly-billed |
| **MacBook Air M1** | 8 GB | Development and ad-hoc analysis. Nothing scheduled |

Two constraints shape every decision below. The TrueNAS has **no spare RAM** — 16 GB already
carries Jellyfin, Immich, Ollama, n8n, MongoDB, Postgres, three Django workers and ZFS ARC.
And the pool sits at **81%**, past the point where OpenZFS switches its block allocator and
write performance begins to degrade.

The MP9 has as much RAM as the node that is drowning, and almost nothing running on it — it
became the edge node. The warehouse itself moved off-prem entirely in v0.4, so neither node
carries analytical load. Memory reclamation on the TrueNAS is covered in
[deploy/truenas/TUNING.md](deploy/truenas/TUNING.md).

---

## Architecture

Four revisions. **v0.4 "Hybrid Lakehouse" is the current target**, documented in
**[ARCHITECTURE.md](ARCHITECTURE.md)** with decision records in **[docs/adr/](docs/adr/)**.

The evolution, honestly told: v0.1 was an enterprise stack (Spark, Delta, Unity Catalog,
Aurora) for a 2 MB/day workload. v0.2 fixed the tooling but assumed TrueNAS RAM that does not
exist. v0.3 went minimal — Postgres as the entire warehouse on the idle HP MP9 — and that
remains the documented fallback for a utility-only build
([ADR-001](docs/adr/ADR-001-lakehouse-for-small-data.md)). **v0.4 adds the goal v0.3 could
not serve: demonstrating lakehouse and MLOps practice.** The Medallion architecture is built
for real — on serverless, per-request-billed AWS services, so the cost stays at ~€1–2/month
and the on-prem constraints stay inviolate.

| Concern | v0.1 | v0.2 | v0.3 Lite | **v0.4 Hybrid Lakehouse** |
|---|---|---|---|---|
| Warehouse | Aurora | TrueNAS Postgres | MP9 Postgres | **Apache Iceberg on S3** |
| Transform engine | Spark on EC2 | DuckDB | Postgres SQL | **Athena (Trino) SQL** — daily |
| Bulk processing | Spark on EC2 (always-on) | — | — | **PySpark on EMR Serverless** — backfill only, €0 idle |
| Catalog | Unity Catalog | — | — | **Glue Data Catalog** (no crawlers — schemas are code; Lake Formation if row/column ACLs are ever wanted) |
| Data lake | S3 | S3 | S3 | **S3 `raw/` + `bronze/`** — still the system of record beneath the Iceberg tables |
| Orchestration | Airflow on EC2 | Airflow on TrueNAS | systemd + n8n | **EventBridge + Step Functions** (edge: systemd) |
| Data quality | — | — | assertions in SQL | **DQ gates that block promotion**, audited in `ops.dq_results` |
| Experiment tracking | — | MLflow | Postgres table | **`ops.ml_runs` + Iceberg snapshot lineage** |
| LLM enrichment | Cloud | Cloud | Local Ollama | Local Ollama (RTX 3060) |
| Training | EC2 GPU | EC2 GPU burst | MP9 CPU | **Lambda batch** (SageMaker job optional) |
| IaC / ADRs / CI | — | — | — | **Terraform · docs/adr · Actions** |
| New RAM on TrueNAS | n/a | 4–8 GB ✗ | 0 | **0** |
| New ZFS writes | n/a | growing ✗ | 0 | **0** |
| Monthly cloud cost | ~€150 | ~€0.50 | ~€0.50 | **~€1–2** |

The guiding rule: *the edge is capped and buffered; the lakehouse is serverless and
per-request; nothing anywhere is hourly-billed.*

Infrastructure lives in **[infra/](infra/)** (Terraform, Step Functions, apply scripts),
lakehouse SQL in **[sql/athena/](sql/athena/)**, edge deployment in **[deploy/](deploy/)**.

---

## Repository Layout

```
AI_SP500/
├── DataIngestion/                  # ← the only production component
│   ├── getRequesterWeekly.py       # Alpha Vantage: 511 tickers × 88 functions → S3
│   ├── getRequesterWeeklyAI.py     # Earnings transcripts, insider transactions
│   ├── getRequesterDailyAI.py      # News sentiment, top gainers/losers  [BROKEN]
│   ├── API_GeneralListCollector.py # Builds sp500_tickers.csv from API Ninjas
│   ├── SP500_Companies_Colector.py # Yahoo Finance scraper (BeautifulSoup)
│   ├── Helper_Functions/
│   │   ├── ingestion.py            # HTTP fetch + S3 upload orchestration
│   │   ├── aws_S3.py               # boto3 put/get helpers
│   │   └── logger.py               # Postgres ingestion logging
│   ├── Data/                       # Declarative endpoint registry + ticker list
│   ├── Logs_OLTP/ddl_queries.sql   # s3_ingestion_logger schema
│   ├── Dockerfile
│   └── docker-compose.yaml
├── infra/                          # ← v0.4 cloud lakehouse (IaC)
│   ├── terraform/                  # S3, Glue, Athena workgroup, IAM, SNS, scheduler, SFN, EMR Serverless
│   ├── stepfunctions/              # daily_pipeline.asl.json — the DAG with DQ gates
│   ├── scripts/athena_apply.sh     # Schemas-as-code deployment (no crawlers)
│   └── Makefile
├── sql/
│   ├── athena/                     # ← the lakehouse: DDL + prepared statements
│   │   ├── 10_bronze_ddl.sql       # External tables, partition projection
│   │   ├── 20_silver_ddl.sql       # Iceberg (typed, MERGE targets)
│   │   ├── 30_gold_ddl.sql         # features / labels / predictions / ops
│   │   ├── 50_maintenance.sql      # OPTIMIZE + VACUUM
│   │   └── prepared/               # One file per prepared statement (MERGEs, DQ)
│   ├── 001_schema.sql              # Landing Postgres (apply platform + silver.news only)
│   └── 002_silver_to_gold.sql      # v0.3 Postgres transform — retained as fallback
├── jobs/spark/                     # PySpark — bulk backfill (EMR Serverless)
│   └── backfill_prices.py          # raw/ JSON → Iceberg silver via Spark MERGE
├── docs/adr/                       # Architecture Decision Records (4)
├── deploy/                         # On-prem edge
│   ├── README.md                   # Deployment guide
│   ├── mp9/                        # Edge node: landing Postgres + systemd timers
│   └── truenas/TUNING.md           # ARC + WiredTiger caps, pool health
├── AI_SP500_Airflow/               # Airflow scaffold — SUPERSEDED by systemd timers
├── BronzeLayer/                    # EMPTY
├── Silver_Layer/                   # One exploratory PySpark script
├── AI_SP500_Source/                # Historical CSVs (FRED macro, 1913–2024)
├── ARCHITECTURE.md                 # ← v0.4 "Hybrid Lakehouse" design
├── CHANGELOG.md
├── InfaArquitecture_V0.1.png       # Original (superseded) diagram
└── pyproject.toml                  # Poetry
```

---

## Data Sources

| Source | Access | Cadence | Coverage | Lands in |
|---|---|---|---|---|
| **Alpha Vantage — Core Stock** | REST | Weekly | Weekly/monthly adjusted prices, quotes, market status | S3 `raw/Core_Stock_APIs/` |
| **Alpha Vantage — Fundamentals** | REST | Weekly | Income statement, balance sheet, cash flow, earnings, dividends, splits, IPO calendar | S3 `raw/Fundamental_Data/` |
| **Alpha Vantage — Economic** | REST | Weekly | Real GDP, CPI, inflation, treasury yields, fed funds, unemployment, nonfarm payroll, retail sales | S3 `raw/Economic_Indicators/` |
| **Alpha Vantage — Commodities** | REST | Weekly | WTI, Brent, natural gas, copper, aluminium, wheat, corn, cotton, sugar, coffee | S3 `raw/Commodities/` |
| **Alpha Vantage — Technicals** | REST | Weekly | ~51 indicators (SMA, EMA, RSI, MACD, BBANDS, ATR, …) | S3 `raw/Technical_Indicators/` |
| **Alpha Vantage — Intelligence** | REST | Daily/Weekly | News sentiment, top gainers/losers, insider transactions, earnings call transcripts | S3 `raw/Alpha_Intelligence/` |
| **News RSS (via n8n)** | RSS + LLM | Daily | 4 topics: Financial/Macro, Geopolitical, Technology, Portugal Local | TrueNAS Postgres (bronze + silver) |
| **FRED historical CSVs** | Static files | One-off | GDP, CPI, PPI, unemployment level & rate, interest rates (1913–2024) | `AI_SP500_Source/` |

> **Rate-limit reality check.** 511 tickers × 88 functions = **44,968 calls per full pass**. At the current `sleep_time=15` that is ~7.8 days of continuous running, so the "weekly" cadence is not currently achievable. About 82% of those calls are avoidable — see [issue 11](#5-index-level-endpoints-are-fetched-once-per-ticker) and [ARCHITECTURE.md § Ingestion budget](ARCHITECTURE.md#11-what-carries-over-unchanged).

---

## Setup

### Prerequisites

- Python 3.12+ and [Poetry](https://python-poetry.org/)
- Docker + Docker Compose
- An AWS account with an S3 bucket
- A PostgreSQL instance (this project targets the one already running on TrueNAS Scale)
- An Alpha Vantage API key

### Install

```bash
cd /Users/tiagoreis/0_MainProjects/AI_SP500 && poetry install
```

### Configure

Create `DataIngestion/.env` (git-ignored — never commit it):

```bash
# AWS
S3_ACCESS_KEY=...
S3_SECRET_ACCESS_KEY=...
REGION_NAME=eu-west-1
BUCKET_NAME=your-bucket

# APIs
ALPHA_VANTAGE_API_KEY=...
ALPHA_VANTAGE_API_KEY_2=...
API_NINJA=...

# Postgres (TrueNAS)
POSTGRES_HOST=truenas.local
POSTGRES_PORT=5432
POSTGRES_DB=aisp500
POSTGRES_USER=...
POSTGRES_PASSWORD=...
```

### Create the log table

```bash
psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f DataIngestion/Logs_OLTP/ddl_queries.sql
```

---

## Running the Ingestion Layer

### Locally

```bash
poetry run python DataIngestion/getRequesterWeekly.py
```

### Via Docker Compose

```bash
docker compose -f DataIngestion/docker-compose.yaml up -d
```

### Building and publishing images

```bash
docker build -t tiagobcr/sp500-data-ingestion_arm64 -f DataIngestion/Dockerfile .
```

```bash
docker buildx build --platform linux/amd64 -t tiagobcr/sp500-data-ingestion_amd64:latest -f DataIngestion/Dockerfile .
```

### Checking pipeline health

```sql
SELECT function, symbol, ts, file_size_bytes, log_message
FROM s3_ingestion_logger
ORDER BY ts DESC
LIMIT 50;
```

---

## Known Issues

Ordered by severity. Each is a concrete, fixable defect confirmed by reading or running the code.

### 1. `getRequesterDailyAI.py` crashes immediately — daily news ingestion has never run

`DataIngestion/getRequesterDailyAI.py:31` calls `datetime.date.today()`, but line 5 imports `from datetime import datetime, timedelta`. `datetime.date` is an unbound method descriptor, not the `date` class:

```
AttributeError: 'method_descriptor' object has no attribute 'today'
```

The line sits **before** the `try` block, so it is not caught and the process dies on the first iteration. Fix: `import datetime` at module level (as the sibling scripts do), or use `datetime.now().date()`.

### 2. `s3_upload_message` can be referenced before assignment in every error handler

In `getRequesterDailyAI.py:64`, `getRequesterWeekly.py:78` and `getRequesterWeeklyAI.py:125`, the `except` block builds its log message from `s3_upload_message`. If the failure happened in `get_json_response()` — an HTTP error, i.e. the common case — that variable was never assigned. The handler then raises `NameError`, **masking the original error and killing the loop**. Fix: initialise to `""` before the `try`, or use `str(e)` alone.

### 3. `ANALYTICS_FIXED_WINDOW` is unreachable

`getRequesterWeeklyAI.py:194`: the `elif function_name == "EARNINGS_CALL_TRANSCRIPT"` branch lives inside the `else` of a check that already excluded that value. The condition can never be true, so `analytics_fixed_window()` is never called and that endpoint is never fetched.

### 4. `analytics_fixed_window()` returns only the last ticker

`getRequesterWeeklyAI.py:90`: `combined_data = {}` is reset inside the per-ticker loop, so all prior tickers are discarded. Move the initialisation above the loop.

### 5. Index-level endpoints are fetched once per ticker

`getRequesterWeekly.py:45` sets `params["symbol"] = symbol` for **every** endpoint, including the 21 Commodities and Economic Indicators functions that have no symbol dimension. Alpha Vantage ignores the unknown parameter and returns the same national series each time, so the pipeline fetches identical WTI, Brent, CPI and unemployment payloads **511 times each** and writes 511 near-duplicate objects to S3.

That is **10,731 API calls doing the work of 21**, plus the storage and the Silver-layer dedup burden that follows. Fix: add an `entity_level` field (`"index"` or `"ticker"`) to each endpoint in `alpha_vantage_urls.json` and only loop tickers where it says `ticker`.

Combined with the 26,061 calls spent fetching technical indicators that could be computed locally from prices, **~82% of the current API budget is avoidable**. See [ARCHITECTURE.md § Ingestion budget](ARCHITECTURE.md#11-what-carries-over-unchanged).

### 6. `getRequesterWeekly.py` re-runs with no cooldown

The `while True:` at line 38 restarts a full ~40,000-call pass the instant the previous one ends. There is no sleep between passes and no watermark. Combined with issue 2, a single HTTP error can also abort mid-pass with a `NameError`.

### 7. `Silver_Layer/SP500_CompaniesList.py` is stale

Line 44 hardcodes `/Users/tiagoreis/PycharmProjects/AI_SP500/DataIngestion_&_BronzeLayer/.env` — a path that no longer exists in either project location. It also reads `ACCESS_KEY`/`SECRET_ACCESS_KEY`, while `.env` defines `S3_ACCESS_KEY`/`S3_SECRET_ACCESS_KEY`.

### 8. `AWS_EC2.py` is not valid Python

It is a pasted AWS console snippet using `{"key": value}` syntax inside positional call arguments. `python -m py_compile` fails at line 8. Either rewrite it against the boto3 API or delete it in favour of the on-demand EC2 pattern in ARCHITECTURE.md.

### 9. Duplicate PostgreSQL instances

`DataIngestion/docker-compose.yaml` provisions a `postgres-logging` container on host port 5433, while TrueNAS already runs a Postgres used by n8n. Two databases means two places to look when something breaks, and the news feed and the API feed cannot be joined. Under v0.3 both consolidate onto the **MP9** analytics Postgres, not the TrueNAS one — see [deploy/README.md](deploy/README.md).

### 10. `s3_ingestion_logger` is under-specified for a control plane

`log_message VARCHAR(255)` truncates real stack traces. There is no `status` enum, no `run_id`, and no `duration_ms`, so "did last night's run succeed?" cannot be answered with a single query. Superseded by `platform.ingestion_log` in [`sql/001_schema.sql`](sql/001_schema.sql).

### 11. Repository location is ambiguous

Two directories share this project's name:

- `/Users/tiagoreis/0_MainProjects/AI_SP500` — **the real repository** (git, code, history)
- `/Users/tiagoreis/PycharmProjects/AI_SP500` — an empty Airflow scaffold with stale `logs/` from September 2025, no git

The second is dead weight and several scripts still reference paths under it. Delete it once you have confirmed it holds nothing you need.

---

## Roadmap

v0.4 phases. **Phase A is unchanged, independent of the pipeline, and still first.**

| Phase | Work | Exit criterion |
|---|---|---|
| **A. Reclaim TrueNAS RAM** | ARC + WiredTiger caps; migrate 3 stateless UIs | >4 GB available; ARC hit ratio >85% |
| **B. Cloud foundation** | `terraform apply`; `make athena-apply` | Athena queries an empty lakehouse; budget alarm armed |
| **C. Fix ingestion defects** | The eleven [known issues](#known-issues) | Every script completes a pass |
| **D. Edge rebuild** | Streaming ingest → raw+bronze; landing PG as 30-day buffer; sync + prune units | A day of data queryable in bronze; ZFS pool untouched |
| **E. Silver + DQ + orchestration** | MERGEs, DQ suite, daily state machine | Green run in the SFN console; a red DQ check blocks gold |
| **F. Gold + lookahead** | Features, labels, as-of joins, technicals in Athena SQL | `gold_no_lookahead` passes |
| **G. News + LLM** | Ollama scoring (pinned model), sync path, news features | `silver.news` carries `llm_model` + `prompt_hash` |
| **H. ML** | Naive baseline → logistic → XGBoost; `ops.ml_runs` with snapshot IDs; daily scoring | A model beats the baseline out-of-sample |
| **I. Portfolio polish** | Streamlit, CI, model cards, ADR pass, skills index | A stranger can evaluate the repo in ten minutes |

Detailed tasks: **[ARCHITECTURE.md § Roadmap](ARCHITECTURE.md#12-roadmap)**. Edge deployment:
**[deploy/README.md](deploy/README.md)**. Cloud deployment: `infra/Makefile`.

---

## Design Principles

1. **Use the hardware that is already on — but put each workload where it fits.** Both nodes run 24/7 regardless. Batch work goes to the idle MP9; only the GPU and the homelab stay on the saturated TrueNAS.
2. **Right-size the bill, and say why out loud.** ~3.5 M rows / ~2 MB per day does not *require* a lakehouse — [ADR-001](docs/adr/ADR-001-lakehouse-for-small-data.md) says so in writing. The lakehouse exists to demonstrate the patterns at production fidelity, on services that bill per request; nothing anywhere is hourly-billed or always-on in the cloud.
3. **The constrained node gets nothing new.** Any design that adds resident memory to the TrueNAS is wrong by construction, however elegant.
4. **Minimise writes to a pool at 81%.** Raw data and the warehouse live in S3; the edge buffer lives on the MP9's SSD. The pipeline adds zero bytes to ZFS.
5. **Raw data is immutable.** Never mutate `raw/`. Every layer is reproducible by replaying from it.
6. **Point-in-time correctness is non-negotiable.** A feature must only ever use information that existed at prediction time. Lookahead bias is the fastest way to build a model that backtests beautifully and loses money.
7. **Configuration over code.** New endpoints are JSON entries, not new modules.
8. **One audit trail per plane, one alert path overall.** Edge feeds log to the landing Postgres; the lakehouse logs to `ops.dq_results` and `ops.ml_runs`; every failure — systemd or SNS — terminates at the same n8n webhook.
9. **Every stage runs standalone.** No step may require the scheduler to be up in order to be tested or backfilled; the state machine re-runs any `run_date` idempotently.
10. **Quality gates block promotion.** Silver never becomes gold on a red check, and `gold_no_lookahead` can never be waived.

---

## Technology Stack

**Edge (on-prem):** Python (`requests`, `boto3`), n8n, Ollama on RTX 3060, systemd timers, landing PostgreSQL (30-day buffer)
**Data lake (AWS):** S3 `raw/` (verbatim, immutable, delete-denied) + `bronze/` (normalized JSONL) — the system of record
**Lakehouse (AWS, all per-request):** Apache Iceberg, Glue Data Catalog, Athena engine v3, Step Functions, EventBridge Scheduler, Lambda, SNS
**Distributed processing:** PySpark on EMR Serverless — bulk historical backfill only, €0 idle ([ADR-004](docs/adr/ADR-004-spark-for-bulk-backfill.md))
**ML:** scikit-learn, XGBoost in Lambda batch; `ops.ml_runs` with Iceberg snapshot lineage; model cards
**Serving:** Streamlit on the MP9 (queries Athena), n8n email digest
**Engineering:** Terraform, GitHub Actions (Phase I), ADRs, schemas-as-code (`make athena-apply`)

Deliberately absent — each rejected in an [ADR](docs/adr/) with a revisit trigger: Delta Lake,
Databricks clusters, MWAA, Glue crawlers, Glue Spark as the *daily* engine, Redshift,
SageMaker endpoints, Kinesis, streaming of any kind. Spark is present but scoped: bulk
backfill only, never the daily path.

---

## License

GPL-3.0-only. See [LICENSE](LICENSE).
