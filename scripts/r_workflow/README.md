# R workflows for FVS

R-based ways to generate FVS keyword files and drive the engine. These scripts
need R with `RSQLite`, `DBI`, and `rFVS` — which the **engine image** provides, so
run them through the container rather than bare system R:

```bash
apptainer exec fvs_ie.sif Rscript scripts/r_workflow/build_input_db.R …
```

(The examples below show bare `Rscript …` for brevity — prefix them with
`apptainer exec fvs_ie.sif` on the cluster, or run on a workstation that has those
R packages.) Because the engine is identical everywhere, a keyword file generated
here runs the same on the HPC batch.

There are two tracks, for two different needs:

| Track | Script(s) | When | How FVS is run |
| --- | --- | --- | --- |
| **Batch / scale** | `build_input_db.R`, `generate_keyfiles.R`, `generate_sweep.R` | many stands or scenarios, run in parallel | generates keyword files → the file-based batch (`cluster/`) runs them |
| **Interactive / in-sim R** | `project_stand.R` | you need R logic *between* FVS cycles, or per-cycle results in R | rFVS loads FVS as a library and steps through it |

Both reuse FVS's own R code rather than reinventing it: the batch generator is
`rFVS::fvsMakeKeyFile()`; the interactive driver is `rFVS::fvsInteractRun()`; the
flat-file writer is the course reference `write.FVSfiles()`
([../reference_scripts/fvs_keyword_file_functions.R](../reference_scripts/fvs_keyword_file_functions.R)).

## Track A — batch (R generates keyword files → file-based runner)

R builds an FVS input database from the inventory CSVs, then templates one
*database-style* keyword file per stand (each reads its records from the shared
`FVS_Data.db` via `DSNin`/`StandSQL`/`TreeSQL`, writes to its own `FVSOut.db`).
The keyword files are plain inputs to the existing batch runner — see
[../../cluster/README.md](../../cluster/README.md) for the SLURM/Apptainer path on Hellgate.

Run each step through the engine image, from the repo root (it supplies R +
`RSQLite` + `rFVS`). `SIF` is your pulled `fvs_ie.sif`; the inventory CSVs must be
in `data/` (see [`../../data/README.md`](../../data/README.md)).

```bash
SIF=/mnt/beegfs/scratch/$USER/fvs_ie.sif

# 1. inventory CSVs -> FVS_Data.db (FVS_StandInit + FVS_TreeInit tables)
apptainer exec "$SIF" Rscript scripts/r_workflow/build_input_db.R outputs/r_batch/FVS_Data.db all

# 2. one keyword file per stand + a keyfiles.txt manifest (55-year projection)
apptainer exec "$SIF" Rscript scripts/r_workflow/generate_keyfiles.R outputs/r_batch CARB_2,CARB_3,CARB_4 55

# 3. run the batch through the image (sequential; for many stands submit the
#    SLURM array in cluster/README.md instead of run_local)
SIF="$SIF" VARIANT=ie FVS_INPUT=$PWD/outputs/r_batch/FVS_Data.db \
  cluster/run_local.sh outputs/r_batch/keyfiles.txt outputs/r_runs
```

Results land in `outputs/r_runs/<STAND_ID>/FVSOut.db` (tables `FVS_Summary2`,
`FVS_Compute`, …). Use `STANDS=all` in step 2 to template every stand.

> On a **workstation** that already has R + `rFVS`/`RSQLite` and a native
> `FVS<variant>` binary, drop the `apptainer exec "$SIF"` prefixes in steps 1–2 and
> use `FVS_BIN=/dir/with/FVSie` instead of `SIF=` in step 3.

### Track A (sweep) — parameter sweep / Monte Carlo

To vary a treatment across runs (the Monte Carlo pattern), use
`generate_sweep.R` instead of `generate_keyfiles.R` at step 2. It expands a grid
of `(stand × treatment)` cells (`expand.grid`, optionally random-subsampled),
injects the treatment into each keyword file via
`fvsMakeKeyFile(moreKeywords=...)`, gives every cell a unique base name so each
gets its own run dir + `FVSOut.db`, and writes a `sweep_manifest.csv` mapping
`run_id → parameters`. The default treatment is a thin-from-below to a residual
basal area (`ThinBBA`), swept over `none,60,100,140` ft²/acre.

