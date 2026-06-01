#!/usr/bin/env bash
# Run an FVS keyword-file batch sequentially with no scheduler or container --
# for testing the batch pattern, or on machines without SLURM/Apptainer. Mirrors
# what cluster/fvs_array.sbatch does per task (via the shared fvs_run_one.sh),
# but runs the native FVS<variant> binary instead of `apptainer exec`.
#
# Usage: run_local.sh <manifest> [output_root]
#   manifest    text file, one keyword-file path per line (blank/# lines skipped)
# Environment:
#   FVS_BIN     directory containing FVS<variant> (else it must be on PATH)
#   VARIANT     FVS variant (default ie)
#   FVS_INPUT   space-separated shared input files to stage into each run dir
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$(readlink -f "${1:?manifest file (one keyword-file path per line)}")"
OUTROOT="${2:-runs}"
mkdir -p "$OUTROOT"

n=0; fail=0
while IFS= read -r KEY || [ -n "$KEY" ]; do
  case "$KEY" in ''|\#*) continue ;; esac      # skip blanks and comments
  n=$((n + 1))
  if "$HERE/fvs_run_one.sh" "$KEY" "$OUTROOT"; then
    echo "[ok]   $KEY"
  else
    rc=$?
    echo "[FAIL] $KEY (exit $rc)"
    fail=$((fail + 1))
  fi
done < "$MANIFEST"

echo "---"
echo "ran $n keyword file(s); $fail failed; outputs under $OUTROOT/"
[ "$fail" -eq 0 ]
