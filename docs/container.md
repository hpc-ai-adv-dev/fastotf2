# Container Guide

Pre-built container images are published to the GitHub Container Registry (GHCR) at `ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter`. Every merge to `main` publishes a `:latest` image, and pull-request builds are available with `pr-<number>` tags.

- [Complete Working Example](#complete-working-example)
- [Building the Container from Source](#building-the-container-from-source)
- [Container Layout](#container-layout)
- [Troubleshooting](#troubleshooting)

## Complete Working Example

### Prerequisites

- [Podman](https://podman.io/) installed and working

<details>
<summary>Docker alternative</summary>

If you prefer Docker, substitute `docker` for `podman` in all commands below.

</details>

### Step 1: Pull the Pre-built Container

```bash
podman pull ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest
```

<details>
<summary>Docker alternative</summary>

```bash
docker pull ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest
```

</details>

If you need to build the image locally instead, see [Building the Container from Source](#building-the-container-from-source).

### Step 2: Run a Trace Conversion

By default the converter prints its help message:

```bash
podman run --rm ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest
```

Run against the bundled sample trace as a quick sanity check.
You will see processing output in the terminal, but no files are saved to the host since the container is removed at the end:

```bash
podman run --rm ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest \
  /workspace/fastotf2/sample-traces/simple-mi300-example-run/traces.otf2
```

To actually keep the output files, mount a host directory with `-v` and write into it:

```bash
mkdir -p "$(pwd)/fastotf2-out"

podman run --rm \
  -v $(pwd)/fastotf2-out:/data/output \
  ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest \
  /workspace/fastotf2/sample-traces/simple-mi300-example-run/traces.otf2 \
  --format=PARQUET \
  --outputDir=/data/output
```

Output files appear in `$(pwd)/fastotf2-out/` on the host.

You can also pass filters and output controls:

```bash
podman run --rm \
  -v $(pwd)/fastotf2-out:/data/output \
  ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest \
  /workspace/fastotf2/sample-traces/simple-mi300-example-run/traces.otf2 \
  --format=CSV \
  --outputDir=/data/output \
  --excludeMPI \
  --log=DEBUG
```

<details>
<summary>Docker alternative</summary>

```bash
docker run --rm ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest

docker run --rm \
  -v $(pwd)/fastotf2-out:/data/output \
  ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest \
  /workspace/fastotf2/sample-traces/simple-mi300-example-run/traces.otf2 \
  --format=PARQUET \
  --outputDir=/data/output
```

</details>

### Step 3: Run with Your Own Traces

Mount a host directory containing your OTF2 traces, then reference the mounted path:

```bash
podman run --rm \
  -v /path/to/my/traces:/data \
  ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest \
  /data/traces.otf2 \
  --format=PARQUET \
  --outputDir=/data/output
```

Output files appear in `/path/to/my/traces/output/` on the host.

<details>
<summary>Docker alternative</summary>

```bash
docker run --rm \
  -v /path/to/my/traces:/data \
  ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest \
  /data/traces.otf2 \
  --format=PARQUET \
  --outputDir=/data/output
```

</details>

### Step 4: Interactive Shell (Optional)

To explore the container or inspect the environment:

```bash
podman run -it --rm ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest bash
```

<details>
<summary>Docker alternative</summary>

```bash
docker run -it --rm ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest bash
```

</details>

For development workflows (rebuilding, running tests), see the [developer guide](developing.md).

## Migrate to HPC Systems

To run on an HPC cluster with Apptainer, see the dedicated guide: [hpc-apptainer.md](hpc-apptainer.md)

## Building the Container from Source

If you need to customize the image, work on a fork, or cannot pull from GHCR, build locally from the **repository root**:

```bash
podman build \
  -f container/Containerfile \
  -t ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest \
  .
```

<details>
<summary>Docker alternative</summary>

```bash
docker build \
  -f container/Containerfile \
  -t ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest \
  .
```

</details>

### Cross-Platform Build (ARM Mac → x86_64 Linux)

```bash
podman build \
  --platform linux/amd64 \
  -f container/Containerfile \
  -t ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:amd64 \
  .
```

<details>
<summary>Docker alternative</summary>

```bash
docker buildx build \
  --platform linux/amd64 \
  -f container/Containerfile \
  -t ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:amd64 \
  .
```

</details>

## Container Layout

The image contains the full repository at `/workspace/fastotf2` with a pre-built converter binary. OTF2 is installed at `/opt/otf2` and Apache Arrow at `/opt/arrow`. Both are configured in `PKG_CONFIG_PATH` and `LD_LIBRARY_PATH`.

When mounting host directories, mount them under `/data` (or any path you prefer) so that paths stay consistent.

## Troubleshooting

**Build fails?**
- Check internet connectivity (the build downloads OTF2 and Apache Arrow sources).
- Run `podman info` (or `docker info`) to verify your container runtime.
- On macOS, if the build is killed by memory pressure, give the Podman VM more memory: `podman machine stop && podman machine rm && podman machine init --memory=4096 && podman machine start`.

**Traces not found?**
- Verify your volume mount maps the right host path. Inside the container, bundled traces are at `/workspace/fastotf2/sample-traces/`.

**Missing toolchain inside the container?**
- Run `chpl --version` and `pkg-config --modversion arrow parquet` to verify the install.

## Next Steps

- [Running on HPC systems with Apptainer](hpc-apptainer.md)
- [Developing and extending FastOTF2](developing.md)
- [Chapel Language Documentation](https://chapel-lang.org/docs/)
- [OTF2 and Score-P Documentation](https://www.vi-hps.org/projects/score-p/)
