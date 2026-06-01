#!/bin/bash
# SLURM array job: run one FVS keyword file per task inside the FVS Apptainer image.
# Designed for Hellgate (Apptainer + SLURM); adjust account/partition as needed.
#
#SBATCH --job-name=fvs
#SBATCH --array=1-100%50           # set upper bound to your manifest's line count
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=01:00:00
#SBATCH --output=logs/fvs_%A_%a.out
#SBATCH --error=logs/fvs_%A_%a.err
#
# Configure via environment (export before sbatch, or edit defaults):
#   SIF        path to the FVS .sif                  (default: fvs_ie.sif)
#   VARIANT    FVS variant -> executable FVS<variant> (default: ie)
#   MANIFEST   text file, one keyword-file path per line (default: keyfiles.txt)
#   OUTROOT    directory for per-run output dirs     (default: runs)
#   FVS_INPUT  space-separated shared input files (e.g. inventory DB) to stage
#              into each run dir, for keyword files that read them via DSNIn
#   CLUSTER_DIR  dir holding fvs_run_one.sh  (default: $SLURM_SUBMIT_DIR/cluster)
#
# Build the manifest and size the array, e.g.:
#   ls inputs/*.key > keyfiles.txt
#   sbatch --array=1-$(wc -l < keyfiles.txt)%50 cluster/fvs_array.sbatch
set -euo pipefail

# Resolve paths first, then validate, then export -- so a missing SIF/MANIFEST
# fails loudly before submitting anything to apptainer/sed. (`readlink -f`
# returns 0 even for nonexistent paths, so an explicit existence check is needed.)
SIF="$(readlink -f "${SIF:-fvs_ie.sif}")"
MANIFEST="$(readlink -f "${MANIFEST:-keyfiles.txt}")"
[ -f "$SIF" ]      || { echo "ERROR: SIF not found: $SIF" >&2; exit 1; }
[ -f "$MANIFEST" ] || { echo "ERROR: MANIFEST not found: $MANIFEST" >&2; exit 1; }
export SIF
export VARIANT="${VARIANT:-ie}"
OUTROOT="${OUTROOT:-runs}"
CLUSTER_DIR="${CLUSTER_DIR:-${SLURM_SUBMIT_DIR:-.}/cluster}"

mkdir -p logs "$OUTROOT"

# Pick this task's keyword file (line N for array index N).
KEY="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$MANIFEST")"
[ -n "$KEY" ] || { echo "No manifest entry for task ${SLURM_ARRAY_TASK_ID}"; exit 1; }

# Per-task run via the shared runner (also used by run_local.sh): it makes an
# isolated output dir, stages FVS_INPUT, and runs FVS<variant> in the .sif
# (SIF is exported, so fvs_run_one.sh uses `apptainer exec`).
"${CLUSTER_DIR}/fvs_run_one.sh" "$KEY" "$OUTROOT"
echo "Task ${SLURM_ARRAY_TASK_ID} done: ${OUTROOT}/$(basename "${KEY%.*}")"
