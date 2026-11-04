# Design

- **Struct of arrays.** Metric fields and child fields live in parallel lists; every child's values sit in one flat `List[Float64]` at its offset (histogram: per-bucket counts, then count and sum). `inc` is one index and one add.
- **Ids, not objects.** `child()` hashes the label values once (a `Dict` from metric id + values to child id); hot code keeps the id and never hashes again.
- **Labels rendered once.** Escaped (`\\`, `\n`, `"`) and sorted by label name when the child is created; `le` is merged into place while writing, without copying.
- **One output buffer, no temporaries.** `exposition()` appends every line into one `String`; whole-number values are written straight into it, and histogram bucket bounds are rendered once at registration instead of once per child and line.
- **Exact floats.** Values and bucket bounds go through Python's `repr` rules (`py_repr` from mojo-pyformat, vendored) and then `floatToGoString`'s exponent switch above six integer digits.
- Matches prometheus_client with `PROMETHEUS_DISABLE_CREATED_SERIES`: `_created` series carry wall-clock timestamps, which no byte-exact check can cover.
