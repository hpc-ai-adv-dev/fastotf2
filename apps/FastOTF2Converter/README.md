# FastOTF2Converter

This directory contains the primary FastOTF2 application package.
It is a Mason application built on the reusable FastOTF2 Chapel library at the repository root.

For end-to-end user instructions, start with one of these instead of using this package README as a standalone quickstart:

- [../../container/README.md](../../container/README.md): recommended container-first workflow
- [../../docs/quickstart.md](../../docs/quickstart.md): local/native workflow

## Package Layout

- [Mason.toml](Mason.toml): application package manifest
- [src/FastOTF2Converter.chpl](src/FastOTF2Converter.chpl): Mason application entrypoint
- [src/FastOTF2ConverterParallel.chpl](src/FastOTF2ConverterParallel.chpl): current primary parallel implementation
- [example/FastOTF2ConverterSerial.chpl](example/FastOTF2ConverterSerial.chpl): serial example path

## Common Commands

```bash
cd apps/FastOTF2Converter
mason build --release
mason run --release -- ../../sample-traces/simple-mi300-example-run/traces.otf2
```

To use a different trace, replace the final positional path when invoking `mason run`.
The primary app also accepts `--format=CSV` or `--format=PARQUET`; the Parquet path is wired up but not implemented yet.

To build and run the serial example path:

```bash
cd apps/FastOTF2Converter
mason build --release --example
mason run --release --example FastOTF2ConverterSerial.chpl
```

## Notes

- Use `--release` for normal builds and runs.
- Mason adds Chapel's `--fast` automatically for release builds.
- The package builds against the root FastOTF2 library source via Mason compiler options.