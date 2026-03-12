# TraceToCSV

This directory contains the primary FastOTF2 application package.
It is a Mason application built on the reusable FastOTF2 Chapel library at the repository root.

For end-to-end user instructions, start with one of these instead of using this package README as a standalone quickstart:

- [../../container/README.md](../../container/README.md): recommended container-first workflow
- [../../docs/quickstart.md](../../docs/quickstart.md): local/native workflow

## Package Layout

- [Mason.toml](Mason.toml): application package manifest
- [src/TraceToCSV.chpl](src/TraceToCSV.chpl): Mason application entrypoint
- [src/TraceToCSVParallel.chpl](src/TraceToCSVParallel.chpl): current primary parallel implementation
- [example/TraceToCSVSerial.chpl](example/TraceToCSVSerial.chpl): serial example path

## Common Commands

```bash
cd apps/TraceToCSV
mason build --release
mason run --release -- ../../sample-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2
```

To build and run the serial example path:

```bash
cd apps/TraceToCSV
mason build --release --example
mason run --release --example TraceToCSVSerial.chpl
```

## Notes

- Use `--release` for normal builds and runs.
- Mason adds Chapel's `--fast` automatically for release builds.
- The package builds against the root FastOTF2 library source via Mason compiler options.