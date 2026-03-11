# trace_to_csv

This directory contains the primary FastOTF2 application for converting OTF2 traces into CSV-oriented outputs.
It is a Mason application package built on the reusable FastOTF2 Chapel library at the repository root.

## Build

Build the primary converter executable with Mason:

```bash
cd apps/trace_to_csv
mason build
```

That builds the package's primary application, `trace_to_csv`.

To build the serial example path as well:

```bash
cd apps/trace_to_csv
mason build --example
```

## Run

Primary parallel run:

```bash
cd apps/trace_to_csv
mason run -- ../../sample-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2
```

Serial example run:

```bash
cd apps/trace_to_csv
mason run --example TraceToCSVSerial.chpl
```

## Package Layout

- [Mason.toml](Mason.toml): application package manifest
- [src/trace_to_csv.chpl](src/trace_to_csv.chpl): primary Mason entrypoint
- [src/TraceToCSVParallel.chpl](src/TraceToCSVParallel.chpl): current parallel implementation used by the primary app
- [example/TraceToCSVSerial.chpl](example/TraceToCSVSerial.chpl): Mason example entrypoint for the serial path
- [example/TraceToCSV.chpl](example/TraceToCSV.chpl): current serial implementation backing the serial example

## Build Model

This package builds against the reusable FastOTF2 Chapel modules at the repository root.
The current package uses the root library source directly through Mason compiler options.

The current primary CLI is the parallel implementation, which supports options such as:

- positional trace path
- `--trace`
- `--metrics`
- `--processes`
- `--outputDir`
- `--excludeMPI`
- `--excludeHIP`
- `--log`

## Trace Inputs

The canonical bundled trace path in the repository is `sample-traces/`.
You can also point the converter at any local `.otf2` trace archive path.