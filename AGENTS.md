# AI_SP500 agentic execution brief

> **Contract status:** `OWNER INPUT INCOMPLETE`
>
> **Current authorization:** local, reversible repository work only. No live API calls,
> cloud deployment, host changes, image publication, or scheduled execution.
>
> **Last repository audit:** 2026-08-28
>
> **Owner:** Tiago Reis

This is the operating contract for autonomous agents working in this repository. It is
intentionally safe to commit: never add credential values, private addresses, tokens,
personal records, or unrelated family information here. Store only secret *references*.

`[OWNER INPUT REQUIRED]` means the agent must use the fail-closed default in the same row.
An agent must not infer authorization from the existence of code, credentials, Terraform,
Docker files, SSH configuration, or an already-running service.

## 1. Mission and boundaries

AI_SP500 is a personal research and portfolio platform for collecting market, economic, and
news data; refining it through Bronze, Silver, and Gold layers; and evaluating point-in-time
S&P 500 forecasting models.

The goals, in priority order, are:

1. Correct, reproducible, leakage-free research.
2. A deployable, observable, low-maintenance data platform.
3. Credible Data Engineering and MLOps portfolio evidence.
4. Low and bounded operating cost.

This is **research only**. Agents must never place or simulate live securities orders, connect
brokerage execution, present predictions as financial advice, or claim profitable performance
without reviewed out-of-sample evidence.

Default next milestone: **Phase 0 safety and reproducibility**, followed by the selected
roadmap phase. Phase 0 means:

1. rotate the exposed credentials through an owner-controlled process;
2. remove secrets from code, logs, container contexts, and published artifacts;
3. establish Python 3.12, a current lock file, unit tests, linting, secret scanning, and CI;
4. define the prediction instant and correct the point-in-time feature semantics;
5. reconcile the v0.4 deployment files with the documented design;
6. test the cloud foundation with all schedules disabled before enabling automation.

## 2. Sources of truth

Use this precedence order when sources disagree:

1. Observed live state, but only when the agent has explicit read access to the named
   environment and reports the observation time.
2. Executable code plus passing tests in the current checkout.
3. This file's completed owner decisions.
4. [`README.md`](README.md) for current versus planned component status.
5. [`ARCHITECTURE.md`](ARCHITECTURE.md) and accepted records in [`docs/adr/`](docs/adr/)
   for the target design.
6. [`CHANGELOG.md`](CHANGELOG.md) for historical context.

Treat these as superseded or non-authoritative unless a task explicitly targets them:

- `SP500_ProjectDescription.md`: Aurora/EC2/Delta/Airflow-era concept.
- `AI_SP500_Airflow/`: superseded scaffold and historical logs.
- `AWS_EC2.py` and `AWS_EC2.yaml`: legacy artifacts, not deployment code.
- `Silver_Layer/SP500_CompaniesList.py`: stale exploratory script.
- `DataIngestion/test*.py`: network scratch scripts, not automated tests.

Never turn a planned or scaffolded feature into an implemented/deployed portfolio claim.

## 3. Current truth versus target architecture

### 3.1 Evidence-backed current state

- The implemented path is Alpha Vantage HTTP ingestion to uncompressed, pretty-printed raw
  JSON in S3, followed by one PostgreSQL log insert per attempt.
- The weekly core loop is unbounded and currently evaluates 511 tickers by 88 endpoints.
- Daily intelligence ingestion crashes before its first protected request.
- Weekly intelligence ingestion is partial and has unsafe checkpoint/error behavior.
- The external n8n news workflow is not versioned or testable in this repository.
- There is no working `pipeline` package, normalized Bronze writer, production Silver/Gold
  path, model, scoring Lambda, dashboard, CI pipeline, or installable v0.4 edge deployment.
- Terraform, Athena SQL, Step Functions, and Spark are target scaffolding and have not been
  validated against the owner's live AWS account.

### 3.2 Target v0.4 flow

