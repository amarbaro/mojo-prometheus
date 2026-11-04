"""Oracle: prometheus_client 0.26 replaying tests/data/ops.txt. `oracle.py --list`; `oracle.py NAME DIR`."""
import os, sys
os.environ["PROMETHEUS_DISABLE_CREATED_SERIES"] = "True"
os.environ["PROMETHEUS_LEGACY_NAME_VALIDATION"] = "True"  # classic names: what mojo-prometheus implements
from prometheus_client import CollectorRegistry, Counter, Gauge, Histogram, Summary, generate_latest
from prometheus_client.utils import floatToGoString
D = os.path.join(os.path.dirname(__file__), "..", "tests", "data")
def ops(_):
    reg = CollectorRegistry(); ms = []
    for n, line in enumerate(open(os.path.join(D, "ops.txt")).read().split("\n")[:-1]):
        f = line.split("\t")
        try:
            if f[0] in ("counter", "gauge", "summary", "histogram"):
                labels = [x for x in f[3].split(",") if x]
                cls = {"counter": Counter, "gauge": Gauge, "summary": Summary, "histogram": Histogram}[f[0]]
                kw = {"buckets": ([] if f[4] == "-" else [float(x) for x in f[4].split(",")])} if f[0] == "histogram" and f[4] else {}
                ms.append(None)  # the slot exists even when registration fails, on both sides
                ms[-1] = cls(f[1], bytes.fromhex(f[2]).decode(), labels, registry=reg, **kw)
            elif f[0] == "expo":
                print(generate_latest(reg).decode(), end=""); print("---")
            else:
                m = ms[int(f[1])]; vals = [bytes.fromhex(x[1:]).decode() for x in f[3].split(",") if x]
                c = m.labels(*vals) if vals else m
                getattr(c, f[0])(float(f[2]))
        except (ValueError, AttributeError, TypeError) as e:
            print("ERR", n, f[0])
def floats(_):
    for x in [0.0, 1.0, -1.0, 0.1, 1e16, 1e15, 1234567.0, 12345678.9, 123456789.0, 1e-7, 1e22, 0.30000000000000004, 1.5e300, 5e-324, 100000000.0, 9999999.999, float("inf"), float("-inf"), float("nan")]:
        print(repr(x), floatToGoString(x))
S = {"ops": ops, "floats": floats}
if sys.argv[1] == "--list": print("\n".join(S))
else: S[sys.argv[1]](sys.argv[2])
