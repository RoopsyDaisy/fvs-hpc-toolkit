# Running FVS at scale on an HPC cluster (Hellgate)

This directory runs the prebuilt FVS engine image (FVS + R + rFVS, published from
[fvs-containers](https://github.com/RoopsyDaisy/fvs-containers))
for batch use on an Apptainer + SLURM cluster such as the University of
Montana's **Hellgate** Research cluster
([`hellgate.rci.umt.edu`](https://www.umt.edu/it/rci/hellgate/)). The cluster path
is for large simulation campaigns — many keyword files run in parallel.

> This page documents the runner **mechanics + flags**. For the canonical,
> copy-pasteable end-to-end commands, use the [example workflows](../examples/) —
> they're the single source of truth for the `sbatch … --export=…` lines.

> **First time on the cluster?** Before any of step 1 below, run
> [`cluster/hellgate_probe.sh`](hellgate_probe.sh) once on the login node.
> It reports partitions, walltime caps, Apptainer + fakeroot, the storage
> layout, login-node registry egress, and runs one tiny SLURM smoke job to
> prove the end-to-end path is alive. The output (`hellgate_probe/report.md`)
> calibrates the defaults in `fvs_array.sbatch`.

## 1. Get the engine image (`.sif`)

Pull the published image onto scratch and convert it to a `.sif` in one step —
the validated default (no build, no auth):

```bash
cd /mnt/beegfs/scratch/$USER
apptainer pull fvs_ie.sif docker://ghcr.io/roopsydaisy/fvs-containers-engine:ie
```

*Only if login-node egress is closed or you need a custom build:* build the OCI
image in [fvs-containers](https://github.com/RoopsyDaisy/fvs-containers)
(`ENGINE=podman TARGETS=cluster scripts/build_images.sh`), convert it with
[`build_sif.sh`](build_sif.sh), and `scp fvs_ie.sif user@hellgate:/mnt/beegfs/scratch/<you>/`.

The image carries R + rFVS as well as the FVS CLI, so the R workflows
(`scripts/r_workflow/`) — keyword-file generation and the rFVS interactive
driver — run on Hellgate too, not just the bare `FVS` binary.

## 2. Stage inputs and build a manifest

Put your keyword files somewhere on the cluster filesystem and list them, one
per line. The array job runs line *N* on array task *N*.

```bash
ls inputs/*.key > keyfiles.txt
```

Each keyword file should reference its own input (inline `TREEDATA`, a `TREELIST`
file beside it, or a `DSNin` database). Outputs are written per-run, so reused
output names (`FVSOut.db`) don't collide.

If many keyword files share **one inventory database** (the typical "build a
batch in R" pattern), don't duplicate it — pass it via `FVS_INPUT` and the
runner symlinks it into each run directory so the keyword file's relative
`DSNin` resolves:

```bash
export FVS_INPUT="$PWD/inputs/FVS_Data.db"      # space-separated list if several
```

## 3. Submit the array job

```bash
sbatch --array=1-$(wc -l < keyfiles.txt)%50 \
       --export=SIF=$PWD/fvs_ie.sif,VARIANT=ie,MANIFEST=$PWD/keyfiles.txt,FVS_INPUT=$PWD/inputs/FVS_Data.db \
       cluster/fvs_array.sbatch
```

- `%50` throttles to 50 concurrent tasks — tune to your allocation.
- Add `--account=...`/`--partition=...` per Hellgate's policy.
- Drop `FVS_INPUT=...` if each keyword file is self-contained.
- Outputs land in `runs/<keyfile-name>/`; logs in `logs/fvs_<jobid>_<taskid>.{out,err}`.

The job runs `FVS<variant> --keywordfile=<name>` inside the container; Apptainer
bind-mounts the working directory, so all FVS output files appear on the host
filesystem under each run directory. (`--keywordfile=` is used rather than piping
the name on stdin because it works for both database-style and legacy flat-file
keyword files — for the latter FVS derives the `.tre`/`.out`/`.trl` names from the
keyword base name. A sibling `<base>.tre` next to a `.key` is staged into the run
dir automatically.)

## 4. Test the batch locally (no SLURM / Apptainer)

`run_local.sh` runs the same per-task logic (`fvs_run_one.sh`) sequentially
against a **native** `FVS<variant>` binary — useful for validating a batch on a
workstation, in the dev container, or in CI before submitting to the cluster:

```bash
FVS_BIN=.devcontainer/fvs-bin VARIANT=ie FVS_INPUT="$PWD/inputs/FVS_Data.db" \
  cluster/run_local.sh keyfiles.txt runs
```

It reports `[ok]`/`[FAIL] (exit N)` per keyword file and exits non-zero if any
run failed. FVS signals normal completion with `STOP 20` (and `STOP 10` for
completed-with-warnings); the runner treats exit 0/10/20 as success. (Verified
locally: a batch of keyword files each produces its own isolated `runs/<name>/`
with a populated output DB and no collisions.)

## Notes

- The per-task work (isolated run dir, stage `FVS_INPUT` + any sibling `.tre`,
  run `FVS --keywordfile=`) lives in `fvs_run_one.sh`, shared by both the SLURM
  array job and `run_local.sh` so the cluster and local paths stay identical —
  only the engine differs (`apptainer exec` vs the native binary).
- Apptainer on Hellgate aliases `singularity`; either command works.
- The `.sif` is variant-specific (it contains `FVSie`). Build one `.sif` per
  variant you need, or build a multi-variant image and set `VARIANT` accordingly.
- To post-process results, the per-run `FVSOut.db` SQLite files can be read in R
  (`DBI`/`RSQLite`) or any SQLite client — e.g. the R workflows under
  `scripts/r_workflow/` read them with `RSQLite`.
