# Deployment — on-prem edge (architecture v0.4)

> **v0.4 note.** This guide covers the **edge**: the MP9 and TrueNAS. The cloud lakehouse
> (S3 + Iceberg + Athena + Step Functions) deploys separately via
> [`infra/`](../infra/) — `make terraform-apply` then `make athena-apply`.
> Changes from v0.3 on the edge:
> - The MP9 Postgres is now a **30-day landing buffer**, not the warehouse — drop its
>   compose memory limit to **1 GB** (`shared_buffers=256MB`) and apply only the
>   `platform` schema + `silver.news` from `sql/001_schema.sql`.
> - systemd stages are now `ingest-daily`, `ingest-weekly`, **`sync-lake`**,
>   **`prune-landing`** — `sp500-build-gold` and `sp500-train` are retired locally
>   (both moved into the cloud state machines).
> - The MP9 `.env` gains the edge-uploader AWS key (Terraform output
>   `edge_uploader_name`) — the only AWS credential on-prem, scoped to `PutObject`.

Two nodes, one cloud bucket. **Nothing new becomes resident on the TrueNAS.**

| Node | Role |
|---|---|
| `mp9.lan` — HP MP9 G2, Ubuntu, 16 GB | Edge: capped ingest/sync jobs, landing Postgres buffer, optional Streamlit |
| `truenas.lan` — TrueNAS Scale, 16 GB | n8n, Ollama + RTX 3060, existing homelab. Unchanged by this project |
| AWS | Raw archive + the entire lakehouse (see [`infra/`](../infra/)) |

> **Do Phase A first.** [`truenas/TUNING.md`](truenas/TUNING.md) reclaims several GB on the
> constrained node and is independent of everything below. It is the largest single
> improvement available and does not depend on the pipeline existing.

---

## 1. MP9 — prerequisites

```bash
sudo apt update && sudo apt install -y docker.io docker-compose-v2 python3-venv curl jq
```

`curl` and `jq` are used by the failure-alert unit; `python3-venv` by the pipeline.

Create a dedicated unprivileged user and the directory layout the systemd units expect:

```bash
sudo useradd -r -s /usr/sbin/nologin -d /opt/ai_sp500 sp500
sudo mkdir -p /opt/ai_sp500/{models,state}
sudo chown -R sp500:sp500 /opt/ai_sp500
```

`models/` and `state/` are the only writable paths — the units run with
`ProtectSystem=strict`, which makes everything else read-only.

---

## 2. MP9 — Postgres

```bash
cd /opt/ai_sp500/deploy/mp9 && cp .env.example .env && chmod 600 .env
```

Fill in `.env`, then bring the database up:

```bash
docker compose up -d postgres
```

`sql/001_schema.sql` is applied automatically on first initialisation. Verify:

```bash
docker exec sp500-postgres psql -U sp500 -d aisp500 -c '\dn' -c '\dt silver.*'
```

Restrict LAN exposure to the TrueNAS, which needs it for n8n's Postgres writes:

```bash
sudo ufw allow from <truenas-ip> to any port 5432 proto tcp
```

---

## 3. MP9 — orchestration

```bash
sudo cp /opt/ai_sp500/deploy/mp9/systemd/*.service /opt/ai_sp500/deploy/mp9/systemd/*.timer /etc/systemd/system/
```

```bash
sudo systemctl daemon-reload && sudo systemctl enable --now sp500-ingest-daily.timer sp500-ingest-weekly.timer sp500-sync-lake.timer sp500-prune-landing.timer
```

Confirm the schedule:

```bash
systemctl list-timers 'sp500-*' --all
```

### Everyday operations

Run a stage now, without waiting for its timer:

```bash
sudo systemctl start sp500-ingest-daily.service
```

Follow a run:

```bash
journalctl -u sp500-ingest-daily.service -f
```

Backfill a date range at the edge (cloud backfills re-run the state machine with an explicit `run_date`):

```bash
sudo -u sp500 /opt/ai_sp500/.venv/bin/python -m pipeline run --stage ingest-daily --from-date 2024-01-01
```

Confirm the memory ceilings are actually enforced:

```bash
systemctl show sp500-ingest-daily.service -p MemoryMax -p MemoryHigh
```

Run history — this is what replaces the Airflow UI:

```sql
SELECT * FROM platform.v_feed_health;
SELECT * FROM platform.v_staleness;
```

---

## 4. TrueNAS — n8n control plane

Three additions to the existing n8n instance. All are workflow edits; none adds a container.

**a. Failure webhook.** A Webhook node at path `sp500-alert` (POST). The systemd
`OnFailure=` handler posts `{unit, host, ts, logs}` — route it to your preferred
notification channel. Set the resulting URL as `N8N_ALERT_WEBHOOK` in the MP9 `.env`.

**b. Daily health digest.** A Schedule Trigger at 07:00 UTC querying
`platform.v_feed_health` and `platform.v_staleness` on `mp9.lan:5432`. Fold this into
the digest the news workflow already emails.

**c. Freshness watchdog.** Alert when any feed's newest row is older than its cadence.
This catches the failure mode a status check cannot see — a job that runs, reports
success, and quietly returns nothing.

### Repoint the news workflow

- Change the Postgres credential from the TrueNAS instance to `mp9.lan:5432`.
- Swap the OpenRouter/Gemini chat nodes for **Ollama** at `http://localhost:11434`
  (n8n and Ollama share the TrueNAS), with `format: json`.
- Constrain the Research Agent's output to the fixed scoring schema and write
  `llm_model` and `prompt_hash` on every row.
- Append a `platform.ingestion_log` insert with `feed='n8n_news'`.

**Do this before backfilling.** Changing the LLM mid-series creates a discontinuity in
the sentiment feature that a model will read as a genuine market signal — see
[ARCHITECTURE.md §11](../ARCHITECTURE.md#11-what-carries-over-unchanged).

---

## 5. Verification

| Check | Command | Expected |
|---|---|---|
| Timers armed | `systemctl list-timers 'sp500-*'` | 4 timers with future `NEXT` |
| Postgres reachable from TrueNAS | `pg_isready -h mp9.lan -U sp500` | `accepting connections` |
| Ollama reachable from MP9 | `curl -s http://truenas.lan:11434/api/tags` | JSON model list |
| Memory caps enforced | `systemctl show sp500-ingest-daily -p MemoryMax` | `MemoryMax=536870912` |
| **TrueNAS RAM freed** | `free -h` | > 4 GB available |
| **ZFS pool unchanged** | `zpool list -o capacity` | no growth from this project |

---

## Notes and caveats

- **The SQL has not been executed against a live PostgreSQL** — no daemon was available
  in this environment. It has been reviewed carefully (one nested-window-function bug was
  found and fixed in the labels query), but run `001_schema.sql` against a scratch database
  before trusting it in place.
- `MemoryMax=` requires **cgroup v2**, the default on Ubuntu 22.04 and later. Verify with
  `stat -fc %T /sys/fs/cgroup` → `cgroup2fs`.
- `pipeline/` does not exist yet — the systemd units reference the entry point that
  ARCHITECTURE.md Phase D specifies (`python -m pipeline run --stage ...`). Install the
  units when that module lands, or they will fail on first fire. The `sync-lake` and
  `prune-landing` units are copies of the ingest unit pattern (same caps, same
  `OnFailure=`) pointing at their stage names — create them from
  `sp500-ingest-daily.service` when the stages exist.
- The MP9 becomes a single point of failure for batch work. This is acceptable: every job
  is watermark-driven and resumes from where it stopped, and `Persistent=true` re-runs a
  missed timer on boot.
