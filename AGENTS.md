# AGENTS.md — contributor & agent notes for fvs-hpc-toolkit

Orientation + the hard-won gotchas, so a fresh contributor (or agent) doesn't
re-learn them. User-facing docs are the [README](README.md), the
[example workflows](examples/), and [docs/HELLGATE.md](docs/HELLGATE.md).

## What this repo is

The **user-facing toolkit** for running FVS at scale on Apptainer + SLURM (built
for UM's Hellgate). It does **not** build FVS — it runs the prebuilt engine image
published from [fvs-containers](https://github.com/RoopsyDaisy/fvs-containers)
(`ghcr.io/roopsydaisy/fvs-containers-engine:ie`). Two repos, coupled only by that
image. **Toolkit changes go straight to `main`** (no PR); the PR/CI flow is for
fvs-containers only.

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
move keepers to **projects**. Validated end-to-end on Hellgate: `apptainer exec
FVSie` on a compute node (job 2215378).

## Status

- **Verified locally** (dev container, native engine + bundled sample): all R
  machinery (build_input_db, generate_keyfiles, generate_sweep, project_stand,
  generate_rfvs_jobs, rfvs_run_one), the three configs producing distinct
  trajectories, and the unit tests.
- **Verified on Hellgate:** the engine path (single FVS run on a compute node).
- **Not yet run on Hellgate:** examples 01–03 as-written (the `apptainer exec` /
  `sbatch` paths) — that's the next pass.

## Testing locally (no cluster)

```bash
# unit suite (pure R) + engine integration (needs FVS on PATH/FVS_BIN)
Rscript tests/run_tests.R
# a workflow against a native binary (dev container):
FVS_DATA_DIR=examples/inventory FVS_BIN=<dir with FVSie> VARIANT=ie \
  Rscript scripts/r_workflow/rfvs_run_one.R <jobs.csv> 1 r_rfvs_runs
```
CI (`.github/workflows/ci.yml`) runs the unit suite on host R, shellchecks the
scripts, and runs the full suite + a `run_local` batch against the **published
image**.
