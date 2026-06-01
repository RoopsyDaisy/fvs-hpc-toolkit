# R workflows for FVS

R-based ways to generate FVS keyword files and drive the engine. They need R with
`RSQLite`, `DBI`, and `rFVS` — all provided by the **engine image** — and the
Hellgate login node has no R of its own, so these run *inside the container*. Two
ways in:

- **Interactive (use this for prep):** `apptainer shell` into the image once, then
  run the steps with `Rscript`, `FVSie`, and `$FVS_BIN` all on `PATH`.
- **One-off / scripted:** `apptainer exec "$SIF" Rscript …`.

The at-scale **SLURM array** runs non-interactively via `apptainer exec` and is
covered in [`../../cluster/README.md`](../../cluster/README.md).

There are two tracks, for two different needs:

| Track | Script(s) | When | How FVS is run |
| --- | --- | --- | --- |
| **Batch / scale** | `build_input_db.R`, `generate_keyfiles.R`, `generate_sweep.R` | many stands or scenarios, run in parallel | generates keyword files → the file-based batch (`cluster/`) runs them |
| **Interactive / in-sim R** | `project_stand.R` | you need R logic *between* FVS cycles, or per-cycle results in R | rFVS loads FVS as a library and steps through it |

Both reuse FVS's own R code rather than reinventing it: the batch generator is
`rFVS::fvsMakeKeyFile()`; the interactive driver is `rFVS::fvsInteractRun()`; the
flat-file writer is the course reference `write.FVSfiles()`
([../reference_scripts/fvs_keyword_file_functions.R](../reference_scripts/fvs_keyword_file_functions.R)).

## Setup — a work dir on scratch, then shell into the image

Keep the clone as *code* and run in a separate **work dir** so outputs (the DB,
keyword files, `runs/`) land there, not in the repo:

```bash
export TK=$HOME/fvs-hpc-toolkit            # <-- set to WHEREVER you cloned this repo
export SIF=/mnt/beegfs/scratch/$USER/fvs_ie.sif         # the pulled engine image
export FVS_DATA_DIR=$TK/examples/inventory              # bundled 3-stand sample; omit to use your own data/

mkdir -p /mnt/beegfs/scratch/$USER/run1 && cd /mnt/beegfs/scratch/$USER/run1
apptainer shell --bind /mnt/beegfs/scratch "$SIF"       # enter the container
# the prompt is now  Apptainer>   — run the track steps below, then `exit`
```

`TK` must point at your actual clone — verify with `ls $TK/scripts` *before* you
shell in; a wrong `TK` is the usual cause of "cannot open file" errors inside.
The clone can live in home (Apptainer auto-mounts it); the **work dir** here is on
scratch, which `--bind /mnt/beegfs/scratch` makes visible inside the container.
Everything writes to the work dir (the current directory).

## Track A — batch (R generates keyword files → file-based runner)

R builds an FVS input database from the inventory CSVs, then templates one
*database-style* keyword file per stand (each reads its records from the shared
`FVS_Data.db` via `DSNin`/`StandSQL`/`TreeSQL`, writes to its own `FVSOut.db`).

Inside the container shell, from your work dir:

```bash
# 1. inventory CSVs -> FVS_Data.db (FVS_StandInit + FVS_TreeInit tables)
Rscript $TK/scripts/r_workflow/build_input_db.R FVS_Data.db all

# 2. one keyword file per stand + a keyfiles.txt manifest (55-year projection)
Rscript $TK/scripts/r_workflow/generate_keyfiles.R "$PWD" all 55

# 3. run the batch — FVS is on PATH in the shell, so no SIF/FVS_BIN needed
VARIANT=ie FVS_INPUT=$PWD/FVS_Data.db bash $TK/cluster/run_local.sh keyfiles.txt r_runs
```

Results land in `r_runs/<STAND_ID>/FVSOut.db` (tables `FVS_Summary2`,
`FVS_Compute`, …). Step 2 takes an explicit stand list (`CARB_2,CARB_3`) or `all`.

**For many stands, submit the SLURM array instead of `run_local`** — a batch job
is non-interactive, so run this *outside* the shell:

```bash
exit                                            # leave the container shell
sbatch --array=1-$(wc -l < keyfiles.txt)%50 \
       --partition='cpu(all)' --account=afflecklab --time=00:15:00 \
       --export=SIF=$SIF,VARIANT=ie,MANIFEST=$PWD/keyfiles.txt,FVS_INPUT=$PWD/FVS_Data.db,CLUSTER_DIR=$TK/cluster \
       $TK/cluster/fvs_array.sbatch
```

> **Workstation (no container):** if you have R + `rFVS`/`RSQLite` and a native
> `FVS<variant>` binary, run the `Rscript …` lines directly (no shell) and pass
> `FVS_BIN=/dir/with/FVSie` to `run_local.sh`.

### Track A (sweep) — parameter sweep / Monte Carlo

To vary a treatment across runs (the Monte Carlo pattern), use `generate_sweep.R`
instead of `generate_keyfiles.R` at step 2. It expands a grid of
`(stand × treatment)` cells (`expand.grid`, optionally random-subsampled), injects
the treatment into each keyword file via `fvsMakeKeyFile(moreKeywords=...)`, gives
every cell a unique base name so each gets its own run dir + `FVSOut.db`, and
writes a `sweep_manifest.csv` mapping `run_id → parameters`. The default treatment
is a thin-from-below to a residual basal area (`ThinBBA`), swept over
`none,60,100,140` ft²/acre.

Inside the container shell, from your work dir:

```bash
Rscript $TK/scripts/r_workflow/build_input_db.R FVS_Data.db CARB_2,CARB_3,CARB_4

SWEEP_RESID_BA="none,60,100,140" SWEEP_THIN_YEAR=2033 \
  Rscript $TK/scripts/r_workflow/generate_sweep.R "$PWD" CARB_2,CARB_3,CARB_4 55

VARIANT=ie FVS_INPUT=$PWD/FVS_Data.db bash $TK/cluster/run_local.sh keyfiles.txt r_sweep_runs
```

Env knobs: `SWEEP_RESID_BA` (comma list; `none` = un-thinned baseline),
`SWEEP_THIN_YEAR`, `SWEEP_SAMPLE=N` (randomly sample N grid cells for a true Monte
Carlo draw instead of the full grid), `SWEEP_SEED`. To sweep a *different*
treatment or an Event-Monitor threshold, edit `treat_record()` in the script —
the grid/manifest/batch plumbing is treatment-agnostic.

Aggregate the per-run `FVSOut.db` files back against the manifest with RSQLite.
Save this as `aggregate.R` in your work dir and run it in the shell
(`Rscript aggregate.R`):

```r
library(RSQLite)
man <- read.csv("sweep_manifest.csv", stringsAsFactors = FALSE)
agg <- do.call(rbind, lapply(seq_len(nrow(man)), function(i) {
  con <- dbConnect(SQLite(), file.path("r_sweep_runs", man$run_id[i], "FVSOut.db"))
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

Inside the container shell, from your work dir:

```bash
Rscript $TK/scripts/r_workflow/project_stand.R CARB_2 55
# -> r_project/CARB_2/{tree_list.csv,stand_summary.csv}
```

The engine `.so` resolves automatically from `$FVS_BIN` (the image sets it to
`/opt/fvs/bin`); pass a 3rd argument to override.

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
```
