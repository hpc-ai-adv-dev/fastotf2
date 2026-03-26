# FastOTF2 in Containers

These are instructions for using a pre-built FastOTF2 container on a desktop, laptop, or HPC system.

The container ships with a pre-built `FastOTF2Converter` binary along with all dependencies (Chapel, OTF2, Apache Arrow, Parquet). No compilation, `mason build`, or language-specific toolchains are required to run a conversion.

Pre-built container images are published to the GitHub Container Registry (GHCR) at
`ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter`.
Every merge to `main` publishes a `:latest` image, and pull-request builds are available with `pr-<number>` tags. No local build is required — just pull and run.

The instructions are based on `podman`. Docker is still supported as an alternative, and the Docker commands are preserved below in expandable sections.

The first section shows a complete working example of pulling the container image and running a trace conversion on a desktop. The later sections provide more details about each step, dependency checks, and HPC migration.

## Table of Contents

- [Complete Working Example: Pull and Run FastOTF2 Container](#complete-working-example-pull-and-run-fastotf2-container)
- [Building the Container from Source](#building-the-container-from-source)
- [Install and Verify Required Dependencies](#install-and-verify-required-dependencies)
- [Container Layout and Mounted Paths](#container-layout-and-mounted-paths)
- [Troubleshooting](#troubleshooting)

## Complete Working Example: Pull and Run FastOTF2 Container

Here is a complete example of using the FastOTF2 container. This example demonstrates the full workflow from pulling the image to running a trace conversion, which should be usable as a practical foundation for trace conversion and optional FastOTF2 development.

This example demonstrates:

1. Pulling the pre-built container image from GHCR (one-time step, requires internet).
2. Running a trace conversion directly — no shell, no compilation needed.
3. Running the converter against your own OTF2 traces.
4. Optionally entering an interactive shell for development or advanced use.
5. An optional next step of exercising the root FastOTF2 library examples.

Once the image is pulled, the container works fully offline.

More details about the process, including setting up prerequisite software and troubleshooting tips, can be found in the later sections of this document.

### Prerequisites

Ensure you have the following:

- `podman` installed and working

If you prefer Docker, the alternative commands below assume `docker` is installed and working.

A local clone of the repository is **not** required to use the converter. You only need the repository if you want to build the image from source (see the fallback option in Step 1).

### Step 1: Pull the Pre-built Container

Pull the latest image from GHCR:

```bash
podman pull ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest
```

<details>
<summary>Docker alternative</summary>

```bash
docker pull ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest
```

</details>

If you need to build the image locally instead of pulling it, see [Building the Container from Source](#building-the-container-from-source).

### Step 2: Run a Trace Conversion

The converter runs directly — no shell needed. By default it prints the help message:

```bash
podman run --rm ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest
```

Run a conversion against the bundled sample trace:

```bash
podman run --rm ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest \
  /workspace/sample-traces/simple-mi300-example-run/traces.otf2
```

This above command is more of a sanity check to make sure things are wroking.
Without a volume mounted to see the result, it will output nothing
since the container is transient (removed at the end of the process).

You can also pass additional filters and output controls:

```bash
podman run --rm ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest \
  /workspace/sample-traces/simple-mi300-example-run/traces.otf2 \
  --format=CSV \
  --outputDir=/workspace/out \
  --excludeMPI \
  --log=DEBUG
```

<details>
<summary>Docker alternative</summary>

```bash
docker run --rm ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest
```

</details>

### Step 3: Run with Your Own Traces

Mount a host directory containing your OTF2 traces into `/workspace/` inside the container, then reference the mounted path:

```bash
podman run --rm \
  --volume /path/to/my/traces:/workspace/traces \
  ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest \
  /workspace/traces/traces.otf2 \
  --format=PARQUET \
  --outputDir=/workspace/traces/output
```

Output files will appear in `/path/to/my/traces/output/` on the host.

The `/workspace/` prefix is the same path convention used outside the container, so the same relative references work in both environments.

<details>
<summary>Docker alternative</summary>

```bash
docker run --rm \
  --volume /path/to/my/traces:/workspace/traces \
  ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest \
  /workspace/traces/traces.otf2 \
  --format=PARQUET \
  --outputDir=/workspace/traces/output
```

</details>

### Step 4: Advanced: Interactive Shell for Development

If you want to explore the container, do development against the FastOTF2 library, or run Mason commands directly, you can enter an interactive shell:

```bash
podman run -it --rm ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest bash
```

Once inside, you are in `/workspace` with the full repository, all dependencies, and the pre-built converter available. You can run Mason commands exactly as you would outside the container:

```bash
cd /workspace/apps/FastOTF2Converter
mason run --release -- /workspace/sample-traces/simple-mi300-example-run/traces.otf2
```

To mount the host repository for live editing:

```bash
podman run -it --rm \
  --volume "$(pwd):/workspace" \
  ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest bash
```

<details>
<summary>Docker alternative</summary>

```bash
docker run -it --rm ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest bash
```

Or with the host repository mounted:

```bash
docker run -it --rm \
  --volume "$(pwd):/workspace" \
  ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest bash
```

</details>

### Step 5: Optional Library Examples

If you also want to exercise the reusable FastOTF2 library package directly, enter an interactive shell (Step 4) and run the root Mason examples:

```bash
cd /workspace
mason build --release --example
mason run --release --example FastOtf2ReadArchive.chpl
mason run --release --example FastOtf2ReadEvents.chpl
```

This is useful when you want to inspect the lower-level OTF2 reading flow apart from the converter application.

### Step 6: Exit the Container

When finished with an interactive shell, exit the container:

```bash
exit
```

Because the run commands above all use `--rm`, the transient run container will be removed automatically after exit. The Docker alternatives behave the same way.

### Optional: Migrate the Container to HPC Systems

The pre-built GHCR image can be pulled directly into Apptainer on any HPC system that has outbound internet access. No desktop build, export, or file transfer is required.

#### Direct pull from GHCR (recommended)

If the HPC login or compute nodes can reach `ghcr.io`:

```bash
module load apptainer
apptainer pull fastotf2-converter.sif docker://ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest
```

This creates `fastotf2-converter.sif` ready to use.

#### Offline / air-gapped HPC systems

If the HPC system cannot reach the internet, export the image on a connected machine and transfer it manually.

1. On the desktop, save the image as an OCI archive:

```bash
podman save --format oci-archive -o fastotf2-converter.tar ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest
```

<details>
<summary>Docker alternative</summary>

Docker's `save` command produces a Docker-format tar, not an OCI archive.
To get an OCI archive compatible with the `oci-archive://` import below, use `buildx`:

```bash
docker buildx build \
  --platform linux/amd64 \
  --output type=oci,dest=fastotf2-converter.tar \
  -t ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest \
  -f container/Containerfile \
  .
```

If the image is already pulled and you don't want to rebuild, you can use
`docker save` instead, but then import with `docker-archive://` on the HPC side:

```bash
docker save -o fastotf2-converter.tar ghcr.io/hpc-ai-adv-dev/fastotf2/fastotf2-converter:latest
# On the HPC system:
# apptainer build fastotf2-converter.sif docker-archive://fastotf2-converter.tar
```

</details>

2. Transfer `fastotf2-converter.tar` to the HPC system.

3. On the HPC system, convert the OCI archive to a SIF file:

```bash
module load apptainer
apptainer build fastotf2-converter.sif oci-archive://fastotf2-converter.tar
```

#### Running with Apptainer

Run a conversion directly on the HPC system:

```bash
apptainer run --bind /path/to/traces:/workspace/traces fastotf2-converter.sif \
  /workspace/traces/traces.otf2 --format=PARQUET --outputDir=/workspace/traces/output
```

Or enter an interactive shell for more advanced use:

```bash
apptainer shell --bind $(pwd):/workspace --pwd /workspace fastotf2-converter.sif
```

Inside the shell, run the same Mason commands you would use outside the container:

```bash
cd /workspace/apps/FastOTF2Converter
mason run --release -- /workspace/sample-traces/simple-mi300-example-run/traces.otf2
```

## Building the Container from Source

If you need to customize the image, work on a fork, or cannot pull from GHCR, you can build locally. This requires a local clone of the repository and internet access for fetching dependencies.

`Containerfile` is the single maintained build file in the `container/` directory. `Dockerfile` is a symlink to `Containerfile`.

### Build with Podman

From the **repository root**:

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

### Cross-platform Build (ARM Mac targeting x86_64 Linux)

If you are on an ARM-based Mac and need an x86_64 image for HPC systems:

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

Once built, the locally-tagged image works with all the same `podman run` / `docker run` / `apptainer` commands shown in the earlier sections.

## Install and Verify Required Dependencies

This section covers the software requirements for building and running the FastOTF2 container workflow.

### Quick Check if These Are Already on System

Use the following commands to check whether the required tools are already installed:

```bash
which podman
podman --version
which apptainer
```

If you plan to use the Docker alternatives instead, also check:

```bash
which docker
docker --version
```

`apptainer` is only needed if you intend to move the built image to an HPC system.

### Mac Installation and Setup

We recommend using Podman on macOS for this repository.

Install Podman with Homebrew:

```zsh
brew install podman
```

Initialize and start the Podman virtual machine:

```zsh
podman machine init
podman machine start
```

Then verify:

```zsh
podman --version
podman info
```

If the container build is killed due to memory pressure inside the Podman VM, recreate the machine with more memory before retrying the build:

```zsh
podman machine stop
podman machine rm
podman machine init --memory=4096
podman machine start
```

### Linux Installation and Setup

Install Podman and Apptainer using your distribution's package manager or the official installation instructions.

Then verify:

```bash
podman --version
podman info
apptainer --version
```

On some Linux systems, rootless container tools also require `/etc/subuid` and `/etc/subgid` entries for your user.

### Verifying Podman Installation

To verify that Podman is properly installed and working, run:

```bash
podman --version
podman info
podman images
podman run --rm hello-world
```

On macOS, it is also worth confirming that the virtual machine is running:

```bash
podman machine list
```

### Verifying Docker Installation

If you intend to use the Docker alternatives, verify that Docker is properly installed and working:

```bash
docker --version
docker info
```

### Verifying Apptainer Installation

To verify that Apptainer is properly installed and working, run:

```bash
apptainer --version
apptainer run docker://hello-world
```

The second command requires access to a container registry.

## Container Layout and Mounted Paths

The image contains the full repository pre-built at `/workspace`. The converter binary, sample traces, library source, and examples are all available there:

```text
/workspace/
├── Mason.toml
├── src/
├── example/
├── apps/
│   └── FastOTF2Converter/
│       └── target/release/FastOTF2Converter   (pre-built)
├── sample-traces/
├── comparisons/
└── docs/
```

The OTF2 installation is under `/opt/otf2` and Apache Arrow under `/opt/arrow`. Both are configured in `PKG_CONFIG_PATH` and `LD_LIBRARY_PATH`.

When mounting host directories for your own traces, mount them under `/workspace/` (e.g. `-v /path/to/traces:/workspace/traces`) so that paths are consistent with the outside-container workflow.

For the interactive development case, mounting the host repository to `/workspace` replaces the baked-in copy. You will need to rebuild with `mason build --release` inside the container after mounting.

## Troubleshooting

### If the Container Build Fails

- Ensure you have internet connectivity (the build downloads OTF2 and Apache Arrow sources).
- Check Podman itself with `podman info`.
- If you are using the Docker alternative instead, check `docker info`.
- If the Arrow CMake build fails, ensure the base image has `libsnappy-dev`, `libbrotli-dev`, `liblz4-dev`, and `libzstd-dev` (they are installed by the Containerfile, but network issues during `apt-get` could cause failures).

### If Mason Cannot Build What You Expect

Make sure you are invoking Mason from the correct package root:

```bash
# Root FastOTF2 library package
cd /workspace
mason build --release --example

# FastOTF2Converter application package
cd /workspace/apps/FastOTF2Converter
mason build --release
```

### If Chapel or OTF2 Appear to Be Missing Inside the Container

Verify the toolchain and dependency installs:

```bash
chpl --version
ls /opt/otf2/include/otf2
ls /opt/otf2/lib
pkg-config --modversion arrow parquet
ls /opt/arrow/lib
```

### If Trace Files Cannot Be Found

Remember that the repository is mounted at `/workspace`, so the bundled traces should be referenced from there:

```bash
ls /workspace/sample-traces
```

### If You Encounter HPC Migration Issues

- Make sure you used an OCI archive when exporting the container image.
- If you are moving from ARM macOS to x86_64 Linux, build with `--platform linux/amd64` and export that image.
- If the image works locally but not on the HPC system, test the SIF file directly with `apptainer inspect fastotf2-converter.sif` and `apptainer exec fastotf2-converter.sif chpl --version`.

## Additional Resources

- [../README.md](../README.md)
- [../docs/quickstart.md](../docs/quickstart.md)
- [../docs/README.md](../docs/README.md)
- [Chapel Language Documentation](https://chapel-lang.org/docs/)
- [OTF2 and Score-P Documentation](https://www.vi-hps.org/projects/score-p/)
