#!/bin/bash
#SBATCH --job-name=fastotf2-converter
#SBATCH --nodes=4
#SBATCH --ntasks=4
#SBATCH --cpus-per-task=256
#SBATCH --exclusive
#SBATCH --output=fastotf2-converter-%j.out
#SBATCH --error=fastotf2-converter-%j.err
#SBATCH --time 12:00:00

set -euo pipefail

IMAGE="${IMAGE:-/lus/bnchlu1/khandeka/dev/hpc-ai-adv-dev/fastotf2/fastotf2-converter-ofi.sif}"
APP="${APP:-/workspace/fastotf2/apps/FastOTF2Converter/target/release/FastOTF2Converter_real}"
INPUT_TRACE="${INPUT_TRACE:-/traces/frontier-2-node-single-HPL-run/traces.otf2}"
OUTPUT_DIR="${OUTPUT_DIR:-/out/pq/tmp}"
FORMAT="${FORMAT:-PARQUET}"
STRATEGY="${STRATEGY:-locgroup_dist_block}"
LOCALES="${LOCALES:-${SLURM_NTASKS:-1}}"
SRUN_NODES="${SRUN_NODES:-${SLURM_NNODES:-1}}"
SRUN_TASKS="${SRUN_TASKS:-${SLURM_NTASKS:-1}}"
SRUN_CPUS_PER_TASK="${SRUN_CPUS_PER_TASK:-${SLURM_CPUS_PER_TASK:-1}}"
# Optional flags — set via --export to enable
TIMINGS_CSV_DIR="${TIMINGS_CSV_DIR:-}"   # non-empty → --timings-csv
MEM_TRACK="${MEM_TRACK:-}"               # non-empty → --memTrack

RUN_COMMAND=(
    e4s-cl launch --image "${IMAGE}" srun
    -N "${SRUN_NODES}"
    -n "${SRUN_TASKS}"
    --cpus-per-task="${SRUN_CPUS_PER_TASK}"
    --kill-on-bad-exit=1
    -- "${APP}"
    -nl "${LOCALES}"
    "${INPUT_TRACE}"
    --format="${FORMAT}"
    --outputDir="${OUTPUT_DIR}"
    --strategy="${STRATEGY}"
    --log=WARN
    --timings
)

# Conditionally append optional flags
[[ -n "${TIMINGS_CSV_DIR}" ]] && RUN_COMMAND+=(--timings-csv "${TIMINGS_CSV_DIR}")
[[ -n "${MEM_TRACK}" ]]      && RUN_COMMAND+=(--memTrack)

printf -v COMMAND_DISPLAY '%q ' "${RUN_COMMAND[@]}"
COMMAND_DISPLAY=${COMMAND_DISPLAY% }

START_TIME=$(date)
START_TIMESTAMP=$(date +%s)

cd "${SLURM_SUBMIT_DIR:-$PWD}"

"${RUN_COMMAND[@]}"

END_TIME=$(date)
END_TIMESTAMP=$(date +%s)
DURATION=$((END_TIMESTAMP - START_TIMESTAMP))

# append the metadata about this run in the .out file
{
    echo ""
    echo "========== RUN METADATA =========="
    echo "Job ID: ${SLURM_JOB_ID}"
    echo "Job Name: ${SLURM_JOB_NAME}"
    echo "Nodes: ${SLURM_NNODES}"
    echo "Tasks: ${SLURM_NTASKS}"
    echo "CPUs per task: ${SLURM_CPUS_PER_TASK:-1}"
    echo "Requested time: 02:00:00"
    echo ""
    echo "Configuration:"
    echo "  Image: ${IMAGE}"
    echo "  App: ${APP}"
    echo "  Input trace: ${INPUT_TRACE}"
    echo "  Output directory: ${OUTPUT_DIR}"
    echo "  Locales (-nl): ${LOCALES}"
    echo "  Format: ${FORMAT}"
    echo "  Strategy: ${STRATEGY}"
    echo "  Timings CSV dir: ${TIMINGS_CSV_DIR:-<not set>}"
    echo "  memTrack: ${MEM_TRACK:-<not set>}"
    echo ""
    echo "Execution:"
    echo "  Command: ${COMMAND_DISPLAY}"
    echo "  Start time: ${START_TIME}"
    echo "  End time: ${END_TIME}"
    echo "  Duration: ${DURATION} seconds"
    echo "=================================="
}
