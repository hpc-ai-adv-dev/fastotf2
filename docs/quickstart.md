# Local Build and Run Quickstart

This guide is for users who want to build and run FastOTF2 directly on their own machine without using the repository container workflow.

If you do not already have Chapel, Mason, and OTF2 installed locally, start with [../container/README.md](../container/README.md) instead. That is the recommended path for most users.

## Overview

This quickstart covers the two primary Mason workflows in the repository:

1. building and running the `TraceToCSV` application
2. building and running the root FastOTF2 library examples

## What You Need

Before using this workflow, ensure you already have:

- Chapel 2.8.0 or higher
- Mason, which ships with Chapel
- OTF2 headers and libraries available locally

The manifests in this repository currently assume an OTF2 installation rooted at `/opt/otf2`.

## Step 1: Verify Your Local Toolchain

Check the expected tools first:

```bash
chpl --version
mason --version
ls /opt/otf2/include/otf2
ls /opt/otf2/lib
```

If those paths do not exist in your environment, you will need to either adjust your local installation to match or modify the manifest compiler options for your system.

## Step 2: Build TraceToCSV

Build the primary converter with Mason:

```bash
cd apps/TraceToCSV
mason build --release
```

Use `--release` for normal builds and runs. Mason adds Chapel's `--fast` automatically for release builds, so `--fast` is not included in the package `compopts` by default.

To build the serial example path as well:

```bash
cd apps/TraceToCSV
mason build --release --example
```

## Step 3: Run TraceToCSV

Run the primary converter against one of the bundled traces:

```bash
cd apps/TraceToCSV
mason run --release -- ../../sample-traces/simple-mi300-example-run/traces.otf2
```

To run a different archive, replace the final positional path with your own `traces.otf2` path.

Run the serial example path:

```bash
cd apps/TraceToCSV
mason run --release --example TraceToCSVSerial.chpl
```

The primary parallel implementation accepts options such as:

- positional trace path
- `--trace`
- `--metrics`
- `--processes`
- `--outputDir`
- `--excludeMPI`
- `--excludeHIP`
- `--log`

The serial path remains an example-backed flow and still uses the older Chapel config-constant interface.

## Step 4: Run the Root Library Examples

The repository root is a Mason library package for FastOTF2. You can build and run the examples from the repository root:

```bash
cd /path/to/fastotf2
mason build --release --example
mason run --release --example FastOtf2ReadArchive.chpl
mason run --release --example FastOtf2ReadEvents.chpl
```

The examples default to bundled inputs under [../sample-traces](../sample-traces).
To point any of the Chapel examples at a different trace, pass `--tracePath=/path/to/traces.otf2`.

## Sample Inputs

Bundled traces are canonically exposed under [../sample-traces](../sample-traces).
You can substitute any local OTF2 trace archive when you move beyond the sample inputs.

## Notes

- The supported build flow is Mason.
- The serial converter is an example path, not a second application package.
- The root package is a library package and is primarily exercised through examples.

## Next Reading

- [../README.md](../README.md)
- [architecture.md](architecture.md)
- [comparisons.md](comparisons.md)
- [../container/README.md](../container/README.md)
- [../DEMO.md](../DEMO.md)