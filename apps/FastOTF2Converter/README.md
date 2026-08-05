# FastOTF2Converter

The primary trace-to-table converter application. For getting started, see the [root README](../../README.md).

## Build and Run

```bash
cd apps/FastOTF2Converter
mason build --release
mason run --release -- ../../sample-traces/simple-mi300-example-run/traces.otf2
```

## Output Formats

The converter supports two output formats via the `--format` flag:

| Format | Flag | Description |
|--------|------|-------------|
| CSV | `--format=CSV` (default) | Human-readable comma-separated values. Times in seconds, `inf` for unended intervals. |
| Parquet | `--format=PARQUET` | Columnar binary format. Times in nanoseconds (int64), `-1` for unended intervals. |

Both formats produce the same set of output files per location group:
- `<Group>_<Thread>_callgraph.{csv,parquet}` — one per thread, with columns: thread, group, depth, name, start, end, duration
- `<Group>_metrics.{csv,parquet}` — one per group, with columns: group, metric_name, time, value

### Parquet Prerequisites

The Parquet output path requires Apache Arrow C++ libraries.
Make sure `pkg-config` can find arrow and parquet headers.
The Parquet package dependency is declared in [Mason.toml](Mason.toml) and pulled automatically by `mason build`.

## Command-Line Arguments

Both the parallel converter and the serial example accept the same CLI:

| Argument | Default | Description |
|----------|---------|-------------|
| `<trace>` (positional) | `../../sample-traces/.../traces.otf2` | Path to the OTF2 trace archive |
| `--format` | `CSV` | Output format: `CSV` or `PARQUET` |
| `--outputDir` | `./` | Directory for output files |
| `--strategy` | Single-locale: `locgroup_block` (recommended) / Multi-locale: `locgroup_dist_block` (default) | Strategy to distribute work across tasks. See [Strategy Options](../../docs/strategies.md) for detailed guidance. |
| `--metrics` | (empty = all) | Comma-separated metric names to track |
| `--processes` | (empty = all) | Comma-separated process/group names to track |
| `--excludeMPI` | `false` | Exclude MPI regions from callgraph output |
| `--excludeHIP` | `false` | Exclude HIP regions from callgraph output |
| `--parallelism-report` | `false` | Print preflight topology, phase parallelism, and scaling headroom for `locgroup_dist_block` |
| `--log` | `INFO` | Log level: `NONE`, `ERROR`, `WARN`, `INFO`, `DEBUG`, `TRACE` |

## Parallelism Preflight

Use `--parallelism-report` with `locgroup_dist_block` to print the execution
plan after the trace definitions and resolved group map are available, but
before event reading begins:

```bash
mason run --release -- -nl 4 ../../sample-traces/simple-mi300-example-run/traces.otf2 \
	--strategy=locgroup_dist_block --format=PARQUET --parallelism-report
```

The report distinguishes raw OTF2 location groups from resolved output groups
after name-based folding. It also reports reader pipelines, active locales,
read/process/write concurrency, and two forms of scaling headroom:

- **Direct reader scaling** adds OTF2 readers until there is one reader per resolved output group.
- **Locale placement scaling** can continue after reader saturation by spreading those readers and their nested output work across more locales. With this strategy, locales beyond the resolved output-group count receive no conversion work.

The second form explains why adding nodes can improve runtime even when the
reader count has already reached the resolved group count. The amount of
speedup still depends on event balance, memory bandwidth, and filesystem I/O.

## Running Tests

Tests verify numeric parity between CSV and Parquet output:

```bash
# Generate CSV and Parquet reference output
mason run --release -- ../../sample-traces/simple-mi300-example-run/traces.otf2 --format=CSV --outputDir=/tmp/csv_out
mason run --release -- ../../sample-traces/simple-mi300-example-run/traces.otf2 --format=PARQUET --outputDir=/tmp/pq_out

# Generate Output from two different strategies
mason run --release -- ../../sample-traces/simple-mi300-example-run/traces.otf2 --strategy=serial --outputDir=/tmp/old_pq_out
mason run --release -- ../../sample-traces/simple-mi300-example-run/traces.otf2 --strategy=locgroup_block --outputDir=/tmp/new_pq_out

# Run Parity tests
mason test --show
```