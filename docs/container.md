# Container Workflow

Use the container workflow if you want a ready-made environment with Chapel and OTF2 available.

The full container setup remains documented in [../container/README.md](../container/README.md).
This page exists to place that workflow into the new documentation hierarchy.

## When To Use The Container

Use the container if:

- you do not want to install Chapel and OTF2 locally
- you want a reproducible environment for building the FastOTF2 Mason packages
- you want to run against the bundled sample traces with minimal local setup

## Current Container Model

Today the container mounts:

- `/workspace` for the Chapel source tree
- `/traces` for the bundled OTF2 traces

The primary build and run instructions now use Mason at the repo root and in [../apps/trace_to_csv](../apps/trace_to_csv).

## Recommended Starting Point

1. Read [../container/README.md](../container/README.md)
2. Build the container from [../container](../container)
3. Enter the environment
4. Run Mason examples from the repo root or build the converter from [../apps/trace_to_csv](../apps/trace_to_csv)
5. Run it against traces from [../sample-traces](../sample-traces)