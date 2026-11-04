# Every public call once, plus the README example.
from prometheus import Registry, go_float


def check(ok: Bool, what: String) raises:
    if not ok:
        raise Error("FAIL api: " + what)


def main() raises:
    var r = Registry()
    var req = r.counter("http_requests", "Requests", ["method"])
    var up = r.gauge("up", "Up")
    var lat = r.histogram("latency_seconds", "Latency", [], [0.1, 1.0])
    var sz = r.summary("size_bytes", "Size")
    r.inc(r.child(req, "GET"))
    r.inc(r.child(req, "GET"), 2.0)
    r.set(r.child(up), 1.0)
    r.dec(r.child(up), 0.5)
    r.observe(lat, r.child(lat), 0.5)
    r.observe(sz, r.child(sz), 10.0)
    var t = r.exposition()
    check('http_requests_total{method="GET"} 3.0' in t, "counter")
    check("up 0.5" in t, "gauge")
    check('latency_seconds_bucket{le="1.0"} 1.0' in t and 'le="+Inf"' in t, "histogram")
    check("size_bytes_sum 10.0" in t, "summary")
    var raised = False
    try:
        r.inc(r.child(req, "GET"), -1.0)
    except:
        raised = True
    check(raised, "negative counter inc raises")
    check(go_float(1234567.0) == "1.234567e+06", "go_float")
    print("PASS api")
