# Scaling Workflows

Performance and memory scaling benchmarks for FastOTF2Converter using containerized
multi-node runs via [e4s-cl](https://github.com/arezaii/e4s-cl-setup).

## Notebooks

| Notebook | Purpose |
|----------|---------|
| `perf_matrix.ipynb` | Strong/weak scaling: conversion time vs node count and input size |
| `mem_matrix.ipynb` | Memory scaling: total memory vs input size, extrapolation to predict node requirements |

## Prerequisites

1. **e4s-cl setup** — clone and configure [e4s-cl-setup](https://github.com/arezaii/e4s-cl-setup) to create a profile for your system
2. **OFI container** — build the OFI-enabled SIF image (see [docs/hpc-apptainer.md](../../docs/hpc-apptainer.md))
3. **OTF2 traces** — HPL traces at various node counts (2, 4, 8, 16, 32, 128)
4. **Slurm cluster** — `sbatch`, `squeue`, `sacct` available on the login node

## Running

Notebooks can run interactively or headlessly as Python scripts.
See [MEM_RUN.md](MEM_RUN.md) and [PERF_RUN.md](PERF_RUN.md) for headless instructions.

Both can run concurrently — jobs use `--exclusive` and write to separate output directories.

## Configuration

Edit the **Configuration** cells at the top of each notebook:

- `IMAGE` — path to your `.sif` container image
- `E4S_SETUP_DIR` — path to your e4s-cl-setup checkout
- `HOST_OUT_ROOT` — where output/timings/logs land on the host filesystem
- `TRACE_INPUTS` — map of input sizes to host trace paths
- `HOST_TRACE_ROOT` / `CONTAINER_TRACE_ROOT` — bind mount mapping for traces