```text
Alpha Vantage / yfinance / RSS
        |
        v
MP9 edge: bounded systemd ingest + landing PostgreSQL + sync/prune
        |                              ^
        |                              | LAN news rows
        v                              |
S3 raw + normalized Bronze       TrueNAS: n8n + optional local Ollama
        |
        v
Glue Catalog + Iceberg Silver/Gold/ops on S3
        ^
        |
Athena SQL <- Step Functions <- EventBridge Scheduler
        |
        +-> DQ gates -> batch score/train -> n8n/Streamlit consumers

Rare historical backfill: S3 raw -> PySpark on EMR Serverless -> Iceberg Silver
```

Target constraints:

- no always-on cloud compute;
- no new resident analytics workload on TrueNAS;
- no pipeline writes to the TrueNAS ZFS pool;
- raw source bytes are preserved and derived layers are replayable;
- quality failure blocks promotion;
- every model is linked to code, features, data snapshot, and evaluation window;
- all recurring workloads have an owner-approved cost and a bounded retry/runtime policy.

## 4. Known blockers: do not deploy around these

### P0 security

- A real Alpha Vantage key is committed in `DataIngestion/test.py` and
  `DataIngestion/test0.py`. It also matches the ignored working configuration as of the
  2026-08-28 audit. Treat it as compromised; never repeat it in output.
- `DataIngestion/Helper_Functions/ingestion.py` prints a URL containing the API key.
- `.dockerignore` does not exclude `.env`, while the Dockerfile copies `DataIngestion/`.
  Previously published images may contain AWS, API, or PostgreSQL credentials.
- Credential remediation order is: revoke/rotate, stop secret logging, exclude secrets from
  build contexts, scan code/history/images, rebuild with an immutable tag, then republish.
- Git history rewriting, credential rotation, registry deletion, and force-push require
  explicit owner approval and coordination.

### P0 data and model correctness

- Gold currently calculates same-day closing-price features but declares them available at
  that day's market open. The `gold_no_lookahead` check validates the declared timestamp, not
  when price inputs became known, and therefore passes by construction.
- Athena's price MERGE overwrites matched rows unconditionally; Spark updates only when
  `fetched_at` is newer. Replaying an older Athena partition can replace newer data.
- Empty or missing inputs can pass several DQ checks; add explicit partition/row-count gates.
- No model result may be published until the prediction instant, feature availability,
  labels, embargo, walk-forward split, naive baseline, and decision metric are owner-approved.

### P1 deployment and reproducibility

- Systemd units call a nonexistent `python -m pipeline` entry point.
- The documented `sync-lake` and `prune-landing` units do not exist; retired local Gold/train
  units remain.
- v0.4 says PostgreSQL is capped at 1 GB with 256 MB shared buffers; deployable files still
  use a 3 GB container and 1 GB shared buffers.
- Terraform schedules the daily state machine but does not create `ai-sp500-score`, so an
  apply would schedule a predictable daily failure.
- Weekly cloud training and maintenance machines are documented but not provisioned.
- Bronze DDL is incomplete for macro/commodity feeds; trading-calendar seeding is manual;
  `ops.pipeline_runs` is described but absent.
- Terraform has no configured remote-state backend or provider lock file.
- The AWS Budget SNS topic lacks the resource policy required for
  `budgets.amazonaws.com` to publish.
- The current `.venv` is Python 3.9.6, while `pyproject.toml` requires Python 3.12+;
  `poetry check --lock` fails because the lock file is stale.
- There is no pytest/ruff/pre-commit/CI configuration. Existing `test*.py` files make live
  calls and contain no useful assertions.
- The legacy Compose file pins an ARM64 ingestion image, but the MP9 target is AMD64.

## 5. Prediction-time decision

The owner must select one contract before Gold or ML work continues.

| Approach | Pros | Cons | Correctness and performance impact |
|---|---|---|---|
| **Pre-market on day T using data known before T market open (recommended)** | Matches the 07:00 UTC cloud schedule; produces an actionable daily research signal; clear cutoff | Day T close and intraday data are unavailable; features must lag price data to T-1 | Removes the current same-day-close leak; honest metrics will likely be lower than the current design |
| **After day T close, predict T+1** | Uses the latest completed bar and same-day news; technically simple | Requires a later schedule and precise close/late-publication handling; signal arrives after the session | Same-day close becomes legitimate only if `feature_asof` is after close; evaluation target and dashboard timing change |

