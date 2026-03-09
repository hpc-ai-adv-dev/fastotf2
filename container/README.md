# Chapel OTF2 Development Container

This Docker container provides a complete development environment for working with Chapel programs that read and process OTF2 (Open Trace Format 2) trace files. The container includes Chapel 2.6.0, OTF2 3.1.1, and all necessary dependencies.

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
- **`/workspace`**: Your repository checkout, including the Chapel package, apps, examples, and docs

Any changes you make in `/workspace` inside the container will be reflected in your host filesystem.

---

## Working with Chapel Programs

Once inside the container, you'll find yourself in `/workspace` with access to several Chapel projects for OTF2 analysis.

### Available Projects

The workspace contains the following projects:

1. **`simple/`** - Basic OTF2 reading examples (3 variants: serial, parallel, parallel2)
2. **`read_events/`** - Event reading and processing (3 variants: serial, parallel, distributed)
3. **`read_events_and_metrics`** - Event and metric reading
4. **`trace_to_csv/`** - Convert OTF2 traces to CSV format (2 variants: serial, parallel)

### Build System Overview

The build system supports multiple Chapel execution modes:

- **Serial**: Single-threaded execution
- **Parallel**: Multi-threaded execution using tasks
- **Distributed**: Multi-locale distributed execution (where available)

**Important:** The top-level Makefile does **not** build anything. You must navigate into subdirectories to build programs.

### Building Programs

Each project directory has its own Makefile. To build programs, navigate to the specific directory:

```bash
# View top-level instructions
cd /workspace
make              # Shows instructions and available subdirectories
make help         # Shows detailed help

# Build in a specific directory
cd simple
make help         # View all available targets for this project
make              # Build all available versions (same as 'make all')
make all          # Build all available versions in this directory
make serial       # Build only the serial version
make parallel     # Build only the parallel version
make clean        # Clean build artifacts
make rebuild      # Clean and rebuild all

# Other project examples
cd /workspace/read_events
make all          # Build serial, parallel, and distributed versions

cd /workspace/trace_to_csv
make all          # Build serial and parallel versions
```

### Running Programs

After building, executables will be in their respective project directories. Version-specific builds may have suffixes:

- Base name (e.g., `otf2read`, `trace_to_csv`) - Serial version
- `*_parallel` - Parallel version
- `*_parallel2` - Alternative parallel version (where available)
- `*_distributed` - Distributed version (where available)

#### Example: Running the Simple OTF2 Reader

```bash
# Navigate to the project directory
cd /workspace/simple

# Build all versions (or just use 'make')
make all

# Or build just the serial version
make serial

# Run with default trace file (uses compiled-in default)
./otf2read

# Run with custom trace file via command-line argument
./otf2read --tracePath=/traces/your-trace-file/traces.otf2
```

#### Example: Running Parallel Version

```bash
# Navigate to the project directory
cd /workspace/simple

# Build parallel version
make parallel

# Run with default trace file
./otf2read_parallel

# Run with custom trace file via command-line argument
./otf2read_parallel --tracePath=/traces/your-trace-file/traces.otf2
```

### Command-Line Arguments

All Chapel programs now support command-line arguments using Chapel's `config const` feature. This allows you to override default values without recompiling.

#### Available Arguments

**All Programs:**
- `--tracePath=<path>` - Path to the OTF2 trace file (required for all programs)

**trace_to_csv and trace_to_csv_parallel:**
- `--tracePath=<path>` - Path to the OTF2 trace file
- `--crayTimeOffsetArg=<float>` - Time offset for Cray metrics (default: 1.0)
- `--metricsToTrackArg=<string>` - Comma-separated list of metrics to track
- `--processesToTrackArg=<string>` - Comma-separated list of processes to track (empty = all)

#### Usage Examples

```bash
# Simple OTF2 reader with custom trace
cd /workspace/simple
./otf2read --tracePath=/traces/my-trace/traces.otf2

# Parallel reader with custom trace
./otf2read_parallel --tracePath=/traces/my-trace/traces.otf2

# Read events with custom trace
cd /workspace/read_events
./otf2_read_events --tracePath=/traces/my-trace/traces.otf2

# Trace to CSV with all custom arguments
cd /workspace/trace_to_csv
./trace_to_csv --tracePath=/traces/my-trace/traces.otf2 \
               --crayTimeOffsetArg=2.5 \
               --metricsToTrackArg="metric1,metric2,metric3" \
               --processesToTrackArg="process1,process2"

# Use defaults (compiled-in values)
./trace_to_csv
```

