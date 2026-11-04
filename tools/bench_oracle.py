import os, time
os.environ["PROMETHEUS_DISABLE_CREATED_SERIES"] = "True"
from prometheus_client import CollectorRegistry, Counter, Histogram, generate_latest
r = CollectorRegistry(); c = Counter("hits", "Hits", ["path"], registry=r); h = Histogram("lat", "Latency", ["path"], registry=r)
cs = [c.labels(f"/p{i}") for i in range(1000)]; hs = [h.labels(f"/p{i}") for i in range(1000)]
N = 500_000; t = time.perf_counter()
for i in range(N): cs[i % 1000].inc()
t1 = time.perf_counter()
for i in range(N): hs[i % 1000].observe((i % 97) * 0.01)
t2 = time.perf_counter()
for _ in range(5): b = generate_latest(r)
t3 = time.perf_counter()
print("python inc ns", round((t1 - t) / N * 1e9), " observe ns", round((t2 - t1) / N * 1e9), " exposition ms", round((t3 - t2) / 5 * 1e3, 1), " bytes", len(b))
