"""Prometheus metrics: counter, gauge, histogram, summary with labels, and the text exposition format
(0.0.4) byte-identical with prometheus_client.generate_latest (created series disabled)."""
from std.collections import Dict
from std.math import isnan, isinf
from pyformat import py_repr

comptime COUNTER = 0
comptime GAUGE = 1
comptime HISTOGRAM = 2
comptime SUMMARY = 3
comptime DEFAULT_BUCKETS: List[Float64] = [0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1.0, 2.5, 5.0, 7.5, 10.0]
comptime _TYPES: List[String] = ["counter", "gauge", "histogram", "summary"]


def _go_into(d: Float64, mut out: String):
    """prometheus_client floatToGoString, written straight into out; whole numbers skip every temporary."""
    if isnan(d):
        out += "NaN"
    elif isinf(d):
        out += "+Inf" if d > 0 else "-Inf"
    elif abs(d) < 1e6 and d == Float64(Int(d)) and not (d == 0 and 1.0 / d < 0):
        out.write(Int(d), ".0")
    else:
        var s = py_repr(d)
        var dot = s.find(".")
        if d > 0 and dot > 6:
            var m = String(s[byte=0:1]) + "." + String(s[byte=1:dot]) + String(s[byte = dot + 1 :])
            var bb = m.as_bytes()
            var e = len(bb)
            while e > 0 and (bb[e - 1] == 48 or bb[e - 1] == 46):
                e -= 1
            var x = dot - 1
            out += m[byte=0:e]
            out += "e+0" if x < 10 else "e+"
            out.write(x)
        else:
            out += s


def go_float(d: Float64) -> String:
    """prometheus_client floatToGoString: Python repr, +Inf/-Inf/NaN, Go-style exponent above 1e6."""
    var out = String()
    _go_into(d, out)
    return out^


