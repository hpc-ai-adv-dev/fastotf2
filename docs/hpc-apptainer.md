# Running FastOTF2Converter on HPC Systems with Apptainer

This guide covers pulling and running the FastOTF2Converter container on HPC clusters using [Apptainer](https://apptainer.org/) (formerly Singularity).

## Choosing the Right Image

For multi-node execution on HPC systems with libfabric/CXI network fabrics (e.g.,
HPE Slingshot), use an **OFI image** whose libfabric version matches the host.
These are built with libfabric-enabled Chapel base images and published to GHCR
by CI:

| Host | libfabric | Image |
|------|-----------|-------|
| Frontier | 1.22.0 | `fastotf2-converter-frontier` |
| HPC system with libfabric 2.3.1 | 2.3.1 | `fastotf2-converter-libfabric2.3.1` |
| Single-node / portable | n/a | `fastotf2-converter` (default, no fabric deps) |

Check the host's libfabric version to pick the matching image:

```bash
fi_info --version
# or
pkg-config --modversion libfabric
```

## Quick Start: Direct Pull from GHCR

If the HPC login or compute nodes can reach `ghcr.io`, pull the image that
matches your host. For example, on Frontier (libfabric 1.22.0):

```bash
apptainer pull fastotf2-converter.sif docker://ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter-frontier:latest
```

On a host with libfabric 2.3.1:

```bash
apptainer pull fastotf2-converter.sif docker://ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter-libfabric2.3.1:latest
```

This creates `fastotf2-converter.sif` ready to use.

## Running a Conversion

Bind-mount a directory containing your OTF2 traces and run:

```bash
apptainer run \
  --bind /path/to/traces:/data \
  fastotf2-converter.sif \
  /data/traces.otf2 \
  --format=PARQUET \
  --outputDir=/data/output
```

Output files appear in `/path/to/traces/output/` on the host filesystem.

For all available CLI options, see the [CLI reference](../apps/FastOTF2Converter/README.md) or run:

```bash
apptainer run fastotf2-converter.sif --help
```

## Interactive Shell

To explore the container or do development work on an HPC node:

```bash
apptainer shell --bind $(pwd):/workspace/fastotf2 --pwd /workspace/fastotf2 fastotf2-converter.sif
```

## Offline / Air-Gapped HPC Systems

If the HPC system cannot reach the internet, export the image on a connected
machine and transfer it. Substitute the image that matches your host
(`fastotf2-converter-frontier` or `fastotf2-converter-libfabric2.3.1`); the
examples below use the Frontier image.

1. Save the image as an OCI archive on your desktop:

```bash
podman save --format oci-archive \
  -o fastotf2-converter-frontier.tar \
  ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter-frontier:latest
```

<details>
<summary>Docker alternative</summary>

Docker's `save` produces a Docker-format tar, not an OCI archive.
For an OCI archive compatible with `oci-archive://` import, use `buildx`:

```bash
docker buildx build \
  --platform linux/amd64 \
  --output type=oci,dest=fastotf2-converter-frontier.tar \
  -t ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter-frontier:latest \
  -f container/Containerfile \
  .
```

Or use `docker save` and import with `docker-archive://` instead:

```bash
docker save -o fastotf2-converter-frontier.tar ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter-frontier:latest
# On HPC: apptainer build fastotf2-converter.sif docker-archive://fastotf2-converter-frontier.tar
```

</details>

2. Transfer `fastotf2-converter-frontier.tar` to the HPC system.

3. Convert the OCI archive to a SIF file:

```bash
apptainer build fastotf2-converter.sif oci-archive://fastotf2-converter-frontier.tar
```

## Cross-Platform Notes

If you built or pulled the image on an ARM Mac and the HPC system is x86_64, make sure you have an `amd64` image. Build one with:

```bash
podman build --platform linux/amd64 \
  -f container/Containerfile \
  -t ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:amd64 .
```

Then export that tagged image instead.

## Building the OFI Image for HPC Fabric Support (Optional)

CI publishes the OFI images (`fastotf2-converter-frontier` and
`fastotf2-converter-libfabric2.3.1`) to GHCR, so most users can simply pull them
as shown above. Building from source is only needed if you are working on a fork
or need to customize the image.

The default container image uses the standard Chapel runtime. For multi-node
execution on HPC systems with libfabric/CXI network fabrics (e.g., HPE
Slingshot), the OFI variants are built with the appropriate libfabric-enabled
Chapel base image.

Build a variant by passing `--build-arg` to select the libfabric-enabled Chapel
base, and tag it with the matching published name:

```bash
# Frontier (libfabric 1.22.0)
podman build \
  --build-arg CHAPEL_BASE_IMAGE=docker.io/arezaiihpe/chapel-2.8.0-libfabric-1.22.0-cxi:latest \
  -f container/Containerfile \
  -t ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter-frontier:latest \
  .
```

```bash
# HPC systems with libfabric 2.3.1
podman build \
  --build-arg CHAPEL_BASE_IMAGE=docker.io/arezaiihpe/chapel-2.8.0-libfabric-2.3.1-cxi:latest \
  -f container/Containerfile \
  -t ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter-libfabric2.3.1:latest \
  .
```

Then export and convert to SIF as described in the [Offline / Air-Gapped](#offline--air-gapped-hpc-systems) section, using the matching image name.

## Multi-Locale (Multi-Node) Support

Multi-node execution across distributed HPC nodes is planned. When available, instructions will be added here.
