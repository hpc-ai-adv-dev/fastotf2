# FastOTF2

FastOTF2 is a Chapel-based toolkit for reading OTF2 traces and converting them into analysis-friendly outputs.
The primary end-to-end workflow in this repository is the `FastOTF2Converter` Mason application in [apps/FastOTF2Converter](apps/FastOTF2Converter), built on top of the reusable FastOTF2 library at the repository root.

The recommended path for most users is the container workflow. It assumes you do not already have Chapel, Mason, and OTF2 installed locally and gives you a ready-made environment for building and running the repository.

## Using FastOTF2 to convert your OTF2 traces

Depending on your use case, you may want to pick one of the following options:

- **Container-first workflow (recommended):** [container/README.md](container/README.md)
- **Local/native workflow with your own Chapel and OTF2 install:** [docs/quickstart.md](docs/quickstart.md)
- **Developer and repository documentation:** [docs/README.md](docs/README.md)

## Recommended Workflow

If you want the shortest path to a working FastOTF2 environment, use the container guide.
It walks through the full process in order:

1. Prepare the required container inputs.
2. Build the container.
3. Launch the container.
4. Build `FastOTF2Converter` inside the container.
5. Run it against one of the bundled traces.

The bundled traces used throughout the documentation live under [sample-traces](sample-traces).

## Repository Layout

- [apps/FastOTF2Converter](apps/FastOTF2Converter): primary user-facing trace-to-table application
- [src](src) and [Mason.toml](Mason.toml): reusable FastOTF2 Chapel library
- [example](example): root Mason examples for the library package
- [comparisons](comparisons): comparison material in C and Python
- [container](container): container build and runtime workflow
- [docs](docs): native-build guidance, architecture notes, benchmarks, tutorials, and other developer-focused material

## Primary Commands

Inside the container or any local environment where Chapel and OTF2 are already available:

```bash
cd apps/FastOTF2Converter
mason build --release
mason run --release -- ../../sample-traces/simple-mi300-example-run/traces.otf2
```

To run against a different trace, replace the final positional path with your own OTF2 archive.
Use `--format=CSV` explicitly if you want to pin the default behavior, or `--format=PARQUET` to exercise the current unimplemented stub path.

Use `--release` for normal builds and runs. Mason adds Chapel's `--fast` automatically for release builds, so `--fast` is not included in the package `compopts` by default.

## Additional Reading

- [container/README.md](container/README.md): full container walkthrough for users
- [docs/quickstart.md](docs/quickstart.md): native/local build and run workflow
- [docs/README.md](docs/README.md): developer docs index
- [DEMO.md](DEMO.md): OTF2 walkthrough and project background
