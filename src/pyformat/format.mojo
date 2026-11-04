# Python-exact number formatting. One exact decimal expansion of the double (base-1e9 limbs on
# the stack), then every type is a rounding of that digit string: half-to-even on the exact binary
# value, as CPython does.
from std.math import isfinite
from std.memory import bitcast
from std.bit import count_trailing_zeros
from std.collections import Array

comptime _F: UInt8 = 102  # 'f'
comptime _E: UInt8 = 101  # 'e'
comptime _G: UInt8 = 103  # 'g'
comptime _P: UInt8 = 37  # '%'
comptime _B: UInt64 = 1_000_000_000
comptime _LIMBS = 96  # 86 limbs hold the worst case, 5e-324 = 5^1074 / 10^1074
comptime _DIGITS = 800


def _mul(mut a: Array[UInt32, _LIMBS], mut n: Int, f: UInt64):
    var carry: UInt64 = 0
    for i in range(n):
        var t = UInt64(a[i]) * f + carry
        a[i] = UInt32(t % _B)
        carry = t // _B
    while carry != 0:
        a[n] = UInt32(carry % _B)
        n += 1
        carry //= _B


struct _Dec(Movable):
    """|x| as digits d[0..n) with no trailing zero: value = 0.d0d1... * 10^pt. Zero is n = 0, pt = 1."""

    var n: Int
    var pt: Int
    var d: Array[UInt8, _DIGITS]  # raw digit values 0..9

    def __init__(out self, bits: UInt64):
        self.n = 0
        self.pt = 1
        self.d = Array[UInt8, _DIGITS](uninitialized=True)
        var ex = Int((bits >> 52) & 0x7FF)
        var m = bits & 0xFFFFFFFFFFFFF
        if ex != 0:
            m |= 1 << 52
        if m == 0:
            return
        var e = (1 if ex == 0 else ex) - 1075  # |x| = m * 2^e
        if e < 0:  # fewer factors of 5: shift out the common 2s
            var tz = min(Int(count_trailing_zeros(m)), -e)
            m >>= UInt64(tz)
            e += tz
        var a = Array[UInt32, _LIMBS](uninitialized=True)
        a[0] = UInt32(m % _B)
        a[1] = UInt32(m // _B)
        var nl = 2 if a[1] != 0 else 1
        var shift = 0
        if e >= 0:
            while e > 0:
                var s = min(e, 32)
                _mul(a, nl, UInt64(1) << UInt64(s))
                e -= s
        else:
            shift = -e
            var k = shift
            while k > 0:
                var s = min(k, 13)
                var f: UInt64 = 1
                for _ in range(s):
                    f *= 5
                _mul(a, nl, f)
                k -= s
        var n = 0
        var top = a[nl - 1]
        var tmp = Array[UInt8, 10](uninitialized=True)
        var t = 0
        while top != 0:
            tmp[t] = UInt8(top % 10)
            t += 1
            top //= 10
        while t > 0:
            t -= 1
            self.d[n] = tmp[t]
            n += 1
        for i in range(nl - 2, -1, -1):
            var v = a[i]
            for j in range(8, -1, -1):
                self.d[n + j] = UInt8(v % 10)
                v //= 10
            n += 9
        self.pt = n - shift
        while self.d[n - 1] == 0:
            n -= 1
        self.n = n

    @always_inline
    def at(self, i: Int) -> UInt8:
        return self.d[i] + 48 if 0 <= i < self.n else 48

    def round_to(mut self, c: Int):
        """Keep the first c digits, half to even; c below 0 leaves zero."""
        if c >= self.n:
            return
        var up = False
        if c >= 0:
            var r = self.d[c]
            up = r > 5 or (r == 5 and (c + 1 < self.n or (c > 0 and self.d[c - 1] % 2 == 1)))
        var n = max(c, 0)
        if up:
            var i = n - 1
            while i >= 0 and self.d[i] == 9:
                i -= 1
            if i < 0:
                self.d[0] = 1
                self.pt += 1
                n = 1
            else:
                self.d[i] += 1
                n = i + 1
        else:
            while n > 0 and self.d[n - 1] == 0:
                n -= 1
        self.n = n


def _exp(mut out: List[UInt8], x: Int):
    out.append(101)
    out.append(UInt8(45 if x < 0 else 43))
    var a = abs(x)
    if a >= 100:
        out.append(UInt8(48 + a // 100))
    out.append(UInt8(48 + a // 10 % 10))
    out.append(UInt8(48 + a % 10))


def _fixed_fast(bits: UInt64, prec: Int, mut out: List[UInt8]) -> Bool:
    """f in plain 64-bit integers when m * 10^prec < 2^64 and 2^-11 <= |x| < 2^53: no digit expansion."""
    var k = 1075 - Int((bits >> 52) & 0x7FF)
    if k < 1 or k > 63 or prec > 19:
        return False
    var p: UInt64 = 1
    for _ in range(prec):
        p *= 10
    var m = (bits & 0xFFFFFFFFFFFFF) | (UInt64(1) << 52)
    if m > UInt64.MAX // p:
        return False
    var num = m * p
    var q = num >> UInt64(k)
    var r = num & ((UInt64(1) << UInt64(k)) - 1)
    var half = UInt64(1) << UInt64(k - 1)
    if r > half or (r == half and (q & 1) == 1):
        q += 1
    var rev = Array[UInt8, 24](uninitialized=True)
    var n = 0
    while q != 0 or n <= prec:  # at least one digit before the point
        rev[n] = UInt8(48 + q % 10)
        q //= 10
        n += 1
    for i in range(n - 1, -1, -1):
        out.append(rev[i])
        if i == prec and prec > 0:
            out.append(46)
    return True


def _body(x: Float64, kind: UInt8, prec_in: Int, pct: Bool) -> List[UInt8]:
    var prec = max(prec_in, 0)  # a negative precision would size a negative buffer
    var v = x * 100.0 if pct else x
    var out = List[UInt8](capacity=prec + 24)
    if v != v:
        out.extend("nan".as_bytes())
    else:
        var bits = bitcast[DType.uint64](v)
        if (bits >> 63) != 0:
            out.append(45)
        if (bits & 0x7FFFFFFFFFFFFFFF) == 0x7FF0000000000000:
            out.extend("inf".as_bytes())
        else:
            if kind == _F and _fixed_fast(bits, prec, out):
                pass
            else:
                var dec = _Dec(bits)
                if kind == _F:
                    dec.round_to(dec.pt + prec)
                    out.reserve(max(dec.pt, 1) + prec + 3)
                    if dec.pt <= 0:
                        out.append(48)
                    for i in range(dec.pt):
                        out.append(dec.at(i))
                    if prec > 0:
                        out.append(46)
                        for j in range(prec):
                            out.append(dec.at(dec.pt + j))
                elif kind == _E:
                    dec.round_to(prec + 1)
                    out.append(dec.at(0))
                    if prec > 0:
                        out.append(46)
                        for j in range(prec):
                            out.append(dec.at(1 + j))
                    _exp(out, dec.pt - 1)
                else:
                    var p = max(prec, 1)
                    dec.round_to(p)
                    var xe = dec.pt - 1
                    if -4 <= xe < p:
                        out.reserve(max(dec.pt, 1) + max(dec.n - dec.pt, 0) + 3)
                        if dec.pt <= 0:
                            out.append(48)
                        for i in range(dec.pt):
                            out.append(dec.at(i))
                        if dec.n > dec.pt:
                            out.append(46)
                            for j in range(dec.pt, dec.n):
                                out.append(dec.at(j))
                    else:
                        out.append(dec.at(0))
                        if dec.n > 1:
                            out.append(46)
                            for j in range(1, dec.n):
                                out.append(dec.at(j))
                        _exp(out, xe)
    if pct:
        out.append(37)
    return out^


def _pad(body: List[UInt8], width: Int, fill: UInt8, align: UInt8) -> String:
    var gap = width - len(body)
    if gap <= 0:
        return String(unsafe_from_utf8=body)
    var left = gap if align == 62 else (gap // 2 if align == 94 else 0)
    var out = List[UInt8](capacity=width)
    for _ in range(left):
        out.append(fill)
    out.extend(Span(body))
    for _ in range(gap - left):
        out.append(fill)
    return String(unsafe_from_utf8=out)


def _typed(x: Float64, kind: UInt8, prec: Int, width: Int, pct: Bool = False) -> String:
    return _pad(_body(x, kind, prec, pct), width, 32, 62)


def fmt_fixed(x: Float64, prec: Int, width: Int = 0) -> String:
    """format(x, f"{width}.{prec}f")"""
    return _typed(x, _F, prec, width)


def fmt_e(x: Float64, prec: Int, width: Int = 0) -> String:
    """format(x, f"{width}.{prec}e")"""
    return _typed(x, _E, prec, width)


def fmt_g(x: Float64, prec: Int, width: Int = 0) -> String:
    """format(x, f"{width}.{prec}g")"""
    return _typed(x, _G, prec, width)


def fmt_pct(x: Float64, prec: Int, width: Int = 0) -> String:
    """format(x, f"{width}.{prec}%")"""
    return _typed(x, _F, prec, width, True)


def fmt_commas(n: Int, width: Int = 0) -> String:
    """format(n, f">{width},")"""
    var u = UInt64(n) if n >= 0 else UInt64(0) - UInt64(n)
    var rev = Array[UInt8, 32](uninitialized=True)
    var k = 0
    while True:
        if k % 4 == 3:
            rev[k] = 44
            k += 1
        rev[k] = UInt8(48 + u % 10)
        k += 1
        u //= 10
        if u == 0:
            break
    var body = List[UInt8](capacity=k + 1)
    if n < 0:
        body.append(45)
    for i in range(k - 1, -1, -1):
        body.append(rev[i])
    return _pad(body, width, 32, 62)


# --- format specs: [[fill]align][width][,][.prec][type] -------------------------------------

@fieldwise_init
struct _Spec(Movable):
    var width: Int
    var prec: Int  # -1 when absent
    var fill: UInt8
    var align: UInt8  # '<' '>' '^'
    var comma: Bool
    var kind: UInt8  # 0 when absent


def _spec(s: String) raises -> _Spec:
    var b = s.as_bytes()
    var n = len(b)
    var r = _Spec(width=0, prec=-1, fill=32, align=62, comma=False, kind=0)
    var i = 0
    if n >= 2 and (b[1] == 60 or b[1] == 62 or b[1] == 94):
        r.fill = b[0]
        r.align = b[1]
        i = 2
    elif n >= 1 and (b[0] == 60 or b[0] == 62 or b[0] == 94):
        r.align = b[0]
        i = 1
    if i < n and b[i] == 48:
        raise Error("pyformat: zero padding is not supported: '" + s + "'")
    while i < n and b[i] >= 48 and b[i] <= 57:
        r.width = _digit(r.width, b[i], s)
        i += 1
    if i < n and b[i] == 44:
        r.comma = True
        i += 1
    if i < n and b[i] == 46:
        i += 1
        var start = i
        r.prec = 0
        while i < n and b[i] >= 48 and b[i] <= 57:
            r.prec = _digit(r.prec, b[i], s)
            i += 1
        if i == start:
            raise Error("pyformat: format specifier missing precision: '" + s + "'")
    if i < n:
        r.kind = b[i]
        i += 1
    if i < n:
        raise Error("pyformat: invalid or unsupported format specifier: '" + s + "'")
    return r^


def _digit(v: Int, d: UInt8, spec: String) raises -> Int:
    if v > (Int.MAX - 9) // 10:
        raise Error("pyformat: too many decimal digits in format string: '" + spec + "'")  # Python: ValueError
    return v * 10 + Int(d) - 48


def fmt(x: Float64, spec: String) raises -> String:
    """format(x, spec) for the types f, e, g and %. No precision means 6, as in Python."""
    var s = _spec(spec)
    if s.comma or not (s.kind == _F or s.kind == _E or s.kind == _G or s.kind == _P):
        raise Error("pyformat: unsupported float format specifier: '" + spec + "'")
    var p = 6 if s.prec < 0 else s.prec
    return _pad(_body(x, _F if s.kind == _P else s.kind, p, s.kind == _P), s.width, s.fill, s.align)


def fmt_int(x: Float64, spec: String) raises -> String:
    """format(int(x), spec) for a whole-number x (any int up to 1.8e308 is a double exactly).
    Spec: [[fill]align][width][,]. A non-finite x prints as Python prints a float."""
    var s = _spec(spec)
    if s.prec >= 0 or not (s.kind == 0 or s.kind == 100):
        raise Error("pyformat: unsupported int format specifier: '" + spec + "'")
    var bits = bitcast[DType.uint64](x)
    var body: List[UInt8]
    if (bits & 0x7FF0000000000000) == 0x7FF0000000000000:
        body = _body(x, _F, 0, False)
    else:
        var dec = _Dec(bits)
        if dec.n > dec.pt:
            raise Error("pyformat: fmt_int needs a whole number, got " + py_repr(x))
        body = List[UInt8](capacity=dec.pt + dec.pt // 3 + 2)
        if dec.n > 0 and (bits >> 63) != 0:
            body.append(45)
        for i in range(max(dec.pt, 1)):
            if s.comma and i > 0 and (dec.pt - i) % 3 == 0:
                body.append(44)
            body.append(dec.at(i) if dec.n > 0 else 48)
    return _pad(body, s.width, s.fill, s.align)


# sum(xs) over floats as CPython 3.12+ computes it (Neumaier compensated summation)
def py_sum(xs: List[Float64]) -> Float64:
    var total: Float64 = 0.0
    var c: Float64 = 0.0
    for x in xs:
        var t = total + x
        c += (total - t) + x if abs(total) >= abs(x) else (x - t) + total
        total = t
    return total + c if c != 0 and isfinite(c) else total  # CPython: c is dropped once the sum overflowed

def _nb(s: String, up: Bool) -> String:
    """The `d.ddde+XX` text one unit in the last digit up or down, renormalised ("" when it reaches 0)."""
    var b = s.as_bytes()
    var neg = b[0] == 45
    var epos = s.find("e")
    var digs = List[UInt8]()
    for i in range(1 if neg else 0, epos):
        if b[i] != 46:
            digs.append(b[i])
    var e = 0
    for i in range(epos + 2, len(b)):
        e = e * 10 + Int(b[i] - 48)
    if b[epos + 1] == 45:
        e = -e
    var n = len(digs)
    var k = n - 1
    if up:
        while k >= 0 and digs[k] == 57:
            digs[k] = 48
            k -= 1
        if k < 0:  # 9.99 -> 10.0: keep n digits, one more power of ten
            digs.insert(0, 49)
            _ = digs.pop()
            e += 1
        else:
            digs[k] += 1
    else:
        while k >= 0 and digs[k] == 48:
            digs[k] = 57
            k -= 1
        if k < 0:
            return ""
        digs[k] -= 1
        if digs[0] == 48:  # 1.00 -> 0.99: drop the leading zero, add a 9, one less power of ten
            if n == 1:
                return ""
            _ = digs.pop(0)
            digs.append(57)
            e -= 1
    var out = String("-") if neg else String()
    out += chr(Int(digs[0]))
    if n > 1:
        out += "."
        for i in range(1, n):
            out += chr(Int(digs[i]))
    out += "e-" if e < 0 else "e+"
    var ae = -e if e < 0 else e
    if ae < 10:
        out += "0"
    out += String(ae)
    return out^


def py_repr(x: Float64) -> String:
    """Python repr(float): the shortest digits that round-trip, fixed notation for 1e-4 <= |x| < 1e16,
    else d.ddde+XX. (Mojo's own float printing is not round-trip safe on 1.2.)"""
    if x != x:
        return "nan"
    if x == Float64.MAX * 2:
        return "inf"
    if x == -Float64.MAX * 2:
        return "-inf"
    if x == 0:
        return "-0.0" if 1.0 / x < 0 else "0.0"
    if abs(x) < 1e16 and x == Float64(Int(x)):  # whole numbers: exact, no digit search
        return String(Int(x)) + ".0"
    var s = String()
    for p in range(17):
        s = fmt_e(x, p)
        try:
            if atof(s) == x:
                break
            # the correctly rounded digits may not read back while a neighbour does (2**-24: ...062 vs ...063)
            var hit = False
            for up in [True, False]:
                var t = _nb(s, up)
                if t and atof(t) == x:
                    s = t^
                    hit = True
                    break
            if hit:
                break
        except:
            pass
    var b = s.as_bytes()
    var neg = b[0] == 45
    var epos = s.find("e")
    var digits = String()
    for i in range(1 if neg else 0, epos):
        if b[i] != 46:
            digits += chr(Int(b[i]))
    var db = digits.as_bytes()
    var n = len(db)
    while n > 1 and db[n - 1] == 48:
        n -= 1
    var trimmed = String(digits[byte=0:n])
    digits = trimmed^
    var e = 0
    for i in range(epos + 2, len(b)):
        e = e * 10 + Int(b[i] - 48)
    if b[epos + 1] == 45:
        e = -e
    var out = String("-") if neg else String()
    if -4 <= e and e < 16:
        if e >= 0:
            var ip = String(digits[byte = 0 : min(e + 1, n)])
            for _ in range(e + 1 - n):
                ip += "0"
            var fp = String(digits[byte = e + 1 :]) if e + 1 < n else String("0")
            out += ip + "." + fp
        else:
            out += "0."
            for _ in range(-e - 1):
                out += "0"
            out += digits
        return out^
    out += String(digits[byte=0:1])
    if n > 1:
        out += "." + String(digits[byte=1:])
    out += "e-" if e < 0 else "e+"
    var ae = -e if e < 0 else e
    if ae < 10:
        out += "0"
    out += String(ae)
    return out^
