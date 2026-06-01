#!/bin/bash
# Run ONE FVS simulation on a compute node, inside the engine image.
# Submit with the image path in the environment, from this directory:
#     SIF=/mnt/beegfs/scratch/$USER/fvs_ie.sif sbatch run.sbatch
#
#SBATCH --job-name=fvs-single
#SBATCH --partition='cpu(all)'
#SBATCH --account=afflecklab
#SBATCH --time=00:10:00
#SBATCH --mem=2G
#SBATCH --cpus-per-task=1
#SBATCH --output=fvs_%j.out
#SBATCH --error=fvs_%j.err
set -euo pipefail

SIF="${SIF:?set SIF=/path/to/fvs_ie.sif (e.g. SIF=... sbatch run.sbatch)}"

echo ">>> node=$(hostname)  job=$SLURM_JOB_ID  cwd=$(pwd)"
apptainer exec --cleanenv "$SIF" FVSie --keywordfile=iet01.key
echo ">>> FVS exit code: $?   (0/10/20 = success; STOP 20 = normal completion)"
echo ">>> outputs:"
ls -la
