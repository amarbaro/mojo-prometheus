# Hot path: inc on a known child, observe on a 14-bucket histogram; exposition of 1,000 children.
from std.time import perf_counter_ns
from prometheus import Registry


def main() raises:
    var r = Registry()
    var c = r.counter("hits", "Hits", ["path"])
    var h = r.histogram("lat", "Latency", ["path"])
    var cs = List[Int]()
    var hs = List[Int]()
    for i in range(1000):
        cs.append(r.child(c, String("/p", i)))
        hs.append(r.child(h, String("/p", i)))
    comptime N = 5_000_000
    var t0 = perf_counter_ns()
    for i in range(N):
        r.inc(cs[i % 1000])
    var t1 = perf_counter_ns()
    for i in range(N):
        r.observe(h, hs[i % 1000], Float64(i % 97) * 0.01)
    var t2 = perf_counter_ns()
    var n = 0
    for _ in range(20):
        n += r.exposition().byte_length()
    var t3 = perf_counter_ns()
    print("inc ns", Float64(t1 - t0) / N, " observe ns", Float64(t2 - t1) / N, " exposition ms", Float64(t3 - t2) / 20e6, " bytes", n // 20)
