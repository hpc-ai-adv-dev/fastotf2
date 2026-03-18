# FastOTF2 in Containers

These are instructions for creating and using a FastOTF2 container on a desktop or laptop, and for optionally migrating that environment to an HPC system.

The document assumes you do not already have Chapel, Mason, and OTF2 installed locally and would like to use containers for this workflow instead.

The instructions are based on `podman`. Docker is still supported as an alternative, and the Docker commands are preserved below in expandable sections.

The first section shows a complete working example of building and running FastOTF2 in a container on a desktop. The later sections provide more details about each step, dependency checks, and HPC migration.

## Table of Contents

- [Complete Working Example: Building and Running FastOTF2 Container on a Desktop or Laptop](#complete-working-example-building-and-running-fastotf2-container-on-a-desktop-or-laptop)
- [Install and Verify Required Dependencies](#install-and-verify-required-dependencies)
- [Container Layout and Mounted Paths](#container-layout-and-mounted-paths)
- [Troubleshooting](#troubleshooting)

## Complete Working Example: Building and Running FastOTF2 Container on a Desktop or Laptop

Here is a complete example of building and using the FastOTF2 container locally. This example demonstrates the full workflow from container build to running the primary trace conversion path, which should be usable as a practical foundation for FastOTF2 development and testing.

This example demonstrates:

1. Building the FastOTF2 container image.
2. Running the repository inside the container.
3. Building the `OTF2ToTable` Mason application inside the container.
4. Running a trace conversion against one of the bundled OTF2 traces.
5. An optional next step of exercising the root FastOTF2 library examples.

More details about the process, including setting up prerequisite software and troubleshooting tips, can be found in the later sections of this document.

### Prerequisites

Ensure you have the following:

- `podman` installed and working
- `podman compose` available on your system
- this `fastotf2` repository cloned locally
- the OTF2 source tarball `otf2-3.1.1.tar.gz` downloaded into this `container/` directory

If you prefer Docker, the alternative commands below assume `docker` plus the Compose plugin are installed and working.

On some systems, `podman compose` is provided by a separate compose provider. If `podman compose version` fails, install the provider your platform recommends before using the compose-based commands below, or use the `podman run` alternative commands instead.

The checked-in build expects the OTF2 tarball to be present locally before the build starts. `Containerfile` is the single maintained build file in this directory. For compose compatibility, `Dockerfile` is just a symlink to `Containerfile`.

### Step 0: Prepare the Environment

This step assumes access to the internet. Skip it if the necessary files are already available locally.

1. Clone the repository if you have not already done so.
2. Download `otf2-3.1.1.tar.gz` from the OTF2 release site: https://perftools.pages.jsc.fz-juelich.de/cicd/otf2/
   ```bash
   cd container/
   wget https://perftools.pages.jsc.fz-juelich.de/cicd/otf2/tags/otf2-3.1.1/otf2-3.1.1.tar.gz
   ```
3. Place that tarball in this `container/` directory so the container build can copy it into the image.

At this point, your `container/` directory should contain at least:

```text
container/
├── Containerfile
├── Dockerfile -> Containerfile
├── compose.yaml
├── README.md
└── otf2-3.1.1.tar.gz
```

### Step 1: Build the FastOTF2 Container

This step assumes access to the base image registry, OS package repositories, and the OTF2 tarball you placed in the previous step.

Now build the FastOTF2 container:

```bash
cd container
podman compose -f compose.yaml build
```

This command:

- builds the `fastotf2-dev` service from the checked-in `compose.yaml`
- uses the default `Dockerfile` path, which resolves to the same `Containerfile`
- produces the `localhost/fastotf2:latest` image used by the run step

If you prefer to avoid compose, the equivalent direct build is:

```bash
cd container
podman build \
  -f Containerfile \
  -t localhost/fastotf2:latest \
  .
```

<details>
<summary>Docker alternative</summary>

Use the checked-in Compose file:

```bash
cd container
docker compose -f compose.yaml build
```

Or build the image directly from the same `Containerfile`:

```bash
cd container
docker build \
  -f Containerfile \
  -t fastotf2:latest \
  .
```

</details>

### Step 2: Run the FastOTF2 Container

Launch the container and enter an interactive shell:

```bash
cd container
podman compose -f compose.yaml run --rm fastotf2-dev
```

This command:

- starts the `fastotf2-dev` service defined in `compose.yaml`
- mounts the repository checkout into `/workspace` inside the container
- starts an interactive shell in that mounted workspace
- removes the transient run container after you exit

If you prefer to avoid compose, the equivalent direct run is:

```bash
cd container
podman run -it --rm \
  --volume "$(cd .. && pwd -P):/workspace" \
  --workdir /workspace \
  localhost/fastotf2:latest
```


Once inside the container, you should be in `/workspace` with the full repository available.

<details>
<summary>Docker alternative</summary>

Use the checked-in Compose file:

```bash
cd container
docker compose -f compose.yaml run --rm fastotf2-dev
```

Or run the image directly:

```bash
cd container
docker run -it --rm \
  --volume "$(cd .. && pwd -P):/workspace" \
  --workdir /workspace \
  fastotf2:latest
```

</details>

### Step 3: Build OTF2ToTable Inside the Container

Once inside the container, build the primary FastOTF2 application:

```bash
cd /workspace/apps/OTF2ToTable
mason build --release
```

Use `--release` for normal builds and runs. Mason adds Chapel's `--fast` automatically for release builds, so `--fast` is not included in the package `compopts` by default.

This builds the main user-facing executable, `OTF2ToTable`.

### Step 4: Run a Trace Conversion Inside the Container

Run the converter against one of the bundled traces:

```bash
cd /workspace/apps/OTF2ToTable
mason run --release -- /workspace/sample-traces/simple-mi300-example-run/traces.otf2
```

You can also pass additional filters and output controls:

```bash
cd /workspace/apps/OTF2ToTable
mason run --release -- /workspace/sample-traces/simple-mi300-example-run/traces.otf2 \
  --metrics=metric1,metric2 \
  --processes=0,1 \
  --outputDir=./out \
  --format=CSV \
  --excludeMPI \
  --log=DEBUG
```

To run a different archive, replace the trace path after `--` with your own OTF2 archive.
`--format=PARQUET` is also accepted now, but currently exits with a clear unimplemented message rather than writing output files.

#### Expected Output

You should see the build complete and then trace-processing output from the converter. Depending on the options you selected, the run should produce generated files in the directory you passed through `--outputDir`, or in the tool's default output location if you did not override it.

### Step 5: Optional Library Examples

If you also want to exercise the reusable FastOTF2 library package directly, run the root Mason examples:

```bash
cd /workspace
mason build --release --example
mason run --release --example FastOtf2ReadArchive.chpl
mason run --release --example FastOtf2ReadEvents.chpl
```

This is useful when you want to inspect the lower-level OTF2 reading flow apart from the converter application.

### Step 6: Exit the Container

When finished, exit the container:

```bash
exit
```

Because the compose and direct-run commands both use `--rm`, the transient run container will be removed automatically after exit. The Docker alternatives above behave the same way.

### Optional: Migrate the Container to HPC Systems

After building and testing the container on a desktop or laptop, you can migrate that environment to an HPC system for further runs. This involves saving the image as an OCI archive and then converting it to an Apptainer SIF file.

1. On the desktop, save the Podman image as an OCI archive:

```bash
cd container
podman save --format oci-archive -o fastotf2-container.tar localhost/fastotf2:latest
```

On an ARM-based Mac targeting x86_64 Linux systems, you will usually want to build an x86_64 image first and then save that image:

```bash
cd container
podman build \
  --platform linux/amd64 \
  -f Containerfile \
  -t localhost/fastotf2:amd64 \
  .

podman save --format oci-archive -o fastotf2-container-amd64.tar localhost/fastotf2:amd64
```

<details>
<summary>Docker alternative</summary>

For Docker, use `buildx` to emit an OCI archive directly from the same `Containerfile`:

```bash
cd container
docker buildx build \
  --output type=oci,dest=fastotf2-container.tar \
  -t fastotf2:latest \
  -f Containerfile \
  .
```

On an ARM-based Mac targeting x86_64 Linux systems, you will usually want:

```bash
cd container
docker buildx build \
  --platform linux/amd64 \
  --output type=oci,dest=fastotf2-container-amd64.tar \
  -t fastotf2:amd64 \
  -f Containerfile \
  .
```

</details>

2. Transfer `fastotf2-container.tar` or `fastotf2-container-amd64.tar` to the HPC system.

3. On the HPC system, convert the OCI archive to a SIF file:

```bash
module load apptainer
apptainer build fastotf2.sif oci-archive://fastotf2-container.tar
```

If you exported the x86_64 image instead, use:

```bash
module load apptainer
apptainer build fastotf2-amd64.sif oci-archive://fastotf2-container-amd64.tar
```

4. Run the container on the HPC system with your workspace bound in:

```bash
apptainer shell --bind $(pwd):/workspace --pwd /workspace fastotf2.sif
```

5. Inside the container, run the same Mason commands you used on the desktop:

```bash
cd /workspace/apps/OTF2ToTable
mason run --release -- /workspace/sample-traces/simple-mi300-example-run/traces.otf2
```

## Install and Verify Required Dependencies

This section covers the software requirements for building and running the FastOTF2 container workflow.

### Quick Check if These Are Already on System

Use the following commands to check whether the required tools are already installed:

```bash
which podman
podman --version
podman compose version
which apptainer
```

If you plan to use the Docker alternatives instead, also check:

```bash
which docker
docker compose version
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
podman compose version
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

If you plan to use `podman compose`, also verify:

```bash
podman compose version
```

On some Linux systems, rootless container tools also require `/etc/subuid` and `/etc/subgid` entries for your user.

### Verifying Podman Installation

To verify that Podman is properly installed and working, run:

```bash
podman --version
podman info
podman compose version
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
docker compose version
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

When you launch the container with either the `podman compose` or direct `podman run` command above, the repository root is mounted into `/workspace`.

That means the paths you will use inside the container look like this:

```text
/workspace/
├── Mason.toml
├── src/
├── example/
├── apps/
│   └── OTF2ToTable/
├── sample-traces/
├── comparisons/
└── docs/
```

The OTF2 installation built into the image is available under `/opt/otf2`.

## Troubleshooting

### If the Container Build Fails

- Ensure you have internet connectivity.
- Ensure `otf2-3.1.1.tar.gz` is present in `container/`.
- Check Podman itself with `podman info`.
- If you are using the compose path, also check `podman compose version`.
- If you are using the Docker alternative instead, check `docker info` and `docker compose version`.

### If Mason Cannot Build What You Expect

Make sure you are invoking Mason from the correct package root:

```bash
# Root FastOTF2 library package
cd /workspace
mason build --release --example

# OTF2ToTable application package
cd /workspace/apps/OTF2ToTable
mason build --release
```

### If Chapel or OTF2 Appear to Be Missing Inside the Container

Verify the toolchain and OTF2 install:

```bash
chpl --version
ls /opt/otf2/include/otf2
ls /opt/otf2/lib
```

### If Trace Files Cannot Be Found

Remember that the repository is mounted at `/workspace`, so the bundled traces should be referenced from there:

```bash
ls /workspace/sample-traces
```

### If You Encounter HPC Migration Issues

- Make sure you used an OCI archive when exporting the container image.
- If you are moving from ARM macOS to x86_64 Linux, build with `--platform linux/amd64` and export that image.
- If the image works locally but not on the HPC system, test the SIF file directly with `apptainer inspect fastotf2.sif` and `apptainer exec fastotf2.sif chpl --version`.

## Additional Resources

- [../README.md](../README.md)
- [../docs/quickstart.md](../docs/quickstart.md)
- [../docs/README.md](../docs/README.md)
- [Chapel Language Documentation](https://chapel-lang.org/docs/)
- [OTF2 and Score-P Documentation](https://www.vi-hps.org/projects/score-p/)
