# FastOTF2Converter

Convert [OTF2](https://www.vi-hps.org/projects/score-p/) traces to **Parquet** or **CSV**.

## Quick Start

```bash
# 1. Pull the pre-built container (one-time)
podman pull ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest

# 2. Convert your traces
podman run --rm \
  -v /path/to/my/traces:/data \
  ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest \
  /data/traces.otf2 \
  --format=PARQUET \
  --outputDir=/data/output

# Output files appear in /path/to/my/traces/output/
```

<details>
<summary>Docker alternative</summary>

```bash
docker pull ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest

docker run --rm \
  -v /path/to/my/traces:/data \
  ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest \
  /data/traces.otf2 \
  --format=PARQUET \
  --outputDir=/data/output
```

</details>

For more container details (building from source, troubleshooting): [docs/container.md](docs/container.md)

## Output Formats

| Format | Flag | Description |
|--------|------|-------------|
| CSV | `--format=CSV` (default) | Human-readable. Times in seconds. |
| Parquet | `--format=PARQUET` | Columnar binary. Times in nanoseconds. |

### CLI Options

| Flag | Default | Description |
|------|---------|-------------|
| `<trace>` | — | Path to the OTF2 trace archive (positional) |
| `--format` | `CSV` | `CSV` or `PARQUET` |
| `--outputDir` | `./` | Directory for output files |
| `--metrics` | all | Comma-separated metric names to include |
| `--processes` | all | Comma-separated process/group names to include |
| `--excludeMPI` | `false` | Exclude MPI regions |
| `--excludeHIP` | `false` | Exclude HIP regions |
| `--log` | `INFO` | `NONE` · `ERROR` · `WARN` · `INFO` · `DEBUG` · `TRACE` |

## Performance

FastOTF2Converter reads trace locations in parallel, scaling with available threads. Early benchmarks on a MacBook Pro M2 Max:

| Trace Size | Events | Python | C | FastOTF2 Serial | FastOTF2 Parallel (8 threads) |
|---|---|---|---|---|---|
| Small | 72,670 | 0.28 s | 0.02 s | 0.017 s | 0.004 s |
| Large | 16.6 M | 42.2 s | 2.00 s | 1.99 s | 1.02 s |

<!-- TODO: Update numbers and dd performance chart image once HPC benchmarks are available -->
<!-- ![Performance chart](docs/benchmarks/perf-chart.png maybe?) -->

> Formal benchmarks on HPC hardware are in progress. Raw data: [docs/benchmarks/perfnotes.md](docs/benchmarks/perfnotes.md)

Under the hood, FastOTF2 is written in [Chapel](https://chapel-lang.org/) — a modern parallel programming language designed for productive, high-performance computing on hardware ranging from laptops to supercomputers. Chapel's built-in support for data parallelism, task parallelism, and multi-locale execution is what makes FastOTF2Converter fast and scalable.
## Running on HPC Systems

If you need to run on an HPC cluster using Apptainer, see the dedicated guide: [docs/hpc-apptainer.md](docs/hpc-apptainer.md)

Multi-node (multi-locale) container support is planned.

## Extending & Developing

Want to add a new output format, modify the converter, or build on the FastOTF2 library? All development can happen inside the container — no local Chapel installation needed.

See the developer guide: [docs/developing.md](docs/developing.md)

## Additional Resources

- [Full CLI and output format details](apps/FastOTF2Converter/README.md)
- [OTF2 format background and project walkthrough](DEMO.md)
- [Raw benchmark data](docs/benchmarks/perfnotes.md)
- [Jupyter notebook tutorials](docs/tutorials)