Decision: `[OWNER INPUT REQUIRED: PRE_MARKET_T or POST_CLOSE_T]`.

Fail-closed default: `PRE_MARKET_T`; all price-derived features for a day-T prediction must
come from T-1 or earlier, and every source must carry an availability timestamp.

## 6. Environment matrix

| Environment | Known role | Current assumption | Missing owner input | Fail-closed default |
|---|---|---|---|---|
| MacBook Air M1, 8 GB | Development and ad-hoc analysis | No scheduled workloads; test ARM64 locally | Approved Python manager and Docker workflow | Local tests only |
| HP MP9 G2, Ubuntu, 16 GB/128 GB | Target edge node | AMD64; bounded PostgreSQL and transient jobs | SSH alias, user, sudo policy, install path, measured watts, maintenance window | No connection or mutation |
| TrueNAS Scale v25.10.1, 16 GB, RTX 3060 | Existing homelab services; optional n8n/Ollama feed | Repository hardware/app snapshot is stale; current pool and app state must be remeasured | Read-only access method, allowed apps, Ollama decision/model digest, current RAM/pool baseline | No tuning, app changes, or new ZFS writes |
| AWS | Target lakehouse | `eu-west-1`; no live deployment evidence or configured local profile | Account alias/ID reference, role/profile, environment, billing/tax context | No AWS API calls |
| PostgreSQL | Current logs and target MP9 landing buffer | Documentation and Compose disagree | Exact scratch/live target, backup, cap, retention, RPO/RTO | Scratch database only |
| n8n | External news and alert control plane | Workflow is outside Git; current cloud-model usage is unknown | Export/workflow ID, owner, model IDs, webhook secret reference, change authority | No workflow calls or edits |

Do not place private IP addresses, passwords, API keys, webhook URLs, AWS account IDs, or SSH
material in this file. Record their names/aliases in an owner-approved secret manager and put
only references here.

## 7. Owner input register

Complete every blocking row before unattended execution.

