# FastOTF2

FastOTF2 is a trace conversion toolkit for turning OTF2 traces into analysis-friendly data products, starting with CSV.
It is built on a Chapel implementation of the OTF2 API and is organized around the workflow a user actually cares about first: build the converter, run it on a trace, and start analyzing the output.

The repository is currently in the middle of a structural cleanup.
The long-term target layout is documented in [docs/repository-organization.md](docs/repository-organization.md), but the current implementation paths remain active while the migration proceeds.

## Start Here

If your goal is to convert traces, begin with:

1. [docs/quickstart.md](docs/quickstart.md)
2. [docs/container.md](docs/container.md) if you want a containerized environment
3. [apps/trace_to_csv](apps/trace_to_csv) for the primary application
4. [sample-traces](sample-traces) for bundled sample traces

If your goal is to understand the implementation strategy or compare languages, continue with:

1. [docs/architecture.md](docs/architecture.md)
2. [docs/comparisons.md](docs/comparisons.md)
3. [DEMO.md](DEMO.md) for the current in-depth walkthrough

## Quickstart

Current build and run flow:

```bash
cd apps/trace_to_csv
make
./trace_to_csv --tracePath=../../sample-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2
```

Parallel variant:

```bash
cd apps/trace_to_csv
make parallel
./trace_to_csv_parallel --trace=../../sample-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2
```

See [docs/quickstart.md](docs/quickstart.md) for prerequisites, options, and notes about the current directory layout.

## Repository Guide

The repository is being reorganized toward a clearer structure with separate homes for the reusable Chapel package, user-facing apps, and comparison implementations.

Today:

- [chpl](chpl) contains the working Chapel library and applications.
- [apps/trace_to_csv](apps/trace_to_csv) contains the primary trace conversion application.
- [chpl/trace_to_csv](chpl/trace_to_csv) remains temporarily as a compatibility path for the pre-migration location.
- [chpl/_chpl](chpl/_chpl) contains the current Chapel OTF2 library modules.
- [examples/c](examples/c) contains the C reference implementations.
- [examples/python](examples/python) contains the Python comparison scripts.
- [docs/tutorials](docs/tutorials) contains the current notebooks.
- [docs/benchmarks/perfnotes.md](docs/benchmarks/perfnotes.md) contains the current performance notes.
- [container](container) contains the development container setup.
- [sample-traces](sample-traces) is the canonical bundled trace path used in the current docs and app defaults.
- [scorep-traces](scorep-traces) remains as the legacy directory name for compatibility.

Target structure:

- [apps](apps) will hold user-facing applications.
- [src](src) will hold the Mason-friendly Chapel package source.
- [examples](examples) will hold comparison and tutorial implementations.
- [docs](docs) will hold quickstart, architecture, and migration guidance.

## Why This Repository Exists

The most important problem this repository solves is converting OTF2 trace data into a format that is easier to analyze with downstream tools.
The Chapel library matters because it enables high-performance implementations of those workflows, but the repository should be judged first by how quickly it gets a user from a trace archive to useful data.

## Current Documentation

- [docs/quickstart.md](docs/quickstart.md): build and run the current converter
- [docs/container.md](docs/container.md): use the container environment
- [docs/architecture.md](docs/architecture.md): how the repository is structured and why
- [docs/comparisons.md](docs/comparisons.md): role of the C, Python, and Chapel implementations
- [docs/repository-organization.md](docs/repository-organization.md): target organization for the ongoing cleanup

## Build Modes

During the migration, both Chapel build flows are supported:

- Make remains the active build path for the existing applications under [chpl](chpl).
- Mason now exists for the reusable Chapel package rooted at [Mason.toml](Mason.toml) and [src](src).

Both build paths currently assume the same default external OTF2 installation paths under `/opt/otf2`.

## Status

This repository is actively being reorganized.
During the transition, some documentation will point at the target structure while commands still reference the current paths under [chpl](chpl).
That is intentional until the implementation is moved.