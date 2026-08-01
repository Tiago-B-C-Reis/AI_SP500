# Changelog

All notable changes to **AI_SP500**.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project does not yet publish versioned releases; entries below are grouped
into development phases and dated from the git history.

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
[ARCHITECTURE.md § Next Steps](ARCHITECTURE.md#11-next-steps).
