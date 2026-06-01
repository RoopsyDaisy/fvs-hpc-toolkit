# 03 · rFVS in-the-loop — R drives FVS, in parallel

**Pattern:** R drives FVS *as a library* (via `rFVS`), running your own logic
**between cycles** — decisions that read the live simulation state, which a static
keyword file / Event Monitor can't express. One **(stand × scenario)** job per
SLURM array task, where each scenario is a small **R config file** the driver
sources. This is the most flexible pattern and the template for custom research.

**When to reach for it:** you need to inspect the running stand (tree list, metrics)
mid-run and act on it — an R-computed harvest rule, a Monte Carlo decision drawn at
a cycle, coupling to external data. If your logic fits in keyword/Event-Monitor
records, use [02-parallel-batch](../02-parallel-batch/) instead — it's simpler and
faster.

## The pieces

| Piece | What it is |
| --- | --- |
| [`configs/`](configs/) | one `.R` file per scenario — defines `DESCRIPTION` + `HOOKS` (a named list of rFVS stop-point → function). **This is where your per-job logic lives.** |
| [`generate_rfvs_jobs.R`](../../scripts/r_workflow/generate_rfvs_jobs.R) | expands a (stand × config) grid → `jobs.csv` (one row per job) |
| [`rfvs_run_one.R`](../../scripts/r_workflow/rfvs_run_one.R) | the per-task driver: reads one `jobs.csv` row, runs FVS via `fvsInteractRun` with that job's hooks, writes `<run_id>/stand_summary.csv` |
| [`fvs_rfvs_array.sbatch`](../../cluster/fvs_rfvs_array.sbatch) | the SLURM array — task N runs row N |

The three bundled configs show the spectrum: `baseline` (no treatment),
`thin_to_ba` (cut a fixed proportion — the simplest R treatment), `harvest_largest`
(inspect the live tree list, cut the largest ~30% by DBH — the case that *needs* R).

## Run it (on Hellgate)

Setup as in the [toolkit README](../../README.md) — `TK`, `SIF`, a scratch work
dir. The sample inventory ships, so this runs from a clone with no data to supply.

**1. Generate the job grid** (light — a quick `apptainer exec`, no compute):

```bash
export FVS_DATA_DIR=$TK/examples/inventory          # bundled 3-stand sample
apptainer exec --env FVS_DATA_DIR="$FVS_DATA_DIR" "$SIF" \
  Rscript $TK/scripts/r_workflow/generate_rfvs_jobs.R "$PWD/jobs" CARB_2,CARB_3,CARB_4 80
#  -> jobs/jobs.csv : 9 jobs (3 stands x 3 scenarios)
```

**2. Submit the array** (the compute — one task per job, on compute nodes):

```bash
N=$(($(wc -l < jobs/jobs.csv) - 1))                 # rows minus header
sbatch --array=1-$N%9 --partition='cpu(all)' --account=afflecklab --time=00:20:00 \
  --export=SIF=$SIF,JOBS=$PWD/jobs/jobs.csv,DRIVER=$TK/scripts/r_workflow/rfvs_run_one.R,FVS_DATA_DIR=$FVS_DATA_DIR \
  $TK/cluster/fvs_rfvs_array.sbatch
squeue --me
```

Each task writes `r_rfvs_runs/<stand>__<scenario>/stand_summary.csv` (+ `run_info.txt`).

**3. Aggregate / compare** (light — in the container):

```bash
apptainer exec "$SIF" Rscript -e '
  runs <- list.dirs("r_rfvs_runs", recursive=FALSE)
  rows <- do.call(rbind, lapply(runs, function(d){
    s <- read.csv(file.path(d,"stand_summary.csv"), check.names=FALSE)
    cbind(run_id=basename(d), s[s$Year==2083, c("Year","Tpa","ATBA")])
  }))
  print(rows, row.names=FALSE)'
```

Verified locally (native engine): the three scenarios diverge as expected — e.g.
CARB_2 final basal area is ~13 (baseline) vs ~7 (thin 50%) vs ~10 (harvest largest).

## Develop a new scenario

Copy a config, edit the hook — that's the whole extension point:

```r
# configs/my_rule.R
DESCRIPTION <- "My rule: ..."
HOOKS <- list(
  AfterEM1 = function() {           # runs each cycle at the AfterEM1 stop point
    yr  <- as.numeric(fvsGetEventMonitorVariables("Year"))
    ta  <- fvsGetTreeAttrs(c("dbh","ht","tpa"))   # inspect the live stand
    # ...decide in R...
    fvsCutNow(propcut)              # act: per-tree cut proportion (0..1)
  }
)
```

rFVS gives you `fvsGetTreeAttrs` / `fvsGetSummary` / `fvsGetEventMonitorVariables`
to read state and `fvsCutNow` / `fvsSetTreeAttrs` / `fvsAddActivity` / `fvsAddTrees`
to act. **`fvsCutNow` must run at `AfterEM1`** (rFVS enforces the stop point).
Drop the new config in `configs/`, regenerate the grid, resubmit — it's just one
more column in the fan-out.

> **Develop interactively, run as a batch.** To prototype one job, run the driver
> by hand inside an `apptainer shell` (`Rscript $TK/scripts/r_workflow/rfvs_run_one.R
> jobs/jobs.csv 1 r_rfvs_runs`). For a campaign, submit the array — never sit in a
> shell running the whole grid.