| ID | Required decision or fact | Known/default | Owner value |
|---|---|---|---|
| GOAL-1 | Next deliverable and selected roadmap phase | Phase 0, then Phase C | `[OWNER INPUT REQUIRED]` |
| GOAL-2 | Utility versus portfolio priority | Correctness/operability before demonstration | `[OWNER INPUT REQUIRED]` |
| TIME-1 | Target date and weekly maintenance time available | No deadline assumed | `[OWNER INPUT REQUIRED]` |
| GIT-1 | Base branch | Current work is on `dev`; `main` is older | `[OWNER INPUT REQUIRED]` |
| GIT-2 | Commit policy | Small meaningful commits; stage only scoped paths | `[OWNER INPUT REQUIRED]` |
| GIT-3 | Push, PR, review, merge, and release authority, separately | None | `[OWNER INPUT REQUIRED]` |
| CLOUD-1 | AWS account/environment and read-only role/profile reference | Region `eu-west-1` | `[OWNER INPUT REQUIRED]` |
| CLOUD-2 | Exact globally unique lake bucket name | Required Terraform variable | `[OWNER INPUT REQUIRED]` |
| CLOUD-3 | Terraform state backend, locking, backup, and recovery owner | Backend is only a comment | `[OWNER INPUT REQUIRED]` |
| CLOUD-4 | Whether any Terraform/resources already exist in any region | No repository evidence | `[OWNER INPUT REQUIRED]` |
| COST-1 | Maximum AWS forecast/month, including VAT | Terraform alerts at USD 5, not EUR | `[OWNER INPUT REQUIRED]` |
| COST-2 | Maximum total project cost/month, including APIs and electricity | Unknown | `[OWNER INPUT REQUIRED]` |
| COST-3 | Maximum cost for one autonomous run/backfill | USD 1 recommended until measured | `[OWNER INPUT REQUIRED]` |
| COST-4 | All-in electricity price and measured MP9/TrueNAS watts | Use smart-plug measurements | `[OWNER INPUT REQUIRED]` |
| API-1 | Alpha Vantage plan, billing cadence, rate, licence, and number of keys | 75 RPM target implies paid service | `[OWNER INPUT REQUIRED]` |
| API-2 | Live-call limits for canary, day, week, and backfill | Zero | `[OWNER INPUT REQUIRED]` |
| API-3 | API Ninjas plan/permission to persist constituent data, or replacement source | Current code persists the response | `[OWNER INPUT REQUIRED]` |
| API-4 | OpenRouter/Gemini model IDs, token volumes, bills, and Ollama cutover choice | External workflow unknown | `[OWNER INPUT REQUIRED]` |
| DATA-1 | Authoritative S&P 500 constituent source and rebalance-history policy | Current CSV is a snapshot | `[OWNER INPUT REQUIRED]` |
| DATA-2 | Data/API retention, caching, redistribution, and portfolio-display rights | Unverified | `[OWNER INPUT REQUIRED]` |
| DATA-3 | Raw retention and deletion policy | Preserve raw; no autonomous deletion | `[OWNER INPUT REQUIRED]` |
| MODEL-1 | Prediction-time contract | `PRE_MARKET_T` recommended | `[OWNER INPUT REQUIRED]` |
| MODEL-2 | Primary target, baseline, evaluation metric, minimum lift, and embargo | No success claim | `[OWNER INPUT REQUIRED]` |
| HOST-1 | MP9 access alias, user, sudo boundary, deploy path, and maintenance window | `/opt/ai_sp500` is only a target path | `[OWNER INPUT REQUIRED]` |
| HOST-2 | TrueNAS read/change permissions and verified resource baseline | No changes | `[OWNER INPUT REQUIRED]` |
| OPS-1 | PostgreSQL backup owner, RPO, RTO, restore test, retention | No live migration | `[OWNER INPUT REQUIRED]` |
| OPS-2 | Alert destination and escalation order | Report in the active task only | `[OWNER INPUT REQUIRED]` |
| OPS-3 | n8n export/versioning and rollback method | No change | `[OWNER INPUT REQUIRED]` |
| REG-1 | Docker registry, repository visibility, immutable tag/digest and signing policy | Local images only | `[OWNER INPUT REQUIRED]` |
| SECRET-1 | Secret manager and references agents may use | Never read/display values by default | `[OWNER INPUT REQUIRED]` |
| QA-1 | Required coverage, performance, data-quality, and review thresholds | At least 80% coverage on new core modules; all critical paths tested | `[OWNER INPUT REQUIRED]` |

## 8. Monthly cost model

This is a planning model, not a live bill. Actual billing requires an owner-approved read-only
Cost Explorer/CUR and service-usage audit. Prices and FX were checked on 2026-08-28; refresh
them before a purchase or deployment. The ECB reference rate was EUR 1 = USD 1.1643.

### 8.1 Target AWS steady state

Assumptions: 5 GB stored, approximately 10,900 optimized ingestion PUTs/month, 15 GB Athena
scan/month, one daily state machine, no warm EMR capacity, no backfill, no internet egress,
and low error-only log volume.

| Component | Planning usage | Approximate monthly cost before VAT |
|---|---:|---:|
| S3 storage | 5 GB Standard-equivalent | USD 0.12 |
| S3 writes and other requests | ~10.9k PUT plus low reads/listing | USD 0.06-0.10 |
| Athena | 15 GB scanned at USD 5/TB | USD 0.08 |
| Glue Catalog | Far below 1M objects and 1M accesses | USD 0 |
| Step Functions | ~510 successful transitions; below 4,000/month | USD 0 |
| Lambda | Small daily/weekly batches; below the perpetual allowance | USD 0 |
| EventBridge Scheduler and SNS | Tens of invocations/deliveries | USD 0 |
| CloudWatch | Error-only; free allowance if available, otherwise usage-based | USD 0-0.50 |
| EMR Serverless | No job | USD 0 |
| **Expected AWS subtotal** | | **USD 0.25-0.75 (~EUR 0.21-0.64)** |

