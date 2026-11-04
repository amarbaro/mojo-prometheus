---
name: mojo-prometheus
description: "Expose Prometheus metrics (counters, gauges, histograms, summaries with labels) from a Mojo program with mojo-prometheus; output is byte-identical with prometheus_client. Use when a Mojo service needs /metrics."
---

# mojo-prometheus

```mojo
from prometheus import Registry
var r = Registry()
var lat = r.histogram("infer_seconds", "Inference latency", ["model"])
var c = r.child(lat, "qwen3")      # keep this id; child() hashes, the hot path should not
r.observe(lat, c, dt)
var text = r.exposition()          # HTTP 200, Content-Type: text/plain; version=0.0.4
```

- Counters: name without `_total` (it is added). Negative `inc` raises.
- No `_created` series and no summary quantiles (prometheus_client has none either).
- One `Registry` per process; it is not thread-safe: update from one thread or guard it.

Gate: `scripts/ci.sh` (prometheus_client oracle, mutants, api, quickstart).
