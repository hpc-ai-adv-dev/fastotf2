# Running FastOTF2Converter on HPC Systems with Apptainer

This guide covers pulling and running the FastOTF2Converter container on HPC clusters using [Apptainer](https://apptainer.org/) (formerly Singularity).

## Quick Start: Direct Pull from GHCR

If the HPC login or compute nodes can reach `ghcr.io`:

```bash
apptainer pull fastotf2-converter.sif docker://ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest
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

If the HPC system cannot reach the internet, export the image on a connected machine and transfer it.

1. Save the image as an OCI archive on your desktop:

```bash
podman save --format oci-archive \
  -o fastotf2-converter-ofi.tar \
  ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter-ofi:latest
```

<details>
<summary>Docker alternative</summary>

Docker's `save` produces a Docker-format tar, not an OCI archive.
For an OCI archive compatible with `oci-archive://` import, use `buildx`:

```bash
docker buildx build \
  --platform linux/amd64 \
  --output type=oci,dest=fastotf2-converter.tar \
  -t ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest \
  -f container/Containerfile \
  .
```

Or use `docker save` and import with `docker-archive://` instead:

```bash
docker save -o fastotf2-converter.tar ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest
# On HPC: apptainer build fastotf2-converter.sif docker-archive://fastotf2-converter.tar
```

</details>

2. Transfer `fastotf2-converter.tar` to the HPC system.

3. Convert the OCI archive to a SIF file:

```bash
apptainer build fastotf2-converter-ofi.sif oci-archive://fastotf2-converter-ofi.tar
```

## Cross-Platform Notes

If you built or pulled the image on an ARM Mac and the HPC system is x86_64, make sure you have an `amd64` image. Build one with:

```bash
podman build --platform linux/amd64 \
  -f container/Containerfile \
  -t ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:amd64 .
```

Then export that tagged image instead.

## Building the OFI Image for HPC Fabric Support

The default container image uses the standard Chapel runtime. For multi-node execution on HPC systems with libfabric/CXI network fabrics (e.g., HPE Slingshot), you need an OFI-enabled image built with the appropriate Chapel base image.

Build the OFI variant by passing `--build-arg` to select the libfabric-enabled Chapel base:

```bash
# For systems with libfabric >= 2.3.1 (e.g., HPE systems with newer Slingshot)
podman build \
  --build-arg CHAPEL_BASE_IMAGE=docker.io/arezaiihpe/chapel-2.8.0-libfabric-2.3.1-cxi:latest \
  -f container/Containerfile \
  -t ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter-ofi:latest \
  .
```

```bash
# For Frontier (libfabric 1.22.0)
podman build \
  --build-arg CHAPEL_BASE_IMAGE=docker.io/arezaiihpe/chapel-2.8.0-libfabric-1.22.0-cxi:latest \
  -f container/Containerfile \
  -t ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter-ofi:latest \
  .
```

Then export and convert to SIF as described in the [Offline / Air-Gapped](#offline--air-gapped-hpc-systems) section, using the `-ofi` tagged image.

## Multi-Locale (Multi-Node) Support

Multi-node execution across distributed HPC nodes is planned. When available, instructions will be added here.
