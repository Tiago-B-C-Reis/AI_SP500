# AI_SP500 — A Personal Data Platform for S&P 500 Research

**AI_SP500** collects economic, financial and geopolitical data that influence the S&P 500, refines it through a Bronze → Silver → Gold lakehouse, and serves it as a feature store for predictive modelling.

It is a personal research platform, deliberately built to run at near-zero marginal cost on **hardware that is already switched on 24/7** — a TrueNAS Scale home server — using AWS only where the cloud genuinely earns its keep (durable off-site raw archive, and burst compute on demand).

> **Status: active — rebuilding after a dormant period.**
> The ingestion layer is the only production component today. The transformation, feature and modelling layers are not built yet. See [Current State](#current-state) for an honest breakdown and [Known Issues](#known-issues) for what is currently broken.

---

## Table of Contents

- [Goals](#goals)
- [Current State](#current-state)
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

Explicit non-goals: beating professional quant funds, running an enterprise-scale platform, or paying for always-on cloud compute.

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

## Architecture

The original design (`InfaArquitecture_V0.1.png`) targeted Spark, Delta Lake, Unity Catalog, Amazon Aurora and always-on EC2. That stack is disproportionate to this project's data volume and cost budget.

**Architecture v0.2** — the current target — is documented in **[ARCHITECTURE.md](ARCHITECTURE.md)**. Summary of the shift:

| Concern | v0.1 (original) | v0.2 (current target) |
|---|---|---|
| Compute engine | Spark on EC2 | **DuckDB** on TrueNAS |
| Table format | Delta Lake | Hive-partitioned **Parquet** |
| Catalog | Unity Catalog | Postgres control-plane tables |
| Warehouse | Amazon Aurora | **Existing TrueNAS Postgres** |
| Orchestration | Airflow on EC2 | **Airflow on TrueNAS** (n8n retained for agentic news) |
| Always-on cloud | EC2 24/7 | **None** — EC2 on demand only |
| News feed | Not modelled | **n8n pipeline as a first-class source** |
| Monthly cost | ~€60–150 | **~€1** (S3 storage only) |

The guiding rule: *TrueNAS is the platform; S3 is the archive; EC2 is a rented burst.*

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
├── AI_SP500_Airflow/               # Airflow scaffold — dags/ is EMPTY
├── BronzeLayer/                    # EMPTY
├── Silver_Layer/                   # One exploratory PySpark script
├── AI_SP500_Source/                # Historical CSVs (FRED macro, 1913–2024)
├── ARCHITECTURE.md                 # ← v0.2 design
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

> **Rate-limit reality check.** 511 tickers × 88 functions = **44,968 calls per full pass**. At the current `sleep_time=15` that is ~7.8 days of continuous running, so the "weekly" cadence is not currently achievable. About 82% of those calls are avoidable — see [issue 11](#5-index-level-endpoints-are-fetched-once-per-ticker) and [ARCHITECTURE.md § Ingestion budget](ARCHITECTURE.md#8-ingestion-budget).

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

Combined with the 26,061 calls spent fetching technical indicators that could be computed locally from prices, **~82% of the current API budget is avoidable**. See [ARCHITECTURE.md § Ingestion budget](ARCHITECTURE.md#8-ingestion-budget).

### 6. `getRequesterWeekly.py` re-runs with no cooldown

The `while True:` at line 38 restarts a full ~40,000-call pass the instant the previous one ends. There is no sleep between passes and no watermark. Combined with issue 2, a single HTTP error can also abort mid-pass with a `NameError`.

### 7. `Silver_Layer/SP500_CompaniesList.py` is stale

Line 44 hardcodes `/Users/tiagoreis/PycharmProjects/AI_SP500/DataIngestion_&_BronzeLayer/.env` — a path that no longer exists in either project location. It also reads `ACCESS_KEY`/`SECRET_ACCESS_KEY`, while `.env` defines `S3_ACCESS_KEY`/`S3_SECRET_ACCESS_KEY`.

### 8. `AWS_EC2.py` is not valid Python

It is a pasted AWS console snippet using `{"key": value}` syntax inside positional call arguments. `python -m py_compile` fails at line 8. Either rewrite it against the boto3 API or delete it in favour of the on-demand EC2 pattern in ARCHITECTURE.md.

### 9. Duplicate PostgreSQL instances

`DataIngestion/docker-compose.yaml` provisions a `postgres-logging` container on host port 5433, while TrueNAS already runs a Postgres used by n8n. Two databases means two places to look when something breaks, and the news feed and the API feed cannot be joined. Consolidate onto the TrueNAS instance.

### 10. `s3_ingestion_logger` is under-specified for a control plane

`log_message VARCHAR(255)` truncates real stack traces. There is no `status` enum, no `run_id`, and no `duration_ms`, so "did last night's run succeed?" cannot be answered with a single query. Superseded by the `platform.ingestion_log` design in ARCHITECTURE.md.

### 11. Repository location is ambiguous

Two directories share this project's name:

- `/Users/tiagoreis/0_MainProjects/AI_SP500` — **the real repository** (git, code, history)
- `/Users/tiagoreis/PycharmProjects/AI_SP500` — an empty Airflow scaffold with stale `logs/` from September 2025, no git

The second is dead weight and several scripts still reference paths under it. Delete it once you have confirmed it holds nothing you need.

---

## Roadmap

| Phase | Objective | Exit criterion |
|---|---|---|
| **0. Stabilise** | Fix the defects above; consolidate onto one Postgres | Every ingestion script runs a full pass without crashing; one query shows the health of all feeds |
| **1. Read path** | S3 raw JSON → typed Parquet Silver via DuckDB | `silver.prices_daily` and `silver.macro_daily` queryable locally |
| **2. Integrate n8n** | Normalise the news feed into the platform schema | `silver.news` carries numeric sentiment with `published_at` **and** `ingested_at` |
| **3. Gold / feature store** | One point-in-time-correct row per `(date, ticker)` and per `date` | `gold.features_daily` materialised in Postgres |
| **4. Backtest harness** | Walk-forward evaluation before any modelling | A naive baseline is scored honestly; leakage tests pass |
| **5. Models** | Logistic → XGBoost → sequence models | A model that beats the naive baseline out-of-sample |
| **6. Serving** | Streamlit dashboard + Grafana pipeline health | Predictions and pipeline status visible without SSH |

Detailed, sequenced tasks live in **[ARCHITECTURE.md § Next Steps](ARCHITECTURE.md#11-next-steps)**.

---

## Design Principles

1. **Use the hardware that is already on.** TrueNAS runs 24/7 regardless. Every workload that can run there, should.
2. **Right-size the engine.** This platform's daily volume is megabytes, not terabytes. DuckDB on one node beats a Spark cluster on every axis that matters here.
3. **The cloud is for durability and burst, not for uptime.** S3 holds the immutable raw archive. EC2 is rented by the hour when a model needs a GPU, then terminated.
4. **Raw data is immutable.** Never mutate `raw/`. Every layer is reproducible by replaying from it.
5. **Point-in-time correctness is non-negotiable.** A feature must only ever use information that existed at prediction time. Lookahead bias is the fastest way to build a model that backtests beautifully and loses money.
6. **Configuration over code.** New endpoints are JSON entries, not new modules.
7. **One control plane.** Every feed — Python or n8n — logs to the same table.

---

## Technology Stack

**Ingestion:** Python (`requests`, `boto3`, `yfinance`, `beautifulsoup4`), n8n
**Storage:** AWS S3 (raw archive), local Parquet (lakehouse), PostgreSQL (control plane + serving)
**Processing:** DuckDB, pandas
**Orchestration:** Apache Airflow (batch), n8n (agentic news)
**ML:** scikit-learn, XGBoost, PyTorch; MLflow for tracking
**Serving:** Streamlit, Grafana
**Infrastructure:** TrueNAS Scale, Docker, Poetry

---

## License

GPL-3.0-only. See [LICENSE](LICENSE).
