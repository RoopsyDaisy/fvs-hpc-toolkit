#!/usr/bin/env bash
# Convert the FVS OCI image into an Apptainer/Singularity .sif for HPC use.
#
# Usage: cluster/build_sif.sh
#   IMAGE    OCI image to convert        (default: fvs-engine:<variant>)
#   VARIANT  FVS variant                 (default: ie)
#   SIF      output .sif path            (default: fvs_<variant>.sif)
#
# Build the OCI image first (the cluster target = FVS + R + rFVS), e.g.:
#   podman build -f docker/Dockerfile --target cluster -t fvs-engine:ie --build-arg FVS_VARIANT=ie .
#   # or: ENGINE=podman scripts/build_images.sh
#
# On Hellgate you can instead push the OCI image to a registry and
# `apptainer pull docker://<registry>/fvs-engine:ie` directly.
set -euo pipefail

VARIANT="${VARIANT:-ie}"
IMAGE="${IMAGE:-fvs-engine:${VARIANT}}"
SIF="${SIF:-fvs_${VARIANT}.sif}"

if   command -v apptainer  >/dev/null 2>&1; then APPT=apptainer
elif command -v singularity >/dev/null 2>&1; then APPT=singularity
else echo "ERROR: apptainer/singularity not found on PATH" >&2; exit 1; fi

# Export the OCI image to an archive and build the .sif from it (no registry needed).
TMPTAR="$(mktemp --suffix=.tar)"
trap 'rm -f "$TMPTAR"' EXIT
if   command -v podman >/dev/null 2>&1; then podman save -o "$TMPTAR" "$IMAGE"
elif command -v docker >/dev/null 2>&1; then docker save -o "$TMPTAR" "$IMAGE"
else echo "ERROR: need podman or docker to export ${IMAGE}" >&2; exit 1; fi

"$APPT" build "$SIF" "docker-archive://${TMPTAR}"
echo "Built ${SIF} from ${IMAGE}"
