# FastOTF2

FastOTF2 converts OTF2 traces into analysis-friendly outputs, starting with CSV.
The main entrypoint is the Mason application in [apps/trace_to_csv](apps/trace_to_csv), built on top of the reusable Chapel library at the repository root.

## Quickstart

Build and run the trace converter:

```bash
cd apps/trace_to_csv
mason build
mason run -- ../../sample-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2
```

Run the serial example:

```bash
cd apps/trace_to_csv
mason run --example TraceToCSVSerial.chpl
```

Use [docs/quickstart.md](docs/quickstart.md) for prerequisites, CLI notes, and alternate workflows.
Use [docs/container.md](docs/container.md) if you want a prebuilt Chapel and OTF2 environment.

## Repository Layout

- [apps/trace_to_csv](apps/trace_to_csv) is the primary trace conversion application.
- [sample-traces](sample-traces) contains bundled trace inputs used by the docs and examples.
- [src](src) and [Mason.toml](Mason.toml) define the reusable FastOTF2 Chapel library.
- [example](example) contains Mason examples for the root library package.
- [comparisons](comparisons) contains C and Python comparison material.
- [docs](docs) contains quickstart, architecture, container, benchmark, and tutorial documentation.
- [container](container) contains the containerized development environment.

## Documentation

- [docs/quickstart.md](docs/quickstart.md): build and run the converter
- [apps/trace_to_csv/README.md](apps/trace_to_csv/README.md): application-specific usage and layout
- [docs/container.md](docs/container.md): container workflow
- [docs/architecture.md](docs/architecture.md): repository structure and package roles
- [docs/comparisons.md](docs/comparisons.md): how the Chapel, Python, and C implementations relate
- [DEMO.md](DEMO.md): walkthrough of the OTF2 model and the project implementation

## Library Workflow

If you want to use the reusable Chapel package directly:

```bash
mason build --example
mason run --example FastOtf2ReadArchive.chpl
mason run --example FastOtf2ReadEvents.chpl
```

## Why This Repository Exists

FastOTF2 exists to make OTF2 trace data easier to explore, export, and analyze at scale.
The converter application is the first user-facing product; the root library exists to support that workflow and to enable additional OTF2 tooling.