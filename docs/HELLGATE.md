# Running FVS in parallel on Hellgate (Apptainer + SLURM)

The runbook for batch FVS on the University of Montana **Hellgate** cluster
([`hellgate.rci.umt.edu`](https://www.umt.edu/it/rci/hellgate/)). Goal: build many
keyword (`.key`) files, then run them in parallel — one FVS invocation per file.

For a single-stand walkthrough first, see [example 01-single-run](../examples/01-single-run/);
the [example workflows](../examples/) cover single → parallel → rFVS-in-the-loop.

> **Validated on Hellgate (2026-06-01):** GHCR pull → `.sif` → SLURM → `apptainer
> exec FVSie` on a compute node, output on BeeGFS. The cluster facts below are
> from `cluster/hellgate_probe.sh`, not assumptions.

## Cluster facts (confirmed by the probe)

| Thing | Value |
| --- | --- |
| Login | `ssh <netid>@login.rci.umt.edu` (netID password), on campus eduroam / VPN |
| Home | `/mnt/beegfs/hellgate/home/<netid>` (500 GB, private) |
| Scratch | `/mnt/beegfs/scratch/<netid>` (5 TB) — **run + output here first** |
| Projects | `/mnt/beegfs/projects/<netid>` (10 TB) — **move keepers here after** |
| Apptainer | v1.3.3, on `PATH` (no `module load`); user namespaces on; `/dev/fuse` present |
| SLURM | v23.11; `MaxArraySize=10001`, `MaxJobCount=10000`; `DefMemPerCPU` ~1 MB → **always set `--mem`** |
| Partition | `'cpu(all)'` (keep the quotes — parens), 2-day max walltime. `'cpu(safe)'` = non-preemptable. **Avoid the default `normal(preemptable)`** for real runs — jobs there can be killed |
| Account | your lab's SLURM account, e.g. `afflecklab` (`--account=`). Find yours in the probe's `sacctmgr` section |
| Egress | login node reaches GHCR/Docker Hub (so `apptainer pull docker://…` works) |
| fakeroot | **not** available (no `/etc/subuid` entry) → don't build images on-cluster; pull or `scp` instead |
| Shared images | `/mnt/beegfs/projects/resources/Containers` — a place to publish a `.sif` for your lab |

## 0. First time on the cluster: run the probe

```bash
git clone https://github.com/RoopsyDaisy/fvs-hpc-toolkit && cd fvs-hpc-toolkit
bash cluster/hellgate_probe.sh           # → hellgate_probe/report.md
```

One shot: partitions, walltime caps, your account, Apptainer + fakeroot, storage,
login-node registry egress, plus one tiny SLURM smoke job to prove the path is
alive. Read the report to fill in `--account`/`--partition` for your site.

## 1. Get the engine image onto scratch

The clean path — pull the published image (no auth, no build):

```bash
cd /mnt/beegfs/scratch/$USER
apptainer pull fvs_ie.sif docker://ghcr.io/roopsydaisy/fvs-containers-engine:ie
```

The image carries R + rFVS as well as the `FVSie` CLI, so keyword generation can
run on the cluster too, not just the bare engine.

*Alternatives (only if egress is closed or you need a custom build):* build the
OCI image in [`fvs-containers`](https://github.com/RoopsyDaisy/fvs-containers),
convert with [`cluster/build_sif.sh`](../cluster/build_sif.sh), and `scp` the
`.sif` to scratch.

## 2. Stage inputs and build a manifest

Put your keyword files on the cluster and list them, one per line — array task *N*
runs line *N*:

```bash
ls inputs/*.key > keyfiles.txt
```

If many keyword files share **one inventory database** (the "batch built in R"
pattern, see [../scripts/r_workflow/README.md](../scripts/r_workflow/README.md)),
don't duplicate it — pass it via `FVS_INPUT` and the runner stages it into each
run dir so the keyword file's relative `DSNin` resolves. Self-contained keyword
files (inline `TREEDATA`, or a sibling `.tre`) need no `FVS_INPUT`.

## 3. Submit the array job

```bash
sbatch --array=1-$(wc -l < keyfiles.txt)%50 \
       --partition='cpu(all)' --account=afflecklab --time=00:30:00 \
       --export=SIF=/mnt/beegfs/scratch/$USER/fvs_ie.sif,VARIANT=ie,MANIFEST=$PWD/keyfiles.txt,FVS_INPUT=$PWD/inputs/FVS_Data.db \
       cluster/fvs_array.sbatch
```

- `%50` caps concurrent tasks — tune to your allocation (cap is 10000).
- Drop `FVS_INPUT=…` if each keyword file is self-contained.
- Each task runs in its own `runs/<keyfile>/` dir, so reused output names
  (`FVSOut.db`) never collide. Logs land in `logs/fvs_<jobid>_<taskid>.{out,err}`.
- FVS runs in seconds; `--time=00:30:00` is generous for a large array's queueing.

Watch it: `squeue --me`, then `sacct -j <jobid>` when done.

## 4. Collect outputs

Each task leaves a self-contained `runs/<stand>/` with its own `FVSOut.db`. Keep
the **per-run DBs** and merge in a final step — don't point all runs at one shared
output DB (concurrent SQLite writers contend). Read them back in R with
`RSQLite`; the sweep aggregation example is in
[../scripts/r_workflow/README.md](../scripts/r_workflow/README.md).

Then move the keepers off scratch:

```bash
mv runs /mnt/beegfs/projects/$USER/fvs_campaign_$(date +%Y%m%d)
```

## Test the batch with no cluster

[`cluster/run_local.sh`](../cluster/run_local.sh) runs the same per-task logic
sequentially against a native `FVS<variant>` binary (or the image) — validate a
batch on a workstation or in CI before submitting. See
[../cluster/README.md](../cluster/README.md).

## References

- UM RCI — Apptainer: https://www.umt.edu/it/rci/getting-started/apptainer/
- UM RCI — SLURM: https://www.umt.edu/it/rci/getting-started/slurm/
- The RCI onboarding docs are mirrored under [hellgate/](hellgate/).
- Engine image source: https://github.com/RoopsyDaisy/fvs-containers
