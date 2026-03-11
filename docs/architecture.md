# Architecture

FastOTF2 is organized around two Mason packages in one repository: the root FastOTF2 library package and the trace converter application package under [../apps/trace_to_csv](../apps/trace_to_csv). Supporting comparison implementations remain in the repo, but they are not the primary product surface.

## Product Layers

The repository has four functional layers:

1. Library layer: the root FastOTF2 Mason package under [..](..) and [../src](../src).
2. Primary application layer: the trace converter Mason package under [../apps/trace_to_csv](../apps/trace_to_csv).
3. Example layer: root Mason library examples plus C and Python comparison material.
4. Infrastructure layer: container setup, bundled trace inputs, and tutorial material.

## Primary Package Layout

The primary supported package structure is:

- [../Mason.toml](../Mason.toml): root FastOTF2 library package manifest
- [../src](../src): reusable Chapel OTF2 modules for FastOTF2
- [../example](../example): Mason examples that prove the root library package works directly
- [../apps/trace_to_csv/Mason.toml](../apps/trace_to_csv/Mason.toml): trace converter application package manifest
- [../apps/trace_to_csv/src](../apps/trace_to_csv/src): primary trace converter source tree
- [../apps/trace_to_csv/example](../apps/trace_to_csv/example): converter examples, including the current serial path

## Supporting Repository Layout

The repository also contains:

- [../comparisons/c](../comparisons/c): C reference implementations
- [../comparisons/python](../comparisons/python): Python comparison scripts
- [../docs/tutorials](../docs/tutorials): notebook-based tutorial material
- [../docs/benchmarks](../docs/benchmarks): benchmark notes and supporting documentation
- [../container](../container): containerized development environment
- [../sample-traces](../sample-traces): canonical bundled sample traces

## Package Roles

The root package is library-only.
Users exercise it through Mason examples and tests rather than through a root application binary.

The application package under [../apps/trace_to_csv](../apps/trace_to_csv) is the main user-facing tool.
Its primary executable is the parallel converter, and alternate flows such as the serial path are modeled as examples or internal modes rather than separate Mason packages.

This separates the reusable package surface from the user-facing application and from the comparison code.

## Design Goals

- A new user should find the converter first, not the internals first.
- The Chapel package should be structured so Mason can manage it cleanly.
- C and Python should remain available without competing with the main supported workflow.
- The repository should expose exactly two Mason packages, not a package per converter variant.
- Documentation should map to user intent instead of current historical layout.