#!/bin/bash
# SLURM array job: run one rFVS (stand x scenario) job per task inside the FVS
# Apptainer image. The R counterpart to fvs_array.sbatch -- instead of running
# the FVS CLI on a keyword file, each task runs the rFVS driver, which drives FVS
# as a library with the job's own between-cycle R logic. See example
# 03-rfvs-insim and scripts/r_workflow/rfvs_run_one.R.
#
#SBATCH --job-name=fvs-rfvs
#SBATCH --array=1-9%9                # set upper bound to your jobs.csv row count
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G                     # R + the FVS .so; bump for very large stands
#SBATCH --time=01:00:00
#SBATCH --output=logs/rfvs_%A_%a.out
#SBATCH --error=logs/rfvs_%A_%a.err
#
# Configure via environment (export before sbatch, or pass with --export=):
#   SIF          path to the FVS .sif                              (required)
#   JOBS         the jobs.csv manifest (run_id,stand_id,years,config) (required)
#   DRIVER       path to scripts/r_workflow/rfvs_run_one.R         (required)
#   OUTROOT      per-run output dirs                               (default r_rfvs_runs)
#   FVS_DATA_DIR inventory CSV dir (e.g. examples/inventory or your data/)
#   VARIANT      FVS variant -> FVS<variant>                       (default ie)
#   BIND         host path(s) to bind into the container           (default /mnt/beegfs)
#
# Build the manifest + size the array, e.g.:
#   Rscript scripts/r_workflow/generate_rfvs_jobs.R out CARB_2,CARB_3,CARB_4 80
#   sbatch --array=1-$(($(wc -l < out/jobs.csv)-1))%50 \
#     --export=SIF=$PWD/fvs_ie.sif,JOBS=$PWD/out/jobs.csv,DRIVER=$TK/scripts/r_workflow/rfvs_run_one.R,FVS_DATA_DIR=$FVS_DATA_DIR \
#     cluster/fvs_rfvs_array.sbatch
set -euo pipefail

SIF="$(readlink -f "${SIF:?set SIF to the FVS .sif}")"
JOBS="$(readlink -f "${JOBS:?set JOBS to the jobs.csv manifest}")"
DRIVER="$(readlink -f "${DRIVER:?set DRIVER to scripts/r_workflow/rfvs_run_one.R}")"
[ -f "$SIF" ]    || { echo "ERROR: SIF not found: $SIF" >&2; exit 1; }
[ -f "$JOBS" ]   || { echo "ERROR: JOBS not found: $JOBS" >&2; exit 1; }
[ -f "$DRIVER" ] || { echo "ERROR: DRIVER not found: $DRIVER" >&2; exit 1; }
OUTROOT="${OUTROOT:-r_rfvs_runs}"
BIND="${BIND:-/mnt/beegfs}"

mkdir -p logs "$OUTROOT"

# --cleanenv keeps the run reproducible; the image's own FVS_BIN/PATH survive it,
# and we pass the few vars the driver needs explicitly. --bind makes the toolkit
# clone (DRIVER + configs + inventory) and the work dir reachable inside.
apptainer exec --cleanenv --bind "$BIND" \
  --env FVS_DATA_DIR="${FVS_DATA_DIR:-}" --env VARIANT="${VARIANT:-ie}" --env IMAGE="$SIF" \
  "$SIF" Rscript "$DRIVER" "$JOBS" "$SLURM_ARRAY_TASK_ID" "$OUTROOT"

echo "Task ${SLURM_ARRAY_TASK_ID} done (outputs under ${OUTROOT}/)"