def _name_ok(n: StringSlice[_], colon: Bool) -> Bool:
    """`[a-zA-Z_:][a-zA-Z0-9_:]*` (metric) or `[a-zA-Z_][a-zA-Z0-9_]*` (label): prometheus_client legacy names."""
    var b = n.as_bytes()
    if len(b) == 0:
        return False
    for i in range(len(b)):
        var c = b[i]
        var alpha = (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95 or (colon and c == 58)
        if not (alpha or (i > 0 and c >= 48 and c <= 57)):
            return False
    return True


def _esc(s: StringSlice[_], quote: Bool, mut out: String):
    for c in s.codepoint_slices():
        if c == "\\":
            out += "\\\\"
        elif c == "\n":
            out += "\\n"
        elif quote and c == '"':
            out += '\\"'
        else:
            out += c


struct Registry(Movable):
    """All metrics in registration order. A metric id comes from counter()/gauge()/histogram()/summary();
    a child id from child(metric, label values...). Unlabeled metrics have their child at `child(m)`."""

    # per metric (struct of arrays)
    var kind: List[UInt8]
    var name: List[String]
    var help: List[String]
    var labels: List[List[String]]
    var bounds: List[List[Float64]]
    var le: List[List[String]]  # bucket bounds already rendered, once per histogram
    var children: List[List[Int]]
    # per child
    var pairs: List[List[String]]  # sorted (name, escaped value) flattened
    var ckind: List[UInt8]  # metric kind per child
    var cmetric: List[Int]  # owning metric per child
    var samples: List[String]  # every sample name registered (duplicate check, as the reference registry)
    var off: List[Int]  # into vals: histogram = buckets..., count, sum; summary = count, sum; else value
    var vals: List[Float64]
    var index: Dict[String, Int]

    def __init__(out self):
        self.kind = List[UInt8]()
        self.name = List[String]()
        self.help = List[String]()
        self.labels = List[List[String]]()
        self.bounds = List[List[Float64]]()
        self.le = List[List[String]]()
        self.children = List[List[Int]]()
        self.pairs = List[List[String]]()
        self.ckind = List[UInt8]()
        self.cmetric = List[Int]()
        self.samples = List[String]()
        self.off = List[Int]()
        self.vals = List[Float64]()
        self.index = Dict[String, Int]()

    def _add(mut self, k: Int, var name: String, help: String, labels: List[String], var bounds: List[Float64]) raises -> Int:
        if not name:
            raise Error("metric name cannot be empty")
        if not _name_ok(name, True):
            raise Error("invalid metric name ", name)
        for l in labels:
            if not _name_ok(l, False):
                raise Error("Invalid label metric name: ", l)
            if l.startswith("__"):
                raise Error("Reserved label metric name: ", l)
            if (k == HISTOGRAM and l == "le") or (k == SUMMARY and l == "quantile"):
                raise Error("Reserved label metric name: ", l)
        if k == COUNTER and name.endswith("_total"):
            var short = String(name[byte = 0 : name.byte_length() - 6])
            name = short^
        var sfx = List[String]()
        sfx.append("")
        if k == COUNTER:
            sfx.append("_total")
            sfx.append("_created")
        elif k == SUMMARY:
            for x in ["_sum", "_count", "_created"]:
                sfx.append(x)
        elif k == HISTOGRAM:
            for x in ["_bucket", "_sum", "_count", "_created"]:
                sfx.append(x)
        for x in sfx:
            var full = name + x
            for t in self.samples:
                if t == full:
                    raise Error("Duplicated timeseries in CollectorRegistry: ", full)
        for x in sfx:
            self.samples.append(name + x)
        self.kind.append(UInt8(k))
        self.name.append(name^)
        self.help.append(help.copy())
        self.labels.append(labels.copy())
        var le = List[String]()
        for x in bounds:
            le.append(go_float(x))
        self.le.append(le^)
        self.bounds.append(bounds^)
        self.children.append(List[Int]())
        var m = len(self.kind) - 1
        if len(labels) == 0:
            _ = self.child(m)
        return m

    def counter(mut self, name: String, help: String, labels: List[String] = []) raises -> Int:
        return self._add(COUNTER, name.copy(), help, labels, List[Float64]())

    def gauge(mut self, name: String, help: String, labels: List[String] = []) raises -> Int:
        return self._add(GAUGE, name.copy(), help, labels, List[Float64]())

    def summary(mut self, name: String, help: String, labels: List[String] = []) raises -> Int:
        return self._add(SUMMARY, name.copy(), help, labels, List[Float64]())

    def histogram(mut self, name: String, help: String, labels: List[String] = [], buckets: List[Float64] = materialize[DEFAULT_BUCKETS]()) raises -> Int:
        var b = buckets.copy()
        for i in range(len(b) - 1):
            if b[i] > b[i + 1]:
                raise Error("Buckets not in sorted order")
        if len(b) > 0 and not (isinf(b[len(b) - 1]) and b[len(b) - 1] > 0):
            b.append(Float64.MAX * 2)
        if len(b) < 2:
            raise Error("Must have at least two buckets")
        return self._add(HISTOGRAM, name.copy(), help, labels, b^)

    def child(mut self, m: Int, *values: String) raises -> Int:
        """The child for these label values (created on first use), like `metric.labels(...)`."""
        if m < 0 or m >= len(self.kind):
            raise Error("unknown metric id ", m)
        if len(values) != len(self.labels[m]):
            raise Error("Incorrect label count")
        var key = String(m)
        for v in values:
            key.write(":", v.byte_length(), ":", v)  # length-prefixed: no two value lists share a key
        var hit = self.index.get(key)
        if hit:
            return hit.value()
        var order = List[Int]()
        for i in range(len(values)):
            var j = 0
            while j < len(order) and self.labels[m][order[j]] < self.labels[m][i]:
                j += 1
            order.insert(j, i)
        var pr = List[String]()
        for i in order:
            var e = String()
            _esc(values[i], True, e)
            pr.append(self.labels[m][i].copy())
            pr.append(e^)
        var c = len(self.off)
        self.pairs.append(pr^)
        self.off.append(len(self.vals))
        self.ckind.append(self.kind[m])
        self.cmetric.append(m)
        var k = Int(self.kind[m])
        var n = len(self.bounds[m]) + 2 if k == HISTOGRAM else (2 if k == SUMMARY else 1)
        for _ in range(n):
            self.vals.append(0.0)
        self.children[m].append(c)
        self.index[key^] = c
        return c

    def _child(self, c: Int) raises -> Int:
        if c < 0 or c >= len(self.off):
            raise Error("unknown child id ", c)
        return Int(self.ckind[c])

    def inc(mut self, c: Int, v: Float64 = 1.0) raises:
        var k = self._child(c)
        if k != COUNTER and k != GAUGE:
            raise Error("inc: not a counter or gauge")
        if v < 0 and k == COUNTER:
            raise Error("Counters can only be incremented by non-negative amounts.")
        self.vals[self.off[c]] += v

    def dec(mut self, c: Int, v: Float64 = 1.0) raises:
        if self._child(c) != GAUGE:
            raise Error("dec: not a gauge")
        self.vals[self.off[c]] -= v

    def set(mut self, c: Int, v: Float64) raises:
        if self._child(c) != GAUGE:
            raise Error("set: not a gauge")
        self.vals[self.off[c]] = v

    def observe(mut self, m: Int, c: Int, v: Float64) raises:
        """Histogram: first bucket with v <= bound; summary: count and sum."""
        var k = self._child(c)
        if self.cmetric[c] != m:
            raise Error("observe: child ", c, " does not belong to metric ", m)
        if k != HISTOGRAM and k != SUMMARY:
            raise Error("observe: not a histogram or summary")
        var o = self.off[c]
        if Int(self.kind[m]) == HISTOGRAM:
            var nb = len(self.bounds[m])
            for i in range(nb):
                if v <= self.bounds[m][i]:
                    self.vals[o + i] += 1.0
                    break
            self.vals[o + nb] += 1.0
            self.vals[o + nb + 1] += v
        else:
            self.vals[o] += 1.0
            self.vals[o + 1] += v

    def _sample(self, mut out: String, name: String, suffix: StringSlice[_], c: Int, le: StringSlice[_], v: Float64):
        """One line, labels in name order with `le` merged in place: no copy of the child's pairs."""
        out += name
        out += suffix
        ref p = self.pairs[c]
        var n = len(p)
        if n or le:
            out += "{"
            var first = True
            var le_done = not le
            for i in range(0, n + 2, 2):
                if not le_done and (i >= n or p[i] > "le"):
                    out += "" if first else ","
                    out += 'le="'
                    out += le
                    out += '"'
                    first = False
                    le_done = True
                if i < n:
                    out += "" if first else ","
                    out += p[i]
                    out += '="'
                    out += p[i + 1]
                    out += '"'
                    first = False
            out += "}"
        out += " "
        _go_into(v, out)
        out += "\n"

    def exposition(self) -> String:
        """Text format 0.0.4, as prometheus_client.generate_latest with created series off."""
        var out = String()
        for m in range(len(self.kind)):
            var k = Int(self.kind[m])
            var nm = self.name[m] + "_total" if k == COUNTER else self.name[m].copy()
            out += "# HELP " + nm + " "
            _esc(self.help[m], False, out)
            out += "\n# TYPE " + nm + " " + materialize[_TYPES]()[k] + "\n"
            for c in self.children[m]:
                var o = self.off[c]
                if k == HISTOGRAM:
                    var acc = 0.0
                    var nb = len(self.bounds[m])
                    for i in range(nb):
                        acc += self.vals[o + i]
                        self._sample(out, nm, "_bucket", c, self.le[m][i], acc)
                    self._sample(out, nm, "_count", c, "", acc)  # the bucket total, as the reference prints it
                    if self.bounds[m][0] >= 0:
                        self._sample(out, nm, "_sum", c, "", self.vals[o + nb + 1])
                elif k == SUMMARY:
                    self._sample(out, nm, "_count", c, "", self.vals[o])
                    self._sample(out, nm, "_sum", c, "", self.vals[o + 1])
                else:
                    self._sample(out, nm, "", c, "", self.vals[o])
        return out^
