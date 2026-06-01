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
Setup (`TK`, `SIF`, scratch work dir, `FVS_DATA_DIR`) is in the
[toolkit README](../../README.md).

## A — batch over stands

```bash
export FVS_DATA_DIR=$TK/examples/inventory

# 1. generate: inventory -> FVS_Data.db + one keyword file per stand  (light, in the image)
apptainer exec --env FVS_DATA_DIR="$FVS_DATA_DIR" "$SIF" \
  Rscript $TK/scripts/r_workflow/build_input_db.R    FVS_Data.db all
apptainer exec --env FVS_DATA_DIR="$FVS_DATA_DIR" "$SIF" \
  Rscript $TK/scripts/r_workflow/generate_keyfiles.R "$PWD" all 55

# 2. run: one array task per keyword file (the compute)
sbatch --array=1-$(wc -l < keyfiles.txt)%50 --partition='cpu(all)' --account=afflecklab --time=00:15:00 \
  --export=SIF=$SIF,VARIANT=ie,MANIFEST=$PWD/keyfiles.txt,FVS_INPUT=$PWD/FVS_Data.db,CLUSTER_DIR=$TK/cluster \
  $TK/cluster/fvs_array.sbatch
squeue --me
```

Each task writes `runs/<stand>/FVSOut.db` (tables `FVS_Summary2`, …). Read any of
them with RSQLite — in the image: `apptainer exec "$SIF" Rscript -e '...'`.

## B — parameter sweep / Monte Carlo

Same shape; swap `generate_keyfiles.R` for `generate_sweep.R`, which expands a
`(stand × treatment)` grid (here: a residual-BA thinning swept over several
targets), gives each cell its own run + `FVSOut.db`, and writes a
`sweep_manifest.csv` (run_id → parameters).

```bash
# 1. build the input DB, then the sweep keyfiles (baseline + thinnings per stand)
apptainer exec --env FVS_DATA_DIR="$FVS_DATA_DIR" "$SIF" \
  Rscript $TK/scripts/r_workflow/build_input_db.R sweep/FVS_Data.db CARB_2,CARB_3,CARB_4
SWEEP_RESID_BA="none,60,100,140" SWEEP_THIN_YEAR=2033 \
  apptainer exec --env FVS_DATA_DIR="$FVS_DATA_DIR" --env SWEEP_RESID_BA --env SWEEP_THIN_YEAR "$SIF" \
  Rscript $TK/scripts/r_workflow/generate_sweep.R sweep CARB_2,CARB_3,CARB_4 55

# 2. run the whole sweep as one array
sbatch --array=1-$(wc -l < sweep/keyfiles.txt)%50 --partition='cpu(all)' --account=afflecklab --time=00:20:00 \
  --export=SIF=$SIF,VARIANT=ie,MANIFEST=$PWD/sweep/keyfiles.txt,FVS_INPUT=$PWD/sweep/FVS_Data.db,CLUSTER_DIR=$TK/cluster \
  $TK/cluster/fvs_array.sbatch

# 3. aggregate: join each run's summary back onto the parameters
cp $TK/examples/02-parallel-batch/aggregate.R .
apptainer exec "$SIF" Rscript aggregate.R sweep r_sweep_runs   # -> sweep_aggregated.csv
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
