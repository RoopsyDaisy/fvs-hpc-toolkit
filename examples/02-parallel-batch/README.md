# 02 · parallel batch — many runs at once (incl. Monte Carlo)

**Pattern:** the workhorse — generate **N keyword files** from an inventory, run
them as a **SLURM array** (one task per file, fanned across compute nodes), collect
per-run outputs. Each run is independent → embarrassingly parallel. A **parameter
sweep / Monte Carlo** is the same pattern with the keyword files varied by
treatment.

**When to reach for it:** running the same kind of simulation over many stands or
many parameter settings, where the logic fits in keyword / Event-Monitor records.
If you need R *between cycles*, use [03-rfvs-insim](../03-rfvs-insim/) instead.

Uses the bundled 3-stand sample, so it runs from a clone with no data to supply.
This page is **self-contained** — start here and follow it top to bottom; you do
not need to have run example 01 first.

## Setup — do this first

Copy-paste this whole block. It pulls the engine image, points at your clone +
the sample inventory, makes a fresh work dir on scratch, and then **fails loudly
if anything is unset** — which beats a cryptic `apptainer` error three commands
later.

```bash
# 1. Engine image onto scratch (skip the pull if you already have it).
#    NOTE: the :ie tag MOVES. To refresh an existing image, `rm -f fvs_ie.sif` first
#    (or add `--force`) — a plain pull won't overwrite, so you'd silently keep the old one.
cd /mnt/beegfs/scratch/$USER
[ -f fvs_ie.sif ] || apptainer pull fvs_ie.sif docker://ghcr.io/roopsydaisy/fvs-containers-engine:ie
#    (xattr "ENOTSUP … user.rootlesscontainers" warnings during the pull are normal
#     on scratch — it doesn't support user xattrs. Harmless; the pull still completes.)

# 2. The three things every command below needs.
export TK=$HOME/fvs-hpc-toolkit                    # your clone of this repo
export SIF=/mnt/beegfs/scratch/$USER/fvs_ie.sif    # the image you just pulled
export FVS_DATA_DIR=$TK/examples/inventory         # bundled 3-stand sample

# 3. A fresh work dir on scratch (outputs land here, never in the clone).
mkdir -p /mnt/beegfs/scratch/$USER/work-02 && cd /mnt/beegfs/scratch/$USER/work-02

# 4. Guard: stop now, with a clear message, if any of the three is unset.
: "${TK:?run the Setup block — TK is unset}" \
  "${SIF:?run the Setup block — SIF is unset}" \
  "${FVS_DATA_DIR:?run the Setup block — FVS_DATA_DIR is unset}"
[ -f "$SIF" ] || echo "WARNING: $SIF not found — pull it (Setup step 1)"
```

> Every `apptainer exec` below uses `--cleanenv --bind /mnt/beegfs`: `--bind` makes
> your scratch work dir reachable inside the container, and `--cleanenv` keeps the
> run reproducible (`--env` still passes the vars we need through). It's the same
> invocation the SLURM runners use.

## A — batch over stands

```bash
# 1. generate: inventory -> FVS_Data.db + one keyword file per stand  (light, in the image)
apptainer exec --cleanenv --bind /mnt/beegfs --env FVS_DATA_DIR="$FVS_DATA_DIR" "$SIF" \
  Rscript $TK/scripts/r_workflow/build_input_db.R    FVS_Data.db all
apptainer exec --cleanenv --bind /mnt/beegfs --env FVS_DATA_DIR="$FVS_DATA_DIR" "$SIF" \
  Rscript $TK/scripts/r_workflow/generate_keyfiles.R "$PWD" all 55
#  -> FVS_Data.db + one .key per stand + keyfiles.txt (the array manifest)

# 2. run: one array task per keyword file (the compute, on compute nodes)
sbatch --array=1-$(wc -l < keyfiles.txt)%50 --partition='cpu(all)' --account=afflecklab --time=00:15:00 \
  --export=SIF=$SIF,VARIANT=ie,MANIFEST=$PWD/keyfiles.txt,FVS_INPUT=$PWD/FVS_Data.db,CLUSTER_DIR=$TK/cluster \
  $TK/cluster/fvs_array.sbatch
squeue --me
```

Each task writes `runs/<stand>/FVSOut.db` (tables `FVS_Summary2`, …). Read any of
them with RSQLite — in the image:
`apptainer exec --bind /mnt/beegfs "$SIF" Rscript -e '...'`.

## B — parameter sweep / Monte Carlo

Same shape; swap `generate_keyfiles.R` for `generate_sweep.R`, which expands a
`(stand × treatment)` grid (here: a residual-BA thinning swept over several
targets), gives each cell its own run + `FVSOut.db`, and writes a
`sweep_manifest.csv` (run_id → parameters). (Run the **Setup** block above first.)

```bash
# 1. build the input DB, then the sweep keyfiles (baseline + thinnings per stand)
apptainer exec --cleanenv --bind /mnt/beegfs --env FVS_DATA_DIR="$FVS_DATA_DIR" "$SIF" \
  Rscript $TK/scripts/r_workflow/build_input_db.R sweep/FVS_Data.db CARB_2,CARB_3,CARB_4
SWEEP_RESID_BA="none,60,100,140" SWEEP_THIN_YEAR=2033 \
  apptainer exec --cleanenv --bind /mnt/beegfs --env FVS_DATA_DIR="$FVS_DATA_DIR" \
    --env SWEEP_RESID_BA --env SWEEP_THIN_YEAR "$SIF" \
  Rscript $TK/scripts/r_workflow/generate_sweep.R sweep CARB_2,CARB_3,CARB_4 55

# 2. run the whole sweep as one array
sbatch --array=1-$(wc -l < sweep/keyfiles.txt)%50 --partition='cpu(all)' --account=afflecklab --time=00:20:00 \
  --export=SIF=$SIF,VARIANT=ie,MANIFEST=$PWD/sweep/keyfiles.txt,FVS_INPUT=$PWD/sweep/FVS_Data.db,OUTROOT=r_sweep_runs,CLUSTER_DIR=$TK/cluster \
  $TK/cluster/fvs_array.sbatch

# 3. aggregate: join each run's summary back onto the parameters
cp $TK/examples/02-parallel-batch/aggregate.R .
apptainer exec --bind /mnt/beegfs "$SIF" Rscript aggregate.R sweep r_sweep_runs   # -> sweep_aggregated.csv
```

Sweep knobs (env): `SWEEP_RESID_BA` (`none` = baseline), `SWEEP_THIN_YEAR`,
`SWEEP_SAMPLE=N` (random subsample for a true Monte Carlo draw), `SWEEP_SEED`. To
sweep a *different* treatment, edit `treat_record()` in `generate_sweep.R`.

## Scale notes (for when this is large)

- **Array cap:** Hellgate's `MaxArraySize` is ~10,000. Past that, submit multiple
  arrays or group several stands per task (also amortizes the per-task container
  startup, which dominates these sub-second runs).
- **Throttle with `%N`** (e.g. `%50`) to be a good neighbor on a shared allocation.
- **Per-run output DBs, not one shared DB** — concurrent SQLite writers contend;
  aggregate afterward (and at very large N, make aggregation its own small job).
- Keep runs/outputs on **scratch**; move keepers to **projects**.
