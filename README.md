# FastOTF2

FastOTF2 converts OTF2 traces into analysis-friendly outputs, starting with CSV.
The main entrypoint is the Mason application in [apps/TraceToCSV](apps/TraceToCSV), built on top of the reusable Chapel library at the repository root.

## Quickstart

Build and run the trace converter:

```bash
cd apps/TraceToCSV
mason build --release
mason run --release -- ../../sample-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2
```

Use `--release` for normal builds and runs. Mason adds Chapel's `--fast` automatically for release builds, so `--fast` is not included in the package `compopts` by default.

Run the serial example:

```bash
cd apps/TraceToCSV
mason run --release --example TraceToCSVSerial.chpl
```

Use [docs/quickstart.md](docs/quickstart.md) for prerequisites, CLI notes, and alternate workflows.
Use [docs/container.md](docs/container.md) if you want a prebuilt Chapel and OTF2 environment.

## Repository Layout

- [apps/TraceToCSV](apps/TraceToCSV) is the primary trace conversion application.
- [sample-traces](sample-traces) contains bundled trace inputs used by the docs and examples.
- [src](src) and [Mason.toml](Mason.toml) define the reusable FastOTF2 Chapel library.
- [example](example) contains Mason examples for the root library package, including the restored simple, read-events, and metrics-focused Chapel utilities.
- [comparisons](comparisons) contains C and Python comparison material.
- [docs](docs) contains quickstart, architecture, container, benchmark, and tutorial documentation.
- [container](container) contains the containerized development environment.

## Documentation

- [docs/quickstart.md](docs/quickstart.md): build and run the converter
- [apps/TraceToCSV/README.md](apps/TraceToCSV/README.md): application-specific usage and layout
- [docs/container.md](docs/container.md): container workflow
- [docs/architecture.md](docs/architecture.md): repository structure and package roles
- [docs/comparisons.md](docs/comparisons.md): how the Chapel, Python, and C implementations relate
- [DEMO.md](DEMO.md): walkthrough of the OTF2 model and the project implementation

## Library Workflow

If you want to use the reusable Chapel package directly:

```bash
mason build --release --example
mason run --release --example FastOtf2ReadArchive.chpl
mason run --release --example FastOtf2ReadEvents.chpl
```

## Why This Repository Exists

FastOTF2 exists to make OTF2 trace data easier to explore, export, and analyze at scale.
The converter application is the first user-facing product; the root library exists to support that workflow and to enable additional OTF2 tooling.
