# TrueNAS Scale — memory and storage tuning

Node: `truenas.lan` · i7-6700 (4C/8T) · 16 GB DDR3 · RTX 3060 12 GB · `StorageOne` at 81%

**None of this is required by the AI_SP500 pipeline** — v0.3 adds zero resident memory and zero
bytes to the pool. It is here because the node is at its limit for reasons that predate the
pipeline, and fixing that is the largest single improvement available.

---

## 0. Measure first

Never cap a cache below its working set. Capture a baseline before changing anything:

```bash
arc_summary | head -40
```

```bash
docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}'
```

```bash
free -h && zpool list -o name,capacity,fragmentation,health
```

Record `ARC Size` (current vs target), the top five containers by memory, and pool
`capacity`/`fragmentation`. You need these numbers again after each change — a tuning
step you cannot measure is a tuning step you cannot defend.

---

## 1. Cap MongoDB's WiredTiger cache · highest expected win

WiredTiger defaults to `max(50% × (RAM − 1 GB), 256 MB)` — on 16 GB that reserves
**~7.5 GB**. It grows into that ceiling opportunistically and only yields under pressure,
which is exactly the memory-pressure churn this node is showing.

Check what it is actually holding:

```bash
docker exec -it mongodb mongosh --quiet --eval 'JSON.stringify(db.serverStatus().wiredTiger.cache["bytes currently in the cache"])'
```

In the MongoDB service definition in Dockge, add the cache cap:

```yaml
services:
  mongodb:
    image: mongo:7
    command: ["mongod", "--wiredTigerCacheSizeGB", "1"]
    # ... rest of your existing definition unchanged
    deploy:
      resources:
        limits:
          memory: 1536M
```

Then recreate just that service:

```bash
docker compose up -d --force-recreate mongodb
```

**Sizing.** 1 GB suits a working set under a few GB. If `bytes currently in the cache` was
already above 1 GB and queries slow noticeably afterwards, step up to 2 GB. The `memory`
limit is deliberately set above the cache size — WiredTiger needs headroom beyond the cache
for connections and sort buffers, and a limit equal to the cache size will get the container
OOM-killed.

---

## 2. Cap ZFS ARC

TrueNAS SCALE targets roughly 50% of RAM for ARC — **~8 GB here**. ARC is genuinely useful
and it *does* yield under pressure, but on a node this oversubscribed the constant reclaim
cycle costs more than the cache returns.

Immediate effect, lost on reboot — use this to test the impact before committing:

```bash
echo 5368709120 | sudo tee /sys/module/zfs/parameters/zfs_arc_max
```

To persist: **System Settings → Advanced → Init/Shutdown Scripts → Add**, Type `Command`,
When `Pre Init`:

```bash
echo 5368709120 > /sys/module/zfs/parameters/zfs_arc_max
```

> Use the TrueNAS UI for persistence rather than `/etc/modprobe.d/zfs.conf` — SCALE's
> immutable-root updates do not preserve hand-edited files there.

**Verify, then judge:**

```bash
arc_summary | grep -E 'ARC size|Target size|Hit ratio|MFU|MRU'
```

If the hit ratio falls below ~85% or Jellyfin/Immich browsing feels slower, raise it back to
6 GB. **ARC starvation hurts pool performance more than the freed RAM helps** — and on a pool
already at 81%, metadata cache misses are expensive. This is a tradeoff, not a free win.

Sizes: 5 GB = `5368709120`, 6 GB = `6442450944`, 8 GB = `8589934592`.

---

## 3. Migrate three stateless UIs to the MP9

Each of these is a web frontend that talks to a backend over HTTP. None owns data, so
migration is a compose-file move plus a bookmark change — and it is reversible in minutes.

| Service | Backend it talks to | After migration |
|---|---|---|
| **pgAdmin** | Postgres | Add both `truenas.lan:5432` and `mp9.lan:5432` as servers |
| **Mongo-Express** | MongoDB | `ME_CONFIG_MONGODB_SERVER=truenas.lan` |
| **Open-WebUI** | Ollama | `OLLAMA_BASE_URL=http://truenas.lan:11434` — **GPU stays here** |

Definitions are in [`../mp9/docker-compose.yml`](../mp9/docker-compose.yml) under the
`migrated` profile. Bring them up on the MP9, confirm each works, and only then remove them
from the TrueNAS stack.

For Open-WebUI, ensure Ollama is reachable off-host. TrueNAS app deployments usually bind
`0.0.0.0` already; if not, set `OLLAMA_HOST=0.0.0.0:11434` and confirm:

```bash
curl -s http://truenas.lan:11434/api/tags | head -c 200
```

**Do not migrate** MongoDB, Postgres, Jellyfin, Immich, Ollama or n8n. Databases are the
riskiest thing to move and capping their caches buys more; the rest need the GPU or data
locality.

---

## 4. Pool health at 81%

Past ~80% OpenZFS switches its block allocator from first-fit to best-fit. Write latency and
fragmentation rise from here and the curve steepens toward 90%.

The pipeline contributes **nothing** — raw data lives in S3, the warehouse lives on the MP9.
But the pool still needs relief, and it will not come from this project.

Find the actual consumers:

```bash
zfs list -o space -s used -r StorageOne | head -25
```

Snapshots are the usual surprise — old snapshots pin freed blocks and are invisible in a
normal `du`:

```bash
zfs list -t snapshot -o name,used -s used -r StorageOne | tail -25
```

If `USEDSNAP` is large on a dataset, review the retention policy on that periodic snapshot
task. Expect Jellyfin media and Immich originals to dominate `USEDDS`.

Getting back under 80% is a measurable performance change, not housekeeping.

---

## 5. Dataset properties for database workloads

Applies to whatever dataset backs the *existing* TrueNAS Postgres. The analytics Postgres
lives on the MP9 and is not affected.

```bash
zfs set recordsize=16K   StorageOne/apps/postgres
zfs set compression=lz4  StorageOne/apps/postgres
zfs set atime=off        StorageOne/apps/postgres
```

- `recordsize=16K` matches Postgres's 8 KB pages closely enough to avoid read amplification;
  the 128 K default forces a 128 K read for an 8 K page.
- `lz4` is effectively free on modern CPUs and reduces both space and I/O.
- `atime=off` removes a metadata write on every read.

**`recordsize` applies to newly written blocks only.** Existing data keeps its old record
size until rewritten, so the benefit arrives gradually — or immediately if you dump and
restore the database.

---

## 6. Verification

After Phase A, re-run the baseline commands. A reasonable target:

| Metric | Before | Target |
|---|---|---|
| `free -h` available | < 1 GB | > 4 GB |
| ARC size | ~8 GB | ~5 GB |
| MongoDB RSS | up to 7.5 GB | ~1.2 GB |
| ARC hit ratio | — | still > 85% |

If the hit ratio dropped below 85%, raise `zfs_arc_max` back to 6 GB and re-measure. The
goal is headroom, not the smallest possible cache.
