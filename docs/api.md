# API

`from prometheus import Registry, DEFAULT_BUCKETS, go_float`

| Call | Does |
|---|---|
| `Registry()` | Holds every metric, in registration order. |
| `r.counter(name, help, labels=[]) -> Int` | Metric id. A trailing `_total` in `name` is dropped; samples are `name_total`. Duplicate names raise. |
| `r.gauge(...)`, `r.summary(...)` | Same shape. A summary exports `_count` and `_sum` (no quantiles, as prometheus_client). |
| `r.histogram(name, help, labels=[], buckets=DEFAULT_BUCKETS)` | `+Inf` appended if missing; unsorted buckets raise. |
| `r.child(metric, *label_values) -> Int` | The labelled child (like `.labels(...)`), created on first use. Wrong count raises. An unlabelled metric's child is `r.child(metric)`. |
| `r.inc(child, v=1.0)` | Counter or gauge; negative raises on a counter. |
| `r.dec(child, v=1.0)`, `r.set(child, v)` | Gauge. |
| `r.observe(metric, child, v)` | Histogram (first bucket with `v <= bound`) or summary. |
| `r.exposition() -> String` | The text format, `# HELP` / `# TYPE` per metric, labels sorted by name. |
| `go_float(x) -> String` | prometheus_client `floatToGoString`. |

Rules, all as prometheus_client 0.26 with classic name validation: an empty or invalid metric name, an invalid or `__`-prefixed label name, `le` on a histogram and `quantile` on a summary raise at registration; a metric whose samples (`x`, `x_total`, `x_bucket`, `x_sum`, `x_count`, `x_created`) overlap an earlier one raises `Duplicated timeseries in CollectorRegistry: <sample>`. Buckets: sorted (equal neighbours allowed), `+Inf` appended, fewer than two raise. `inc` is for counters and gauges, `dec`/`set` for gauges, `observe` for histograms and summaries (and the child must belong to that metric); anything else raises. A histogram's `_count` is its bucket total (a NaN observation lands in no bucket), and `_sum` is printed only when the first bound is >= 0.
