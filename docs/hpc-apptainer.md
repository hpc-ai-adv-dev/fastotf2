# Running FastOTF2Converter on HPC Systems with Apptainer

This guide covers pulling and running the FastOTF2Converter container on HPC clusters using [Apptainer](https://apptainer.org/) (formerly Singularity).

## Quick Start: Direct Pull from GHCR

If the HPC login or compute nodes can reach `ghcr.io`:

```bash
module load apptainer
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
  -o fastotf2-converter.tar \
  ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest
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
module load apptainer
apptainer build fastotf2-converter.sif oci-archive://fastotf2-converter.tar
```

## Cross-Platform Notes

If you built or pulled the image on an ARM Mac and the HPC system is x86_64, make sure you have an `amd64` image. Build one with:

```bash
podman build --platform linux/amd64 \
  -f container/Containerfile \
  -t ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:amd64 .
```

Then export that tagged image instead.

## Multi-Locale (Multi-Node) Support

Multi-node execution across distributed HPC nodes is planned. When available, instructions will be added here.
