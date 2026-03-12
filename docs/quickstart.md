# Quickstart

This quickstart covers the two primary Mason workflows in the repository: running the trace converter application and using the FastOTF2 library through root examples.

## What You Need

- Chapel compiler
- OTF2 development headers and libraries
- Mason, which ships with Chapel

If you do not want to install those directly on your machine, use the container workflow in [container.md](container.md).

## Build The Converter

Build the primary parallel converter with Mason:

```bash
cd apps/TraceToCSV
mason build
```

That builds the package's primary executable, `TraceToCSV`.

To build the serial proof-of-concept example as well:

```bash
cd apps/TraceToCSV
mason build --example
```

## Run The Converter

Example primary run:

```bash
cd apps/TraceToCSV
mason run -- ../../sample-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2
```

Example serial run through the package example:

```bash
cd apps/TraceToCSV
mason run --example TraceToCSVSerial.chpl
```

The primary parallel implementation currently accepts arguments such as:

- positional trace path
- `--trace`
- `--metrics`
- `--processes`
- `--outputDir`
- `--excludeMPI`
- `--excludeHIP`
- `--log`

The serial example remains an example path and still uses the older Chapel config-constant interface.

## Root Library Package

The repository root is a Mason library package for FastOTF2.
You can build and run the proof-of-concept Chapel examples from the repository root:

```bash
cd /path/to/fastotf2
mason build --example
mason run --example FastOtf2ReadArchive.chpl
mason run --example FastOtf2ReadEvents.chpl
```

The examples default to bundled inputs under [../sample-traces](../sample-traces).

## Sample Inputs

Bundled traces are canonically exposed under [../sample-traces](../sample-traces).
You can substitute any local OTF2 trace archive when you move beyond the sample inputs.

## Notes

- The supported build flow is Mason.
- The serial converter is an example path, not a second application package.
- The default external OTF2 installation path is `/opt/otf2`.

## Next Reading

- [architecture.md](architecture.md)
- [container.md](container.md)
- [comparisons.md](comparisons.md)
- [../DEMO.md](../DEMO.md)