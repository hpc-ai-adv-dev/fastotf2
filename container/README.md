# Chapel OTF2 Development Container

This Docker container provides a development environment for working with the FastOTF2 Mason library package and the `TraceToCSV` Mason application package. The container includes Chapel, OTF2, and the dependencies needed to build and run the repository workflows.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Building the Container](#building-the-container)
- [Launching the Container](#launching-the-container)
- [Working with Chapel Programs](#working-with-chapel-programs)
- [Container Architecture](#container-architecture)
- [Migrating to HPC Systems (Apptainer)](#migrating-to-hpc-systems-apptainer)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before you begin, ensure you have the following:

1. **Docker Compose** installed on your system
2. **OTF2 3.1.1 tarball**: Download `otf2-3.1.1.tar.gz` from [https://perftools.pages.jsc.fz-juelich.de/cicd/otf2/](https://perftools.pages.jsc.fz-juelich.de/cicd/otf2/) and place it in the `container/` directory

Verify your Docker installation:
```bash
docker compose version
```

---

## Building the Container

**Important:** You must use Docker Compose to build this container as it includes the necessary OTF2 support and volume configurations.

```bash
cd container
docker compose build
```

This will:
1. Build the container image based on Chapel 2.6.0
2. Install OTF2 3.1.1 from the tarball in the `container/` directory
3. Configure all necessary environment variables
4. Set up the workspace directory structure

**Build time:** The initial build typically takes 5-10 minutes depending on your system.

---

## Launching the Container

Start the container in interactive mode:

If you're not already in the container directory, `cd` into it.

```bash
docker compose up -d
docker compose exec chapel-dev /bin/bash
```

The container will continue running in the background even after you `exit`.

To stop the container:

```bash
docker compose down
```

Or start and attach in one command (Recommended for transient containers):

```bash
docker compose run --rm chapel-dev
```


### Volume Mounts Explained

The container mounts two important directories:

- **`/traces`**: Contains OTF2 trace files from the repository's canonical `sample-traces/` path
- **`/workspace`**: Your repository checkout, including the Chapel package, apps, comparisons, and docs

Any changes you make in `/workspace` inside the container will be reflected in your host filesystem.

---

## Working with FastOTF2

Once inside the container, you'll find yourself in `/workspace` with access to the FastOTF2 library package at the repository root and the trace converter application package under `apps/TraceToCSV`.

### Primary Mason Workflows

The primary supported flows are:

1. **Repo root Mason package** - `mason build --release --example` and `mason run --release --example ...` for FastOTF2 proof-of-concept examples
2. **`apps/TraceToCSV/`** - `mason build --release`, `mason run --release`, and `mason run --release --example TraceToCSVSerial.chpl` for trace conversion

### Build System Overview

The primary build system is Mason.

- The root package is a library package exercised through Mason examples.
- The converter package is the primary user-facing application package.
- Use Mason's `--release` flag for normal builds and runs; it already enables Chapel's `--fast`, so `--fast` is not included in package `compopts` by default.

### Building Packages

From the repository root:

```bash
cd /workspace
mason build --release --example
```

From the converter package:

```bash
cd /workspace/apps/TraceToCSV
mason build --release
mason build --release --example
```

### Running Packages

Run root library examples:

```bash
cd /workspace
mason run --release --example FastOtf2ReadArchive.chpl
mason run --release --example FastOtf2ReadEvents.chpl
```

Run the primary converter:

```bash
cd /workspace/apps/TraceToCSV
mason run --release -- /workspace/sample-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2
```

Run the serial example path:

```bash
cd /workspace/apps/TraceToCSV
mason run --release --example TraceToCSVSerial.chpl
```

### Command-Line Arguments

The converter package's primary executable uses argument parsing for its main workflow.

#### Available Arguments

**Primary converter:**
- positional trace path
- `--trace=<path>`
- `--metrics=<csv-list>`
- `--processes=<csv-list>`
- `--outputDir=<path>`
- `--excludeMPI`
- `--excludeHIP`
- `--log=<NONE|ERROR|WARN|INFO|DEBUG|TRACE>`

**Serial example:**
- uses the older Chapel config-constant interface baked into the example-backed implementation

#### Usage Examples

```bash
# Root library example
cd /workspace
mason run --release --example FastOtf2ReadArchive.chpl

# Primary converter with explicit trace path
cd /workspace/apps/TraceToCSV
mason run --release -- /workspace/sample-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2

# Primary converter with additional filters
mason run --release -- /workspace/sample-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2 \
  --metrics=metric1,metric2 \
  --processes=0,1 \
  --outputDir=./out \
  --excludeMPI \
  --log=DEBUG

# Serial example path
mason run --release --example TraceToCSVSerial.chpl
```

### Common Workflow

Here's a typical development workflow:

```bash
# 1. Enter the container
docker compose run --rm chapel-dev

# 2. Build and run the root examples
cd /workspace
mason build --release --example
mason run --release --example FastOtf2ReadArchive.chpl

# 3. Build and run the converter package
cd /workspace/apps/TraceToCSV
mason build --release
mason run --release -- /workspace/sample-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2

# 4. Optionally build and run the serial example path
mason build --release --example
mason run --release --example TraceToCSVSerial.chpl

# 5. Make code changes as needed and rebuild
mason build --release
```

### Working with Multiple Projects

```bash
# Build and test the root library package examples
cd /workspace
mason build --release --example
mason run --release --example FastOtf2ReadArchive.chpl

# Build and test the converter application package
cd /workspace/apps/TraceToCSV
mason build --release
mason run --release -- /workspace/sample-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2

# Optionally exercise the serial example path
mason build --release --example
mason run --release --example TraceToCSVSerial.chpl
```

---

## Container Architecture

### Installed Components

- **Chapel 2.6.0**: Parallel programming language
- **OTF2 3.1.1**: Open Trace Format 2 library (installed in `/opt/otf2`)
- **Build tools**: gcc, make, cmake, pkg-config
- **Python 3**: For auxiliary scripts
- **Development libraries**: zlib, bz2, lz4, zstd, openssl

### Environment Variables

The following environment variables are pre-configured:

- `LD_LIBRARY_PATH=/opt/otf2/lib:$LD_LIBRARY_PATH` - OTF2 library path
- `CHPL_HOME` - Chapel installation directory (set by base image)

### Directory Structure

```
/workspace/                    # Your Chapel source code (mounted from host)
├── Mason.toml                 # Root FastOTF2 library manifest
├── src/                       # Root FastOTF2 library source
├── example/                   # Root Mason examples
├── apps/
│   └── TraceToCSV/
│       ├── Mason.toml         # Converter application manifest
│       ├── src/               # Primary converter source tree
│       └── example/           # Converter examples
├── sample-traces/             # Canonical bundled OTF2 trace inputs
├── comparisons/               # C and Python comparison material
└── docs/                      # Quickstart, comparisons, and tutorial material

/opt/otf2/                     # OTF2 installation
├── bin/
├── lib/
└── include/
```

---

## Migrating to HPC Systems (Apptainer)

After developing and testing your Chapel programs in the Docker container on your desktop, you can migrate the entire environment to an HPC system for production runs. This involves converting the Docker container to an Apptainer (formerly Singularity) SIF file.

### Prerequisites

- **Desktop**: Docker or Podman installed
- **HPC System**: Apptainer/Singularity installed
- **Compatible architectures**: Ensure both systems use the same architecture (e.g., x86_64)

### Step 1: Save the Container as an OCI Archive

On your **desktop system**, save the built container to a portable archive file:

#### Using Docker:

```bash
docker buildx build \
  --output type=oci,dest=chapel-dev.tar \
  -t chapel-dev:latest \
  .
```

If you're on mac, you'd also need to specify the platforms for cross-achitecture support:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --output type=oci,dest=chapel-dev.tar \
  -t chapel-dev:latest \
  .
```

#### Using Podman:

```bash
podman save --format oci-archive -o chapel-dev.tar chapel-dev:latest
```

This creates a `chapel-dev.tar` file containing the entire container image.

### Step 2: Transfer to HPC System

Transfer the archive file to your HPC system using your preferred method:

#### Using scp:

```bash
scp chapel-dev.tar username@hpc-system.domain:/path/to/destination/
```

#### Using rsync:

```bash
rsync -avz --progress chapel-dev.tar username@hpc-system.domain:/path/to/destination/
```

#### Using Globus or other HPC file transfer tools:

Follow your HPC center's guidelines for large file transfers.

### Step 3: Convert to Apptainer SIF

On the **HPC system**, convert the OCI archive to an Apptainer SIF file:

```bash
# Load Apptainer module (if required by your HPC system)
module load apptainer

# Convert OCI archive to SIF
apptainer build chapel-dev.sif oci-archive://chapel-dev.tar
```

This creates a `chapel-dev.sif` file, which is a single executable container image optimized for HPC environments.

### Step 4: Run on HPC System

#### Interactive Mode:

```bash
apptainer shell --bind /path/to/traces:/traces --bind /path/to/workspace:/workspace chapel-dev.sif
```

#### Execute Commands Directly:

```bash
# Run a specific Chapel program with default trace
apptainer exec --bind $(pwd):/workspace --pwd /workspace chapel-dev.sif \
  ./simple/otf2read

# Run with custom trace path
apptainer exec --bind $(pwd):/workspace --pwd /workspace chapel-dev.sif \
  ./simple/otf2read --tracePath=/traces/your-trace/traces.otf2
```

#### Run with Working Directory:

```bash
apptainer run --bind $(pwd):/workspace --pwd /workspace chapel-dev.sif
```

### Step 5: Use in HPC Job Scripts

You can integrate the Apptainer container into your SLURM or PBS job scripts:

#### SLURM Example:

```bash
#!/bin/bash
#SBATCH --job-name=chapel-otf2
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --time=01:00:00

module load apptainer

# Run Chapel program with custom trace path
apptainer exec --bind $(pwd):/workspace --pwd /workspace \
  chapel-dev.sif \
  ./simple/otf2read_parallel --tracePath=/traces/your-trace/traces.otf2

# Or run the converter package with Mason inside the container
apptainer exec --bind $(pwd):/workspace --pwd /workspace \
  chapel-dev.sif \
  bash -lc 'cd /workspace/apps/TraceToCSV && mason run --release -- /workspace/sample-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2 --metrics=metric1,metric2'

# Note: Ensure packages are built before running the job, or use Mason commands that build on demand.
```

### Architecture Migration Notes

- **Same Architecture (x86_64 → x86_64)**: Direct migration works seamlessly
- **Different Architecture (ARM → x86_64)**: You may need to:
  - Build the container directly on the HPC system, or
  - Use Docker's `--platform` flag during build: `docker build --platform linux/amd64 -t chapel-dev:latest .`

### Cleanup

After successfully migrating and testing:

```bash
# On desktop: remove the tar archive if no longer needed
rm chapel-dev.tar

# On HPC: keep the SIF file for future runs
# The SIF is read-only and can be shared among users
```

---

## Troubleshooting

### Container Won't Build

**Problem**: Build fails with network errors

**Solution**: Check your internet connection and Docker daemon status:
```bash
docker info
```

**Problem**: OTF2 installation fails

**Solution**: Ensure `otf2-3.1.1.tar.gz` is present in the `container` directory.

### Programs Won't Compile

**Problem**: Mason cannot find the package or example you expected to build

**Solution**: Make sure you're invoking Mason from the correct package root:
```bash
# Root FastOTF2 library package
cd /workspace
mason build --release --example

# Converter application package
cd /workspace/apps/TraceToCSV
mason build --release
```

**Problem**: Chapel compiler not found

**Solution**: Verify you're inside the container and Chapel is available:
```bash
chpl --version
```

**Problem**: OTF2 headers not found

**Solution**: Check OTF2 installation:
```bash
ls /opt/otf2/include/otf2
ls /opt/otf2/lib
```

### Runtime Errors

**Problem**: Trace files not found

**Solution**: Verify the volume mount and trace file path:
```bash
ls /traces
```

**Problem**: Library not found errors

**Solution**: Check library path:
```bash
echo $LD_LIBRARY_PATH
ldd /workspace/apps/TraceToCSV/target/debug/TraceToCSV
```

### Build System Questions

**Question**: What should I build first?

**Answer**: Start with the converter package using `cd /workspace/apps/TraceToCSV && mason build --release`, then use the root library examples if you want to inspect the reusable package surface directly.

**Question**: How do I run the serial converter path now?

**Answer**: Use the converter package example: `cd /workspace/apps/TraceToCSV && mason run --release --example TraceToCSVSerial.chpl`.

### Permission Issues

**Problem**: Cannot write to mounted volumes

**Solution**: Ensure Docker has proper permissions to access the mounted directories. On Linux, you may need to adjust file permissions or run Docker with appropriate user privileges.

### Performance Issues

**Problem**: Slow execution

**Solution**:
- Use parallel versions for large traces
- Ensure sufficient memory allocation to Docker:
  ```bash
  docker compose run --rm -e DOCKER_MEMORY=8g chapel-dev
  ```

### Issues migrating to HPC systems

**Problem**: The docker command to export to oci archive doesn't work:

On many standard Linux Docker installations (specifically those using the legacy storage backend), the default driver throws an error when you try to export type=oci.
This is not an issue with Docker desktop.

**Solution**:
- Switch to a different docker driver
```bash
docker buildx create --use --name oci-builder
```
- Try again to export the oci archive
- To switch back to the default driver :
```bash
docker buildx use default
docker buildx rm oci-builder
```

Alternatively, use the podman commands instead.

### Getting Additional Help

- **Chapel Documentation**: https://chapel-lang.org/docs/
- **OTF2 Documentation**: https://www.vi-hps.org/projects/score-p/
- **Container Issues**: Check Docker logs:
  ```bash
  docker logs chapel-dev
  ```

---

## Additional Resources

- [Chapel Language Documentation](https://chapel-lang.org/docs/)
- [OTF2 Documentation](https://www.vi-hps.org/projects/score-p/)
- [Docker Documentation](https://docs.docker.com/)
- [Apptainer Documentation](https://apptainer.org/docs/)

---

## License

This container configuration is part of the arkouda-telemetry-analysis project. Please refer to the project's LICENSE file for details.

## Contributing

For questions, issues, or contributions related to this container setup, please refer to the main project repository.