Keep the operational AWS envelope at **EUR 1-2/month** until observed usage proves a tighter
number. The Terraform USD 5 budget is an alert, not a hard cap; it updates after spend occurs.
The 1 GiB Athena limit caps one query, not a day or month, and EMR's capacity ceiling does not
cap job duration.

At the Terraform maximum of 8 vCPU and 32 GB, EMR Serverless is approximately USD 0.61 per
fully utilized hour using the current public rates. Planning examples: about USD 0.05 for five
minutes, USD 0.30 for 30 minutes, or USD 0.61 for one hour, plus logs and S3 operations. Set a
job runtime timeout before unattended use.

Most raw API objects are likely below 128 KB. S3 does not transition objects below 128 KB by
default, so the current raw-to-Glacier-Instant-Retrieval rule will not archive many of them.
This is usually economical because per-object transition charges can exceed small-object
storage savings.

### 8.2 Data APIs and external AI

| Service | Current planning fact | Approximate monthly cost before VAT |
|---|---|---:|
| Alpha Vantage free | 25 calls/day; cannot support the design | USD 0 |
| Alpha Vantage 75 RPM monthly | Matches the target configuration | USD 49.99 (~EUR 42.94) |
| Alpha Vantage 75 RPM annual | Two months off, annualized | ~EUR 35.78/month |
| API Ninjas | Free and Developer tiers disallow retained/cached data; current code writes a CSV | Replace the source or obtain permission; the first currently listed storage-capable tier is Business at USD 149 monthly (~EUR 127.97), or USD 99/month equivalent on annual billing |
| OpenRouter/Gemini | Still named by the external n8n workflow | `[OWNER INPUT REQUIRED: actual bill and model/token usage]` |
| Local Ollama | No API subscription; currently not proven active for this workflow | Electricity only |

For a personal consumer in mainland Portugal, the normal VAT rate is 23% when it applies.
Confirm each supplier's invoice and the owner's tax status rather than assuming. Alpha Vantage
monthly would be approximately EUR 52.81 if 23% is added; annualized, approximately EUR 44.01.

### 8.3 Local electricity

Use measured wall power, not TDP:

```text
monthly electricity EUR = average watts * 24 * uptime_days / 1000 * all_in_EUR_per_kWh
```

Illustration only, at EUR 0.22/kWh and 30 days:

| Incremental average power | Energy | Monthly cost |
|---:|---:|---:|
| 10 W | 7.2 kWh | EUR 1.58 |
| 20 W | 14.4 kWh | EUR 3.17 |
| 30 W | 21.6 kWh | EUR 4.75 |

If the MP9 and TrueNAS remain on for unrelated services, report both marginal project cost
and an explicitly defined allocated share. Do not charge the entire TrueNAS baseline to this
project without the owner's allocation rule.

### 8.4 Practical total scenarios

| Scenario | Included | Expected monthly total |
|---|---|---:|
| Development/scaffold dormant | No recurring job; existing shared hardware | Unknown actual S3 storage, otherwise approximately EUR 0 incremental |
| Target AWS only | Serverless lakehouse, no paid API or allocated hardware | EUR 0.21-0.64 before VAT; budget EUR 1-2 |
| Target with Alpha monthly and MP9 at 10-30 W | AWS + USD 49.99 Alpha + illustrative power | ~EUR 44.7-48.3 before VAT |
| Same, with 23% supplier VAT where applicable | AWS + Alpha + illustrative power | ~EUR 54.7-58.4 |
| Target with annual Alpha equivalent | AWS + annualized Alpha + illustrative power | ~EUR 37.6-41.2 before VAT |

API Ninjas storage rights would add about EUR 127.97/month before VAT at its current monthly
Business list price, so replacing that one manually refreshed feed is the economic default.
Add OpenRouter/Gemini, domains, paid GitHub/Docker features, hardware depreciation, backups,
or egress only if the owner confirms they are project-specific.

Current legacy ingestion is not the target cost shape. At one request every 15 seconds and an
unbounded outer loop, it can approach 172,800 API calls/S3 PUTs per 30-day month. The S3 PUT
portion alone is roughly USD 0.86 before response storage, versioning, or log growth, and the
job can continuously upload quota/error payloads. Never run it unattended.