```bash
# 1. inventory CSVs -> FVS_Data.db (same as above)
Rscript scripts/r_workflow/build_input_db.R outputs/r_sweep/FVS_Data.db CARB_2,CARB_3,CARB_4

# 2. sweep keyfiles: baseline + 3 residual-BA thinnings at year 2033, per stand
SWEEP_RESID_BA="none,60,100,140" SWEEP_THIN_YEAR=2033 \
  Rscript scripts/r_workflow/generate_sweep.R outputs/r_sweep CARB_2,CARB_3,CARB_4 55

# 3. run the whole sweep through the same batch runner
FVS_BIN=.devcontainer/fvs-bin VARIANT=ie FVS_INPUT=$PWD/outputs/r_sweep/FVS_Data.db \
  cluster/run_local.sh outputs/r_sweep/keyfiles.txt outputs/r_sweep_runs
```

Env knobs: `SWEEP_RESID_BA` (comma list; `none` = un-thinned baseline),
`SWEEP_THIN_YEAR`, `SWEEP_SAMPLE=N` (randomly sample N grid cells for a true
Monte Carlo draw instead of the full grid), `SWEEP_SEED`. To sweep a *different*
treatment or an Event-Monitor threshold, edit `treat_record()` in the script —
the grid/manifest/batch plumbing is treatment-agnostic.

Aggregate the per-run `FVSOut.db` files back against the manifest with RSQLite:

```r
library(RSQLite)
man <- read.csv("outputs/r_sweep/sweep_manifest.csv", stringsAsFactors = FALSE)
agg <- do.call(rbind, lapply(seq_len(nrow(man)), function(i) {
  con <- dbConnect(SQLite(), file.path("outputs/r_sweep_runs", man$run_id[i], "FVSOut.db"))
  on.exit(dbDisconnect(con))
  s <- dbGetQuery(con, "SELECT Year, BA, Tpa, MCuFt FROM FVS_Summary2 ORDER BY Year, RowID")
  cbind(man[i, ], s)              # joins parameters onto every summary row
}))
```

> **Thinning-year rows.** FVS writes *two* `FVS_Summary2` rows in a treatment
> year — pre- and post-thin (the post-thin row comes second). Aggregate on a
> *post*-treatment year, or take the last row per `Year`, so a thinning shows up
> as the lower residual value rather than the pre-thin one. A residual target
> above the stand's standing BA is a no-op (you can't thin below what's there) —
> expected, not a bug.

## Track B — interactive (R drives FVS via rFVS)

For a single stand, generate a flat-file keyword + tree file, load the FVS shared
library, run it cycle-by-cycle, and pull per-cycle tree lists + the summary into R
in memory (no database). This is where you'd insert R logic that the keyword-file
Event Monitor can't express.

```bash
Rscript scripts/r_workflow/project_stand.R CARB_2 55
# -> outputs/r_project/CARB_2/{tree_list.csv,stand_summary.csv}
```

## Notes

- **Run method.** The batch runner invokes `FVS --keywordfile=name`, which works
  for both database-style and legacy flat-file keyword files (it derives the
  `.tre`/`.out`/`.trl` names from the keyword base name and runs non-interactively).
  Piping the keyword name on stdin (`echo name | FVS`) only works for
  database-self-contained keyword files; flat-file ones make FVS prompt for each
  filename interactively.
- **Exit codes.** FVS signals normal completion with `STOP 20` (and `STOP 10` for
  completed-with-warnings); both are success. The runner treats exit 0/10/20 as
  success. Per-stand data/keyword problems are logged to the `FVS_Error` table in
  the output DB, not the exit code.
- **Two keyword-file styles.** *Database-style* (what the GUI and
  `rFVS::fvsMakeKeyFile` produce) reads/writes via SQLite and feeds the batch.
  *Flat-file* (`write.FVSfiles`) pairs a `.key` with a `.tre` and suits the rFVS
  in-memory track.
