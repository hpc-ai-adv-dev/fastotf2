# Repository Organization Target

This document defines the target repository information architecture for FastOTF2.
It exists to anchor the reorganization work before code and directory moves begin.

## Product Positioning

FastOTF2 should present itself first as a trace conversion toolkit for turning OTF2 traces into analysis-friendly data products.
The Chapel library remains a core asset, but it supports the primary user-facing workflow rather than competing with it.

Primary user:
- Someone who wants to convert an OTF2 trace into CSV, and later Parquet or other analysis-ready formats.

Secondary users:
- Someone evaluating the Chapel implementation against C and Python reference implementations.
- Someone using the Chapel package directly to build custom OTF2 tooling.

## Primary User Journey

The intended path for a first-time user is:

1. Open the repository landing page and immediately understand that the main value is trace conversion.
2. Find a quickstart path without needing to understand the full library internals.
3. Build and run the primary conversion tool against bundled sample traces.
4. Discover parallel and advanced workflows if needed.
5. Only then drill into library internals, comparison implementations, and development environment details.

That user journey implies that the repository structure and top-level docs should guide users in this order:

1. README
2. Quickstart documentation
3. Primary conversion application
4. Sample trace data
5. Supporting documentation
6. Comparison implementations
7. Chapel package internals

## Target Top-Level Layout

The repository should evolve toward the following structure:

```text
fastotf2/
├── README.md
├── docs/
│   ├── quickstart.md
│   ├── repository-organization.md
│   ├── architecture.md
│   ├── comparisons.md
│   └── container.md
├── src/
│   └── OTF2.chpl
├── apps/
│   └── trace_to_csv/
├── examples/
│   ├── chapel/
│   ├── python/
│   └── c/
├── container/
├── sample-traces/
└── Mason.toml
```

This target shape is intentional:

- `src/` gives the Chapel package a Mason-friendly home.
- `apps/trace_to_csv/` keeps the main application visible at the product layer.
- `examples/` clearly labels non-primary implementations as supporting material.
- `docs/` becomes the stable home for quickstart, architecture, and migration guidance.
- `sample-traces/` keeps bundled data discoverable for new users.

## Classification Rules

Every repository artifact should fit one of these roles:

- Primary app: supported tools that represent the main user value.
- Library: reusable Chapel package code used by the apps.
- Example: comparison, tutorial, or exploratory implementations.
- Infrastructure: container, build, and environment setup assets.
- Sample data: bundled traces and fixtures used for demos, validation, and onboarding.

Artifacts that do not fit one of these roles should be moved, renamed, or removed.

## Migration Principles

The reorganization should follow these principles:

1. Keep the primary conversion workflow visible and easy to follow.
2. Avoid root-level clutter.
3. Preserve compatibility where practical during the migration.
4. Make Mason the canonical Chapel package entry point.
5. Keep Make available during transition where it provides practical value.
6. Keep C and Python implementations, but label them clearly as comparison or reference material.

## What This Step Changes

This step does not move code yet.
It establishes the target structure and user journey so subsequent edits can be evaluated against a concrete design.

## Next Planned Step

Step 2 will begin aligning the repository with this target layout by choosing and introducing the new top-level structure in the codebase.