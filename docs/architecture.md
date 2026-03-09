# Architecture

FastOTF2 currently mixes library code, applications, examples, and tutorial material in ways that make the primary user workflow harder to see than it should be.
The repository is being reorganized so the trace conversion path is explicit and the supporting material is clearly labeled.

## Product Layers

The repository has four functional layers:

1. Primary application layer: trace conversion tools that users run directly.
2. Library layer: reusable Chapel OTF2 modules that power the applications.
3. Example layer: C, Python, and non-primary Chapel implementations used for comparison or exploration.
4. Infrastructure layer: container setup, build helpers, and bundled trace inputs.

## Current Working Layout

Today, the working implementation is split like this:

- [../apps/trace_to_csv](../apps/trace_to_csv): primary converter implementation
- [../chpl/trace_to_csv](../chpl/trace_to_csv): temporary compatibility path for the previous converter location
- [../chpl/_chpl](../chpl/_chpl): current reusable Chapel OTF2 modules
- [../chpl/simple](../chpl/simple), [../chpl/read_events](../chpl/read_events), [../chpl/read_events_and_metrics](../chpl/read_events_and_metrics): additional Chapel programs
- [../examples/c](../examples/c): C reference implementations
- [../examples/python](../examples/python): Python comparison scripts
- [../docs/tutorials](../docs/tutorials): notebook-based tutorial material
- [../docs/benchmarks/perfnotes.md](../docs/benchmarks/perfnotes.md): current benchmark notes
- [../container](../container): containerized development environment
- [../sample-traces](../sample-traces): canonical bundled sample traces
- [../scorep-traces](../scorep-traces): legacy bundled trace path retained for compatibility

## Target Working Layout

The target structure is:

- [../apps](../apps): user-facing applications
- [../src](../src): Mason-friendly Chapel package source
- [../examples](../examples): comparison and tutorial implementations
- [..](..): top-level docs and onboarding

This separates the product surface from the reusable package and from the comparison code.

## Design Goals

- A new user should find the converter first, not the internals first.
- The Chapel package should be structured so Mason can manage it cleanly.
- C and Python should remain available without competing with the main supported workflow.
- Documentation should map to user intent instead of current historical layout.

## Transitional Reality

During migration, some docs point to the target structure while commands still reference current paths under [../chpl](../chpl).
That is expected until the code and build systems are moved.

See [repository-organization.md](repository-organization.md) for the target information architecture and migration principles.