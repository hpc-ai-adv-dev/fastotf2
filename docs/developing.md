# Developing FastOTF2

All development happens inside the container. You do not need to install Chapel, OTF2, or Apache Arrow on your machine.

## Setup

Clone the repository:

```bash
git clone https://github.com/hpc-ai-adv-dev/fastotf2.git
cd fastotf2
```

Start an interactive container, using `-v` to mount your local clone into `/workspace` inside the container. This lets you edit source files with your normal editor on the host while building and running inside the container:

```bash
podman run -it --rm \
  -v "$(pwd):/workspace" \
  ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest bash
```

<details>
<summary>Docker alternative</summary>

```bash
docker run -it --rm \
  -v "$(pwd):/workspace" \
  ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest bash
```

</details>

You are now in `/workspace` with Chapel, Mason, OTF2, and Apache Arrow all available.

> Mounting your clone replaces the baked-in copy inside the container. You will need to rebuild after mounting.

## Build and Run

The converter application lives under `apps/FastOTF2Converter/`:

```bash
cd /workspace/apps/FastOTF2Converter
mason build --release
mason run --release -- /workspace/sample-traces/simple-mi300-example-run/traces.otf2
```

To run against a different trace, replace the final path. All CLI options are documented in the [converter README](../apps/FastOTF2Converter/README.md).

## Run Tests

Tests verify numeric parity between CSV and Parquet output:

```bash
cd /workspace/apps/FastOTF2Converter

# Generate reference output
mason run --release -- /workspace/sample-traces/simple-mi300-example-run/traces.otf2 \
  --format=CSV --outputDir=/tmp/csv_out
mason run --release -- /workspace/sample-traces/simple-mi300-example-run/traces.otf2 \
  --format=PARQUET --outputDir=/tmp/pq_out

# Run parity tests
mason test --show
```

## Project Structure

```
apps/FastOTF2Converter/         ← The converter application
  src/
    FastOTF2Converter.chpl           Entrypoint (delegates to parallel impl)
    FastOTF2ConverterParallel.chpl   Parallel event reading + writing
    FastOTF2ConverterCommon.chpl     Shared callbacks, types, helpers
    FastOTF2ConverterWriters.chpl    CSV and Parquet output writers
    CallGraphModule.chpl             Timeline/interval data structures
  example/
    FastOTF2ConverterSerial.chpl     Serial reference implementation
  test/                              CSV↔Parquet parity tests

src/                            ← The FastOTF2 library (reusable OTF2 modules)
  FastOTF2.chpl                      Library entry module
  OTF2_Reader.chpl, OTF2_Events.chpl, ...

example/                        ← Library examples (OTF2 reading demos)
```

The converter application (`apps/FastOTF2Converter`) depends on the root library (`src/`) via Mason compiler options. Both are Mason packages.

## Adding a New Output Format

Output formats are implemented in `apps/FastOTF2Converter/src/FastOTF2ConverterWriters.chpl`. To add a new format:

1. Add a new value to the `OutputFormat` enum.
2. Update `parseOutputFormat()` to recognize the new flag value.
3. Implement your writer functions following the pattern of `writeCallgraphCSV()` / `writeCallgraphParquet()`.
4. Wire the new format into `writeCallgraph()` and `writeMetrics()` dispatch in `FastOTF2ConverterCommon.chpl`.

## Running Library Examples

The root package contains standalone examples for reading OTF2 traces with the FastOTF2 library:

```bash
cd /workspace
mason build --release --example
mason run --release --example FastOtf2ReadArchive.chpl
mason run --release --example FastOtf2ReadEvents.chpl
```

These are useful for understanding the lower-level OTF2 reading API apart from the converter.

## References

- [Mason Documentation](https://chapel-lang.org/docs/tools/mason/mason.html)
- [Chapel Language Documentation](https://chapel-lang.org/docs/)
- [Chapel GitHub](https://github.com/chapel-lang/chapel)
- [OTF2 / Score-P Documentation](https://www.vi-hps.org/projects/score-p/)
- [Converter CLI and output format details](../apps/FastOTF2Converter/README.md)
- [Jupyter notebook tutorials](tutorials/)
