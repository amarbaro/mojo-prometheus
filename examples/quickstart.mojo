# Count requests by method, time them, print the /metrics text.
from prometheus import Registry


def main() raises:
    var r = Registry()
    var req = r.counter("http_requests", "HTTP requests", ["method", "code"])
    var lat = r.histogram("request_seconds", "Request latency")
    for i in range(10):
        r.inc(r.child(req, "GET" if i % 3 else "POST", "200"))
        r.observe(lat, r.child(lat), 0.01 * Float64(i))
    print(r.exposition(), end="")
