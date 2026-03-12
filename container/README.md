# FastOTF2 in Containers

These are instructions for creating and using a FastOTF2 container on a desktop or laptop, and for optionally migrating that environment to an HPC system.

The document assumes you do not already have Chapel, Mason, and OTF2 installed locally and would like to use containers for this workflow instead.

The instructions are written around `docker compose` because that is what this repository ships today. If you prefer `docker` or `podman`, you can adapt the image build and run commands, but the supported commands in this repository use the files in this directory.

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
3. Building the `TraceToCSV` Mason application inside the container.
4. Running a trace conversion against one of the bundled OTF2 traces.
5. An optional next step of exercising the root FastOTF2 library examples.

More details about the process, including setting up prerequisite software and troubleshooting tips, can be found in the later sections of this document.

### Prerequisites

Ensure you have the following:

- `docker compose` installed and working
- this `fastotf2` repository cloned locally
- the OTF2 source tarball `otf2-3.1.1.tar.gz` downloaded into this `container/` directory

The Dockerfile expects the OTF2 tarball to be present locally before the build starts.

### Step 0: Prepare the Environment

This step assumes access to the internet. Skip it if the necessary files are already available locally.

1. Clone the repository if you have not already done so.
2. Download `otf2-3.1.1.tar.gz` from the OTF2 release site.
3. Place that tarball in this `container/` directory so the Docker build can copy it into the image.

At this point, your `container/` directory should contain at least:

```text
container/
├── Dockerfile
├── docker-compose.yml
├── README.md
└── otf2-3.1.1.tar.gz
```

### Step 1: Build the FastOTF2 Container

This step assumes access to the base image registry, OS package repositories, and the OTF2 tarball you placed in the previous step.

Now build the FastOTF2 container:

```bash
cd container
docker compose build
```

This command:

- builds from the repository Dockerfile in this directory
- installs Chapel and system build tools into the image
- builds and installs OTF2 into `/opt/otf2`
- prepares the container to mount the repository at `/workspace`

This build can take several minutes depending on your system and network connection.

### Step 2: Run the FastOTF2 Container

Launch the container and enter an interactive shell:

```bash
cd container
docker compose run --rm chapel-dev
```

This command:

- starts the `chapel-dev` service defined in `docker-compose.yml`
- mounts the repository checkout into `/workspace` inside the container
- starts an interactive shell in that mounted workspace
- removes the container after you exit

Once inside the container, you should be in `/workspace` with the full repository available.

### Step 3: Build TraceToCSV Inside the Container

Once inside the container, build the primary FastOTF2 application:

```bash
cd /workspace/apps/TraceToCSV
mason build --release
```

Use `--release` for normal builds and runs. Mason adds Chapel's `--fast` automatically for release builds, so `--fast` is not included in the package `compopts` by default.

This builds the main user-facing executable, `TraceToCSV`.

### Step 4: Run a Trace Conversion Inside the Container

Run the converter against one of the bundled traces:

```bash
cd /workspace/apps/TraceToCSV
mason run --release -- /workspace/sample-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2
```

You can also pass additional filters and output controls:

```bash
cd /workspace/apps/TraceToCSV
mason run --release -- /workspace/sample-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2 \
  --metrics=metric1,metric2 \
  --processes=0,1 \
  --outputDir=./out \
  --excludeMPI \
  --log=DEBUG
```

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

Because the recommended command uses `docker compose run --rm`, the container will be removed automatically after exit.

### Optional: Migrate the Container to HPC Systems

After building and testing the container on a desktop or laptop, you can migrate that environment to an HPC system for further runs. This involves saving the image as an OCI archive and then converting it to an Apptainer SIF file.

1. On the desktop, build an OCI archive from the same Dockerfile:

```bash
cd container
docker buildx build \
  --output type=oci,dest=fastotf2-container.tar \
  -t fastotf2:latest \
  .
```

On an ARM-based Mac targeting x86_64 Linux systems, you will usually want:

```bash
cd container
docker buildx build \
  --platform linux/amd64 \
  --output type=oci,dest=fastotf2-container.tar \
  -t fastotf2:latest \
  .
```

2. Transfer `fastotf2-container.tar` to the HPC system.

3. On the HPC system, convert the OCI archive to a SIF file:

```bash
module load apptainer
apptainer build fastotf2.sif oci-archive://fastotf2-container.tar
```

4. Run the container on the HPC system with your workspace bound in:

```bash
apptainer shell --bind $(pwd):/workspace --pwd /workspace fastotf2.sif
```

5. Inside the container, run the same Mason commands you used on the desktop:

```bash
cd /workspace/apps/TraceToCSV
mason run --release -- /workspace/sample-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2
```

## Install and Verify Required Dependencies

This section covers the software requirements for building and running the FastOTF2 container workflow.

### Quick Check if These Are Already on System

Use the following commands to check whether the required tools are already installed:

```bash
which docker
docker compose version
which apptainer
```

`apptainer` is only needed if you intend to move the built image to an HPC system.

### Mac Installation and Setup

We recommend using Docker Desktop on macOS for this repository because the checked-in workflow uses `docker compose` directly.

Install Docker Desktop and verify that it is running.

Then check:

```bash
docker --version
docker compose version
```

If the container build is killed due to memory pressure, increase Docker Desktop's memory allocation before retrying the build.

### Linux Installation and Setup

Install Docker Engine and the Docker Compose plugin using your distribution's package manager or the official Docker installation instructions.

Then verify:

```bash
docker --version
docker compose version
```

Ensure your user account has permission to run Docker commands.

### Verifying Docker Installation

To verify that Docker is properly installed and working, run:

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

When you launch the container with `docker compose run --rm chapel-dev`, the repository root is mounted into `/workspace`.

That means the paths you will use inside the container look like this:

```text
/workspace/
├── Mason.toml
├── src/
├── example/
├── apps/
│   └── TraceToCSV/
├── sample-traces/
├── comparisons/
└── docs/
```

The OTF2 installation built into the image is available under `/opt/otf2`.

## Troubleshooting

### If the Container Build Fails

- Ensure you have internet connectivity.
- Ensure `otf2-3.1.1.tar.gz` is present in `container/`.
- Check Docker itself with `docker info`.

### If Mason Cannot Build What You Expect

Make sure you are invoking Mason from the correct package root:

```bash
# Root FastOTF2 library package
cd /workspace
mason build --release --example

# TraceToCSV application package
cd /workspace/apps/TraceToCSV
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
- If you are moving from ARM macOS to x86_64 Linux, build with `--platform linux/amd64`.
- If the image works locally but not on the HPC system, test the SIF file directly with `apptainer inspect fastotf2.sif` and `apptainer exec fastotf2.sif chpl --version`.

## Additional Resources

- [../README.md](../README.md)
- [../docs/quickstart.md](../docs/quickstart.md)
- [../docs/README.md](../docs/README.md)
- [Chapel Language Documentation](https://chapel-lang.org/docs/)
- [OTF2 and Score-P Documentation](https://www.vi-hps.org/projects/score-p/)
