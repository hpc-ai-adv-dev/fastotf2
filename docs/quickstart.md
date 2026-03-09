# Quickstart

This quickstart is for the primary workflow in the repository: convert an OTF2 trace into CSV.

## What You Need

- Chapel compiler
- OTF2 development headers and libraries
- Make

If you do not want to install those directly on your machine, use the container workflow in [container.md](container.md).

## Current Implementation Location

The converter's primary home is now [../apps/trace_to_csv](../apps/trace_to_csv).
The legacy implementation path under [../chpl/trace_to_csv](../chpl/trace_to_csv) remains available temporarily during the migration.

## Build The Converter

Serial and parallel builds are both driven by the Makefile in the current implementation directory.

```bash
cd apps/trace_to_csv
make
```

That builds:

- `trace_to_csv`
- `trace_to_csv_parallel`

If you only want the parallel build:

```bash
cd apps/trace_to_csv
make parallel
```

## Run The Converter

Example serial run:

```bash
cd apps/trace_to_csv
./trace_to_csv --tracePath=../../sample-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2
```

Example parallel run:

```bash
cd apps/trace_to_csv
./trace_to_csv_parallel --trace=../../sample-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2
```

The serial implementation uses Chapel config constants such as:

- `--tracePath`
- `--crayTimeOffsetArg`
- `--metricsToTrackArg`
- `--processesToTrackArg`

The parallel implementation currently uses argument parsing and supports options such as:

- `--trace`
- `--metrics`
- `--processes`
- `--outputDir`
- `--excludeMPI`
- `--excludeHIP`

## Sample Inputs

Bundled traces are canonically exposed under [../sample-traces](../sample-traces).
The legacy path [../scorep-traces](../scorep-traces) remains available during the migration.
Those traces are kept in the repository so the main conversion workflow is easy to try.

## Current Caveats

- The repository is in transition, so the user-facing documentation is ahead of the implementation layout.
- The legacy app path under [../chpl/trace_to_csv](../chpl/trace_to_csv) still exists for compatibility.
- The long-term Chapel package home is [../src](../src), but the library currently lives under [../chpl/_chpl](../chpl/_chpl).

## Next Reading

- [architecture.md](architecture.md)
- [container.md](container.md)
- [comparisons.md](comparisons.md)
- [../DEMO.md](../DEMO.md)