Pricing references:

- [Amazon S3 pricing](https://aws.amazon.com/s3/pricing/)
- [Amazon Athena pricing](https://aws.amazon.com/athena/pricing/)
- [AWS Glue pricing](https://aws.amazon.com/glue/pricing/)
- [AWS Step Functions pricing](https://aws.amazon.com/step-functions/pricing/)
- [AWS Lambda pricing](https://aws.amazon.com/lambda/pricing/)
- [Amazon EventBridge pricing](https://aws.amazon.com/eventbridge/pricing/)
- [Amazon EMR pricing](https://aws.amazon.com/emr/pricing/)
- [Amazon CloudWatch pricing](https://aws.amazon.com/cloudwatch/pricing/)
- [Alpha Vantage premium](https://www.alphavantage.co/premium/)
- [API Ninjas pricing](https://api-ninjas.com/pricing)
- [ECB EUR/USD reference rates](https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/index.en.html)
- [Portuguese VAT Code, Article 18](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/codigos_tributarios/civa_rep/Pages/iva18.aspx)

## 9. Permission matrix

### Autonomous without further approval

- Read repository files and inspect local Git state.
- Create or use a scoped `codex/<task-slug>` branch after rechecking the worktree.
- Edit scoped source, tests, non-secret examples, ADRs, and documentation.
- Run deterministic local tests/static checks against fixtures, mocks, and scratch resources.
- Produce a Terraform plan only after CLOUD-1 through CLOUD-4 identify the account and state.
- Update cost-impact notes using current primary pricing sources.
- Make narrow, meaningful commits only if GIT-2 explicitly authorizes commits.

### Explicit approval required

- Any live HTTP/API request, email, webhook, LLM call, data scrape, or backfill.
- Dependency download, lock-file regeneration, or major dependency version change.
- AWS plan against an unidentified account; any apply, import, state operation, replacement,
  deletion, schedule enablement, or paid compute job.
- SQL migration or data mutation outside an ephemeral scratch database.
- SSH, sudo, systemd, firewall, Docker Compose, TrueNAS, n8n, or Ollama mutation.
- Docker registry push/delete, Git push, PR creation, merge, tag, release, or force-push.
- Credential rotation, Git history rewrite, published-artifact deletion, or notification to a
  third party.
- Any operation projected to exceed COST-1, COST-2, or COST-3.

### Always prohibited

- Print, commit, cache, embed, transmit, or log credential values.
- Read ignored `.env` files merely because they exist; use named secret references only after
  authorization and never return their values.
- Broad-stage a dirty worktree or overwrite unrelated owner changes.
- Use destructive Git/file commands to discard work.
- Mutate or delete `raw/`, weaken its access policy, or bypass replay/audit history.
- Waive DQ or lookahead gates to make a run green.
- Disable cost/security/retention controls without an approved replacement.
- Run an unbounded loop, unlimited retry, or paid job without a runtime/call ceiling.
- Automate trading or portray research output as investment advice.

## 10. Git and change management

- Recheck `git status --short --branch` before editing, staging, committing, or reporting.
- Existing modified/untracked files belong to the owner. Preserve them and stage explicit
  paths only; never use `git add .` in a dirty worktree.
- Default branch name for new work: `codex/<task-slug>`.
- One meaningful concern per commit: security baseline, dependency/test baseline, edge stage,
  cloud resource, schema/model, or documentation.
- A commit message must state the outcome, not the activity.
- Do not amend, rebase, force-push, or rewrite history without explicit approval.
- Do not claim a release exists until a tag, immutable artifact digest, deployment evidence,
  and rollback reference have been verified.

## 11. Engineering and data invariants

- Python runtime: 3.12, aligned across Poetry, Docker, CI, Mac ARM64, and MP9 AMD64.
- HTTP, AWS, PostgreSQL, clock, filesystem, and LLM calls must be injectable and mocked.
- Every request has connect/read timeouts, bounded retries with jitter, and redacted logging.
- Rate limiting is configuration-driven and validated against the paid plan.
- No `while True` worker without a scheduler-controlled single-run mode and explicit bound.
- Every run has a `run_id`, source, status, start/end, duration, row/object counts, bytes,
  watermark, code SHA, and sanitized error.
- Raw keys are collision-safe and replayable; raw payloads are never rewritten in place.
- Silver writes are order-safe using source availability/fetch time and natural keys.
- Bronze partitions and all feature sources carry event, publication, ingestion, and/or fetch
  time needed to enforce the chosen prediction cutoff.
- Gold features and labels remain separate. Labels may look forward; features may not.
- A DQ batch must fail on missing required partitions, zero unexpected row counts, duplicate
  keys, invalid bounds/types, staleness, and feature availability after cutoff.
- Train/test splits are chronological, walk-forward, embargoed, and compared with a naive
  baseline. Report uncertainty and costs; never optimize on the final test window.
- Preserve `llm_model`, exact model digest/version, prompt hash, schema version, and raw source
  references for every LLM-derived row.
- New data providers require documented rights for caching, retention, model use, and display.

## 12. Standard validation and definition of done

The repository does not pass this target baseline yet. An implementation is not complete
until relevant commands succeed in the intended Python 3.12 environment:

```bash
poetry check --lock
poetry run ruff check .
poetry run pytest
terraform fmt -check -recursive infra/terraform
terraform -chdir=infra/terraform validate
jq empty infra/stepfunctions/daily_pipeline.asl.json
bash -n infra/scripts/athena_apply.sh
```

Also require, when relevant:

- deterministic unit tests with no live network/cloud/database dependency;
- a final secret scan of source, diff, logs, build context, and built image layers;
- Docker builds for the actual target architecture, pinned by digest;
- Compose rendering with non-secret test values;
- a reviewed Terraform saved plan with zero unapproved replacements/deletes;
- scratch execution of SQL before production data;
- canary input and an idempotent rerun;
- failure-path proof: a red DQ check blocks Gold and sends only sanitized alerts;
- cost estimate before live execution and observed cost/usage after it;
- updated README/ADR wording that explicitly distinguishes coded, locally tested,
  live-tested, deployed, and scheduled states;
- narrow staging and a final diff that preserves owner changes.

Definition of done for live deployment additionally requires:

1. all blocking owner inputs completed;
2. secrets rotated and prior artifacts assessed;
3. backups and rollback tested;
4. exact account/host/environment verified immediately before the change;
5. schedules disabled during deployment and smoke testing;
6. monitoring, budget notification, and alert delivery proven;
7. owner approval to enable each recurring schedule.

## 13. Incident and rollback rules

Stop immediately on credential exposure, wrong account/host, unexpected replacement/deletion,
cost-cap risk, missing backup, ambiguous live state, DQ failure, or possible lookahead.

- Retry a live or paid operation at most twice, only when the failure is understood and the
  projected total remains below the approved cap.
- Preserve sanitized logs, run/query/execution IDs, plan files, timestamps, and affected data
  locations. Never preserve a secret in the incident report.
- Code rollback: revert only the agent's scoped commit; never discard owner changes.
- Container rollback: redeploy the previous verified immutable digest.
- Terraform rollback: inspect state and apply reviewed corrective configuration. Never run an
  automatic destroy or manual state surgery.
- Database rollback: use the pre-reviewed migration rollback and verified backup.
- Scheduler containment: disable only the newly introduced schedule/timer after confirming
  the exact environment; preserve the failed execution.
- Secret incident: revoke/rotate first, then rebuild/redeploy artifacts; history rewrite is a
  separate owner-approved action.
- DQ incident: quarantine derived output and halt promotion; never bypass the failed gate.
- Report scope, environment, possible cost, preserved evidence, and safest next action.

## 14. Agent report format

Every handoff must state:

1. outcome achieved;
2. files/resources changed;
3. implemented versus planned/deferred behavior;
4. validations run and exact failures/skips;
5. cost impact and whether it is measured or estimated;
6. security/data/licensing impact;
7. remaining owner inputs or approvals;
8. rollback method for live changes.

Never use success language for unexecuted SQL, unapplied Terraform, an unrun Spark job, an
unverified model, or a scheduled pipeline whose alert path has not been tested.