### Common Workflow

Here's a typical development workflow:

```bash
# 1. Enter the container
docker compose run --rm chapel-dev

# 2. Navigate to the project directory you want to work with
cd simple

# 3. View available build targets
make help

# 4. Build the program
make              # Builds all available versions (default)
# or: make serial, make parallel, etc. for specific versions

# 5. List available trace files
ls /traces

# 6. Run your program with default trace path
./otf2read

# Or run with a custom trace file
./otf2read --tracePath=/traces/your-trace/traces.otf2

# 7. Make code changes as needed (files sync with host)
# Edit files using your host editor or vim inside the container

# 8. Rebuild (Make automatically detects changes)
make              # or: make serial, make rebuild, etc.

# 9. Test again
./otf2read --tracePath=/traces/your-trace/traces.otf2
```

### Working with Multiple Projects

```bash
# Build and test different projects
cd /workspace/simple
make              # Build all available versions
./otf2read --tracePath=/traces/your-trace/traces.otf2

cd /workspace/read_events
make              # Build all available versions
./otf2_read_events --tracePath=/traces/your-trace/traces.otf2

cd /workspace/trace_to_csv
make              # Build all available versions
./trace_to_csv --tracePath=/traces/your-trace/traces.otf2
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
├── Makefile                   # Top-level (instructions only, does not build)
├── Makefile.common            # Shared build rules and variables
├── _chpl/                     # Chapel OTF2 module files
├── simple/                    # Simple OTF2 examples
│   ├── Makefile               # Builds serial, parallel, parallel2 versions
│   ├── otf2read.chpl
│   ├── otf2read_parallel.chpl
│   ├── otf2read_parallel2.chpl
│   └── otf2read_parallel3.chpl
├── read_events/               # Event processing
│   ├── Makefile               # Builds serial, parallel, distributed versions
│   ├── otf2_read_events.chpl
│   ├── otf2_read_events_parallel.chpl
│   └── otf2_read_events_distributed.chpl
├── read_events_and_metrics/  # Event and metric processing
│   ├── Makefile              # Builds serial
│   └── read_events_metrics.chpl
└── trace_to_csv/              # Trace conversion
    ├── Makefile              # Builds serial and parallel versions
    ├── trace_to_csv.chpl
    ├── trace_to_csv_parallel.chpl
    └── CallGraph.chpl

/traces/                       # OTF2 trace files (mounted from host)
├── trace1/
├── trace2/
└── ...

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

# Or run trace_to_csv with multiple arguments
apptainer exec --bind $(pwd):/workspace --pwd /workspace \
  chapel-dev.sif \
  ./trace_to_csv/trace_to_csv --tracePath=/traces/your-trace/traces.otf2 \
                               --crayTimeOffsetArg=1.5 \
                               --metricsToTrackArg="metric1,metric2"

# Note: Ensure programs are built before running the job
# You can build them in the job script or build beforehand:
# cd /workspace/simple && make all
```

### Architecture Compatibility Notes

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

**Problem**: "No rule to make target" or "No such file or directory"

**Solution**: Make sure you're in the correct subdirectory, not the top-level `/workspace`:
```bash
# Wrong - top-level doesn't build
cd /workspace
make all          # This won't work!

# Correct - navigate to subdirectory
cd /workspace/simple
make all          # This works!
```

**Problem**: Chapel compiler not found

**Solution**: Verify you're inside the container and Chapel is available:
```bash
chpl --version
```

**Problem**: OTF2 headers not found

**Solution**: Check OTF2 installation:
```bash
ls /opt/otf2/include
pkg-config --cflags otf2
```

**Problem**: Make tries to build non-existent files

**Solution**: This has been fixed! Each subdirectory Makefile now only builds targets that have corresponding source files. Run `make help` in the subdirectory to see available targets.

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
ldd ./simple/otf2read
```

### Build System Questions

**Question**: Why doesn't the top-level `make` build anything?

**Answer**: This is by design! The new build system requires you to navigate to specific project subdirectories to build. This ensures:
- You know exactly what you're building
- Each project can have its own configuration
- Builds are more manageable and predictable

See `/workspace/MAKEFILE_GUIDE.md` for complete documentation.

**Question**: What targets are available in each subdirectory?

**Answer**: Run `make help` in any subdirectory to see available targets. Each project has different variants based on available source files.

**Question**: Can I just run `make` without specifying a target?

**Answer**: Yes! Running `make` (without arguments) is equivalent to `make all` and will build all available versions in that directory. This is the recommended approach for most builds.

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
