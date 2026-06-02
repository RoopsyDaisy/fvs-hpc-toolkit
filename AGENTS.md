# AGENTS.md — contributor & agent notes for fvs-hpc-toolkit

Orientation + the hard-won gotchas, so a fresh contributor (or agent) doesn't
re-learn them. User-facing docs are the [README](README.md), the
[example workflows](examples/), and [docs/HELLGATE.md](docs/HELLGATE.md).

## What this repo is

The **user-facing toolkit** for running FVS at scale on Apptainer + SLURM (built
for UM's Hellgate). It does **not** build FVS — it runs the prebuilt engine image
published from [fvs-containers](https://github.com/RoopsyDaisy/fvs-containers)
(`ghcr.io/roopsydaisy/fvs-containers-engine:ie`). Two repos, coupled only by that
image. **Toolkit changes go to `main`** — direct for trivial edits, but **push a
branch and let CI verify when the outcome is uncertain** (a new `.sbatch`/shellcheck,
a new test), then `git merge --ff-only`. The PR + CI flow is for fvs-containers
only (it rebuilds the live engine image).

## Architecture

- **`examples/`** is the front door — three runnable MVP workflows, each a real
  HPC pattern. **`scripts/` + `cluster/`** are the reusable machinery they call.
- Every workflow is **generate → SLURM array → aggregate**. Only the array is
  compute; it runs on **compute nodes**, never the login node. The interactive
  `apptainer shell` is for *developing* a workflow (one stand), not running
  campaigns.
- The three workflows: **01-single-run** (one job), **02-parallel-batch** (CLI
  array over keyfiles, incl. Monte Carlo sweep), **03-rfvs-insim** (rFVS drives
  FVS with per-job R logic, one (stand × scenario) per array task).

### Extension points
- **New treatment sweep:** edit `treat_record()` in `scripts/r_workflow/generate_sweep.R`.
- **New rFVS scenario:** drop an R file in `examples/03-rfvs-insim/configs/` defining
  `DESCRIPTION` + `HOOKS` (a named list of rFVS stop-point → function). The driver
  (`rfvs_run_one.R`) sources it per job — that's the whole extension surface.

## The contract (one assumption everything rests on)

A container that puts `FVS<variant>` (e.g. `FVSie`), `R`, and `rFVS` on `PATH`,
with `FVS_BIN=/opt/fvs/bin` set. The Hellgate **login node has no R of its own**,
so *every* R step runs inside the image — `apptainer shell` (interactive prep) or
`apptainer exec` (scripted / the array). Keygen needs `RSQLite`/`DBI`/`rFVS`, all
from the image.

## Gotchas (each cost real time this build)

**rFVS (workflow 03):**
- `fvsInteractRun(<StopPoint>=fn_or_codestring, SimEnd=fvsGetSummary)` runs hooks at
  named stop points (`BeforeEM1`,`AfterEM1`,…). Hook can be a function or an R string.
- **`fvsCutNow(propcut)` only works at the `AfterEM1` stop point** — rFVS enforces
  it (errors "can only be used at stoppoint 2" elsewhere). `propcut` is per live
  tree record (0 = keep, 1 = cut); scalar is recycled.
- Read state with `fvsGetTreeAttrs(vars)` (one row per live tree),
  `fvsGetEventMonitorVariables("Year")` (note the capital Y), `fvsGetSummary`.
- **`fvsGetSummary` returns a MATRIX, not a data.frame** — index with `s[,"col"]`
  (`$` fails). Basal area column is **`ATBA`**; removed TPA is `RTpa`.
- **Domain correctness:** `harvest_largest.R` is **TPA-weighted** — remove the
  largest stems until ~30% of *TPA* is cut, not 30% of *records* (records carry
  expansion factors, so record-quantile ≠ stem-quantile). Weight any cut rule by `tpa`.
- **Reproducibility:** `generate_rfvs_jobs.R` adds a per-job `seed`; `rfvs_run_one.R`
  `set.seed()`s it and stamps `run_info.txt` (seed, toolkit SHA, image, engine,
  timestamp). So stochastic hooks reproduce and every output carries provenance.

**R scripting:**
- Multi-line `if (...) a else b` at top level: **keep `else` trailing** the value
  line, or wrap in `{ }`. `else` at the start of a line is a parse error. (Bit us
  twice — in `project_stand.R`, `generate_rfvs_jobs.R`.)
- `data_paths.R` resolves inventory CSVs via **`FVS_DATA_DIR`** (relative →
  repo-root; absolute → as-is; default `data/`). The bundled sample is
  `examples/inventory` → `FVS_DATA_DIR=examples/inventory` runs from a clone.

**Cluster / Apptainer:**
- **Work-dir pattern:** the clone is *code* (home is fine — Apptainer auto-mounts
  it). Run from a **scratch work dir** and reference the clone by `$TK` path so
  outputs never land in the repo. Bind scratch into the container with
  `--bind /mnt/beegfs` (or `/mnt/beegfs/scratch`); home auto-mounts. A wrong `TK`
  (pointing nowhere) is the usual "cannot open file" inside the container.
- `cluster/fvs_run_one.sh` uses Apptainer **only if the binary exists** — so
  running `run_local.sh` *inside* an `apptainer shell` (where `$SIF` is inherited
  but there's no apptainer binary, and FVS is on PATH) falls through to native FVS
  instead of erroring. Keep that guard.
- Scripts self-locate / take explicit output paths — never rely on `repo_root`
  defaults for outputs (they'd write into the clone). `project_stand.R` and
  `rfvs_run_one.R` write under the current dir.

## Hellgate facts (confirmed via cluster/hellgate_probe.sh, 2026-06-01)

Account **`afflecklab`**; partition **`'cpu(all)'`** (keep the quotes — parens are
shell metachars; 2-day max walltime; avoid the preemptable default). Apptainer
1.3.3 on PATH (no module); **fakeroot unavailable** (pull/scp images, don't build
on-cluster); login-node egress to GHCR is open; **`MaxArraySize=10001`** (group
stands per task or submit multiple arrays beyond that); `DefMemPerCPU` ~1 MB so
always set `--mem`. Storage: run/output on **scratch** (`/mnt/beegfs/scratch/$USER`),
move keepers to **projects**. All three example workflows validated end-to-end on
Hellgate (see Status).

## Status

- **Verified locally + by CI** (the integration job runs the suite + a `run_local`
  batch against the published image): all R machinery, the three rFVS configs
  producing distinct trajectories (CARB_2 final BA 15/8/11 baseline/thin/harvest),
  the unit tests, and `tests/integration/test_rfvs_insim.R` (asserts baseline vs
  harvest_largest diverge).
- **Verified on Hellgate (2026-06-02): all three example workflows, end-to-end.**
  01 single run (job 2215378); 02 CLI array (job 2215900 — 3 stands, each
  `runs/<stand>/FVSOut.db` with a full `FVS_Summary2` projection); 03 rFVS array
  (job 2215904 — all 9 (stand × scenario) tasks, divergence matching the local
  baseline *exactly*: CARB_2 final BA 15/11/8 baseline/harvest_largest/thin_to_ba).
  Each example's README is now self-contained (a guarded Setup block), so a forester
  picks one and follows it top to bottom.
- **The `--bind`/absolute-`jobs.csv`-path break we predicted did not happen.** The
  clone under `$HOME` auto-mounts, so `rfvs_run_one.R`'s
  `normalizePath(..., mustWork=TRUE)` resolves each config inside the container;
  `--bind /mnt/beegfs` covers the scratch work dir (the sbatch sets it by default).
  A clone in an unusual, non-auto-mounted location would still need its own `--bind`.
- **Deferred until a real large campaign** (documented, not built): >10k array
  chunking, multi-stand-per-task grouping (amortize Apptainer cold-start), and a
  standalone aggregation job.

## Testing locally (no cluster)

```bash
# unit suite (pure R) + engine integration (needs FVS on PATH/FVS_BIN)
Rscript tests/run_tests.R
# a workflow against a native binary (dev container):
FVS_DATA_DIR=examples/inventory FVS_BIN=<dir with FVSie> VARIANT=ie \
  Rscript scripts/r_workflow/rfvs_run_one.R <jobs.csv> 1 r_rfvs_runs
```
CI (`.github/workflows/ci.yml`) runs the unit suite on host R, shellchecks
`cluster/*.sh` + `cluster/*.sbatch`, and runs the full suite + a `run_local` batch
+ the rFVS test against the **published image**. Can't run shellcheck/in-image
locally? Push a branch and poll
`api.github.com/repos/<owner>/<repo>/commits/<sha>/check-runs` (public, no auth).
