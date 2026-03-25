# FastOTF2Converter

This directory contains the primary FastOTF2 application package.
It is a Mason application built on the reusable FastOTF2 Chapel library at the repository root.

For end-to-end user instructions, start with one of these instead of using this package README as a standalone quickstart:

- [../../container/README.md](../../container/README.md): recommended container-first workflow
- [../../docs/quickstart.md](../../docs/quickstart.md): local/native workflow

## Package Layout

- [Mason.toml](Mason.toml): application package manifest
- [src/FastOTF2Converter.chpl](src/FastOTF2Converter.chpl): Mason application entrypoint
- [src/FastOTF2ConverterParallel.chpl](src/FastOTF2ConverterParallel.chpl): primary parallel implementation
- [src/FastOTF2ConverterWriters.chpl](src/FastOTF2ConverterWriters.chpl): CSV and Parquet output writers
- [src/CallGraphModule.chpl](src/CallGraphModule.chpl): timeline and interval data structures
- [example/FastOTF2ConverterSerial.chpl](example/FastOTF2ConverterSerial.chpl): serial reference example
- [test/CallgraphParityTest.chpl](test/CallgraphParityTest.chpl): CSV↔Parquet callgraph parity test
- [test/MetricsParityTest.chpl](test/MetricsParityTest.chpl): CSV↔Parquet metrics parity test

## Common Commands

```bash
cd apps/FastOTF2Converter
mason build --release
mason run --release -- ../../sample-traces/simple-mi300-example-run/traces.otf2
```

To use a different trace, replace the final positional path when invoking `mason run`.

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

The Parquet output path requires Apache Arrow C++ libraries. On systems using Spack:

```bash
. ~/dev/spack/share/spack/setup-env.sh && spack env activate arrow-19
```

The Parquet package dependency is declared in [Mason.toml](Mason.toml) and pulled automatically by `mason build`.

### Known Parquet Limitations

The Parquet backend has the following known limitations due to the upstream Chapel Parquet package:

- **[PARQUET-PKG-GUARD]** `writeTable()` crashes on empty arrays — the converter skips writing when there are zero rows.
- **[PARQUET-PKG-1]** `getDatasets()` / `getArrType()` segfault on valid files — schema validation tests are disabled.
- **[PARQUET-PKG-2]** `readColumn()` does not support string columns — string parity tests are disabled.

Search these tags in the source to find related workarounds.

## Command-Line Arguments

The parallel converter accepts the following arguments:

| Argument | Default | Description |
|----------|---------|-------------|
| `<trace>` (positional) | `../../sample-traces/.../traces.otf2` | Path to the OTF2 trace archive |
| `--format` | `CSV` | Output format: `CSV` or `PARQUET` |
| `--outputDir` | `./` | Directory for output files |
| `--metrics` | (empty = all) | Comma-separated metric names to track |
| `--processes` | (empty = all) | Comma-separated process/group names to track |
| `--excludeMPI` | `false` | Exclude MPI regions from callgraph output |
| `--excludeHIP` | `false` | Exclude HIP regions from callgraph output |
| `--log` | `INFO` | Log level: `NONE`, `ERROR`, `WARN`, `INFO`, `DEBUG`, `TRACE` |

The serial example path uses Chapel config constants instead of ArgumentParser:

| Config Constant | Default | Description |
|-----------------|---------|-------------|
| `--tracePath` | `../../sample-traces/.../traces.otf2` | Path to the OTF2 trace archive |
| `--outputFormatArg` | `CSV` | Output format: `CSV` or `PARQUET` |
| `--metricsToTrackArg` | (energy metrics) | Comma-separated metric names |
| `--processesToTrackArg` | (empty = all) | Comma-separated process names |
| `--crayTimeOffsetArg` | `1.0` | Time offset for CrayPM metrics (serial only) |

## Running Tests

Tests verify numeric parity between CSV and Parquet output. They require pre-generated output files:

```bash
# Generate CSV and Parquet reference output
mason run --release -- ../../sample-traces/simple-mi300-example-run/traces.otf2 --format=CSV --outputDir=/tmp/csv_out
mason run --release -- ../../sample-traces/simple-mi300-example-run/traces.otf2 --format=PARQUET --outputDir=/tmp/pq_out

# Run parity tests
mason test --show
```

## Notes

- Use `--release` for normal builds and runs.
- Mason adds Chapel's `--fast` automatically for release builds.
- The package builds against the root FastOTF2 library source via Mason compiler options.