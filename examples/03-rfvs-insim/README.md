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

This page is **self-contained** — start here and follow it top to bottom; you do
not need to have run examples 01 or 02 first.

> **Status (2026-06-02):** validated locally against a native engine (the three
> scenarios diverge as expected, below). The **SLURM array on Hellgate has not yet
> been run end-to-end** — the likely first snag is the `--bind` / absolute config
> paths in `jobs.csv` (see the note on step 2). If a job can't find its config,
> that's the spot to check.

## The pieces

| Piece | What it is |
| --- | --- |
| [`configs/`](configs/) | one `.R` file per scenario — defines `DESCRIPTION` + `HOOKS` (a named list of rFVS stop-point → function). **This is where your per-job logic lives.** |
| [`generate_rfvs_jobs.R`](../../scripts/r_workflow/generate_rfvs_jobs.R) | expands a (stand × config) grid → `jobs.csv` (one row per job) |
| [`rfvs_run_one.R`](../../scripts/r_workflow/rfvs_run_one.R) | the per-task driver: reads one `jobs.csv` row, runs FVS via `fvsInteractRun` with that job's hooks, writes `<run_id>/stand_summary.csv` |
| [`fvs_rfvs_array.sbatch`](../../cluster/fvs_rfvs_array.sbatch) | the SLURM array — task N runs row N |

The three bundled configs show the spectrum: `baseline` (no treatment),
`thin_to_ba` (cut a fixed proportion — the simplest R treatment), `harvest_largest`
(inspect the live tree list, remove the largest stems until ~30% of TPA is cut,
TPA-weighted — the case that *needs* R).

## Setup — do this first

Copy-paste this whole block. It pulls the engine image, points at your clone +
the sample inventory, makes a fresh work dir on scratch, and then **fails loudly
if anything is unset** — which beats a cryptic `apptainer` error later.

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
mkdir -p /mnt/beegfs/scratch/$USER/work-03 && cd /mnt/beegfs/scratch/$USER/work-03

# 4. Guard: stop now, with a clear message, if any of the three is unset.
: "${TK:?run the Setup block — TK is unset}" \
  "${SIF:?run the Setup block — SIF is unset}" \
  "${FVS_DATA_DIR:?run the Setup block — FVS_DATA_DIR is unset}"
[ -f "$SIF" ] || echo "WARNING: $SIF not found — pull it (Setup step 1)"
```

## Run it (on Hellgate)

**1. Generate the job grid** (light — a quick `apptainer exec`, no compute):

```bash
apptainer exec --cleanenv --bind /mnt/beegfs --env FVS_DATA_DIR="$FVS_DATA_DIR" "$SIF" \
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

> **The one path to watch.** `jobs.csv` stores each scenario's config as an
> **absolute path** into your clone, and the driver opens it with
> `normalizePath(..., mustWork=TRUE)` *inside* the container. The clone is under
> `$HOME` (Apptainer auto-mounts home) and the work dir is bound via `--bind
> /mnt/beegfs`, so both resolve — but if you put the clone somewhere exotic, bind
> it too. A task that dies with "No such file or directory" on its config is this.

Each task writes `r_rfvs_runs/<stand>__<scenario>/stand_summary.csv` (+ `run_info.txt`).

**3. Aggregate / compare** (light — in the container):

```bash
apptainer exec --bind /mnt/beegfs "$SIF" Rscript -e '
  runs <- list.dirs("r_rfvs_runs", recursive=FALSE)
  rows <- do.call(rbind, lapply(runs, function(d){
    s <- read.csv(file.path(d,"stand_summary.csv"), check.names=FALSE)
    cbind(run_id=basename(d), s[s$Year==max(s$Year), c("Year","Tpa","ATBA")])
  }))
  print(rows, row.names=FALSE)'
```

Expected (validated locally, native engine): the three scenarios diverge — e.g.
CARB_2 final-year (2103) basal area ~15 (baseline) vs ~8 (thin 50%) vs ~11
(harvest-largest), i.e. removing the *largest* stems leaves more BA than thinning
the same TPA share from across the diameter distribution. Seeing that spread is
how you know the per-job R logic actually fired.

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
