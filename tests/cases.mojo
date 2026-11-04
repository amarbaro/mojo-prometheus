# The Mojo side of tools/oracle.py: `cases SCENARIO DIR` prints the same lines.
from std.sys import argv
from prometheus import Registry, go_float


def unhex(h: StringSlice[_]) raises -> String:
    var b = h.as_bytes()
    var out = List[UInt8]()
    for i in range(0, len(b), 2):
        var v = 0
        for k in range(2):
            var c = Int(b[i + k])
            v = v * 16 + (c - 48 if c <= 57 else c - 87)
        out.append(UInt8(v))
    return String(unsafe_from_utf8=out)


def main() raises:
    var c = argv()[1]
    if c == "floats":
        var xs: List[Float64] = [0.0, 1.0, -1.0, 0.1, 1e16, 1e15, 1234567.0, 12345678.9, 123456789.0, 1e-7, 1e22, 0.30000000000000004, 1.5e300, 5e-324, 100000000.0, 9999999.999, Float64.MAX * 2, -Float64.MAX * 2, Float64.MAX * 2 - Float64.MAX * 2]
        for x in xs:
            print(x, go_float(x))
        return
    var reg = Registry()
    var ms = List[Int]()
    var kinds = List[String]()
    var n = 0
    with open("tests/data/ops.txt", "r") as h:
        var text = h.read()
        var lines = text.split("\n")
        for li in range(len(lines) - 1):
            var f = lines[li].split("\t")
            var op = String(f[0])
            try:
                if op == "counter" or op == "gauge" or op == "summary" or op == "histogram":
                    var labels = List[String]()
                    for x in f[3].split(","):
                        if x:
                            labels.append(String(x))
                    var name = String(f[1])
                    var help = unhex(f[2])
                    ms.append(-1)  # the slot exists even when registration fails, on both sides
                    kinds.append(op)
                    var m: Int
                    if op == "counter":
                        m = reg.counter(name, help, labels)
                    elif op == "gauge":
                        m = reg.gauge(name, help, labels)
                    elif op == "summary":
                        m = reg.summary(name, help, labels)
                    elif f[4]:
                        var b = List[Float64]()
                        if String(f[4]) != "-":
                            for x in f[4].split(","):
                                b.append(Float64.MAX * 2 if String(x) == "inf" else atof(x))
                        m = reg.histogram(name, help, labels, b)
                    else:
                        m = reg.histogram(name, help, labels)
                    ms[len(ms) - 1] = m
                elif op == "expo":
                    print(reg.exposition(), end="")
                    print("---")
                else:
                    var mi = Int(atol(f[1]))
                    var m = ms[mi]
                    if m < 0:
                        raise Error("metric slot failed")
                    var vals = List[String]()
                    for x in f[3].split(","):
                        if x:
                            vals.append(unhex(x[byte=1:]))
                    var ch: Int
                    if len(vals) == 0:
                        ch = reg.child(m)
                    elif len(vals) == 1:
                        ch = reg.child(m, vals[0])
                    else:
                        ch = reg.child(m, vals[0], vals[1])
                    var v = Float64.MAX * 2 - Float64.MAX * 2 if f[2] == "nan" else atof(f[2])
                    if op == "inc":
                        reg.inc(ch, v)
                    elif op == "dec":
                        reg.dec(ch, v)
                    elif op == "set":
                        reg.set(ch, v)
                    else:
                        reg.observe(m, ch, v)
            except:
                print("ERR", li, op)
