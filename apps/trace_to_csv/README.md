# trace_to_csv

This directory is the primary home for the FastOTF2 trace conversion application.

It contains the promoted Chapel implementation for converting OTF2 traces into CSV-oriented analysis outputs.
The legacy implementation path under `chpl/trace_to_csv/` remains available temporarily for compatibility during the migration.

## Build

Serial and parallel builds are both supported:

```bash
cd apps/trace_to_csv
make
```

That builds:

- `trace_to_csv`
- `trace_to_csv_parallel`

Parallel only:

```bash
cd apps/trace_to_csv
make parallel
```

## Run

Serial example:

```bash
cd apps/trace_to_csv
./trace_to_csv --tracePath=../../sample-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2
```

Parallel example:

```bash
cd apps/trace_to_csv
./trace_to_csv_parallel --trace=../../sample-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2
```

## Build Model

This app now builds against the reusable Chapel package modules in `src/`.
The shared Make-based build helper still comes from `chpl/Makefile.common` during the migration.

## Trace Inputs

The canonical bundled trace path in the repository is now `sample-traces/`.
The legacy `scorep-traces/` name remains available during the migration for compatibility.