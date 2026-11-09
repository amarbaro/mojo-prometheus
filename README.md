# mojo-prometheus

<!-- badges -->
[![ci](https://github.com/amarbaro/mojo-prometheus/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/amarbaro/mojo-prometheus/actions/workflows/ci.yml) [![latest release](https://img.shields.io/github/v/release/amarbaro/mojo-prometheus)](https://github.com/amarbaro/mojo-prometheus/releases/latest) [![license](https://img.shields.io/github/license/amarbaro/mojo-prometheus)](https://github.com/amarbaro/mojo-prometheus/blob/main/LICENSE) [![checks](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/amarbaro/mojo-prometheus/badges/checks.json)](https://github.com/amarbaro/mojo-prometheus/actions/workflows/ci.yml)
<!-- /badges -->

Prometheus metrics for Mojo: counters, gauges, histograms and summaries with labels, and the `/metrics` text exposition (format 0.0.4) byte-identical with Python's `prometheus_client`. 272 lines of code (`mojo-loc`, without the vendored pyformat).

Install: `pixi workspace channel add https://conda.modular.com/max https://prefix.dev/amarbaro/amarbaro`, then `pixi add mojo-prometheus` (import `prometheus`). From source: `git clone https://github.com/amarbaro/mojo-prometheus`, then `mojo run -I mojo-prometheus/src app.mojo`.
Toolchains: Mojo 1.2 stable, and the nightly 1.3.0.dev2026110805 in the weekly [mojo-libs](https://github.com/amarbaro/mojo-libs) matrix (36 libraries on stable, 35 on nightly).

```mojo
from prometheus import Registry


def main() raises:
    var r = Registry()
    var req = r.counter("http_requests", "HTTP requests", ["method", "code"])
    var lat = r.histogram("request_seconds", "Request latency")
    r.inc(r.child(req, "GET", "200"))          # child() = .labels(...), cache the id on hot paths
    r.observe(lat, r.child(lat), 0.042)
    print(r.exposition())                      # serve this as text/plain; version=0.0.4
```

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

**Checked against prometheus_client 0.26.0** (created series off): a 436-op script (9 metrics, label values with quotes, backslashes, newlines and Unicode, custom and default buckets, sample-name duplicates, name and label validation, bucket rules, a negative-bucket histogram fed NaN, wrong-kind updates, a negative counter increment) replayed by both, 6 exposition snapshots and 13 error rows byte-identical, plus Go-style float formatting (`1.234567e+06`, `+Inf`, `NaN`), each scenario twice. 9 of 9 mutants caught. Builds and passes on Mojo 1.2.0 and the 1.3 nightly.

**Limits:** names follow prometheus_client's classic validation (`PROMETHEUS_LEGACY_NAME_VALIDATION=true`): metric names `[a-zA-Z_:][a-zA-Z0-9_:]*`, label names `[a-zA-Z_][a-zA-Z0-9_]*`, no `__` labels. The default UTF-8 names of prometheus_client 0.26 (quoted in the output) are not supported.

**Speed** (1,000 labelled children, 7800X3D, pinned core, load average 6.5): `inc` 7 ns (kind-checked), `observe` 25 ns, exposition 3.8 ms; prometheus_client 255 ns, 625 ns and 79 ms.

Floats print exactly as Python's `repr`: Mojo 1.2's own float printing is not round-trip safe, so the vendored `src/pyformat` (mojo-pyformat 0.2) supplies `py_repr`.

- API: [docs/api.md](docs/api.md) · design: [docs/design.md](docs/design.md) · agent skill: [skills/mojo-prometheus/SKILL.md](skills/mojo-prometheus/SKILL.md)
- License: Apache-2.0
