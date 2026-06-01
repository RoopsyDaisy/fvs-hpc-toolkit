# Quickstart — run one FVS stand on Hellgate, by hand

The goal: prove the whole path works end to end — **pull the engine container,
run FVS on a compute node, read the output** — in about five minutes, typing
every command yourself. Once this works, scaling to hundreds of stands is just
swapping in the array runner ([cluster/README.md](cluster/README.md)).

This is the exact sequence used to first validate FVS on Hellgate (job `2215378`
on node `hgcpu2-3`, June 2026).

## 0. Log in

From a campus network (eduroam), or the UM VPN:

```bash
ssh <netid>@login.rci.umt.edu        # your netID password
```

## 1. Pull the FVS engine image (once)

The image is published to GHCR and pulls without authentication. Put it on
**scratch** (Hellgate's rule: run/output on scratch, move keepers to projects):

```bash
cd /mnt/beegfs/scratch/$USER
apptainer pull fvs_ie.sif docker://ghcr.io/roopsydaisy/fvs-containers-engine:ie
```

The first pull converts the OCI layers to a `.sif` (~1 min). Any `xattr ...
ENOTSUP` warnings are harmless — BeeGFS just doesn't store those attributes.

Sanity-check it (this can't hang on a prompt the way a bare `FVSie` can):

```bash
apptainer exec fvs_ie.sif which FVSie     # → /opt/fvs/bin/FVSie
```

## 2. Stage a self-contained example

This repo ships one (`examples/iet01/`) — an Inland Empire FVS example that reads
its trees from a sibling `.tre` file, so there's nothing else to supply:

```bash
git clone https://github.com/RoopsyDaisy/fvs-hpc-toolkit
mkdir -p ~/fvs_test && cd ~/fvs_test
cp ~/fvs-hpc-toolkit/examples/iet01/iet01.key ~/fvs-hpc-toolkit/examples/iet01/iet01.tre .
```

## 3. Write a tiny SLURM script

```bash
cat > run_fvs.sbatch <<'EOF'
#!/bin/bash
#SBATCH --job-name=fvs-test
#SBATCH --partition='cpu(all)'
#SBATCH --account=afflecklab
#SBATCH --time=00:10:00
#SBATCH --mem=2G
#SBATCH --cpus-per-task=1
#SBATCH --output=fvs_test_%j.out
#SBATCH --error=fvs_test_%j.err

SIF=/mnt/beegfs/scratch/rw242025/fvs_ie.sif       # <-- your scratch path
echo ">>> node=$(hostname)  job=$SLURM_JOB_ID  cwd=$(pwd)"
apptainer exec --cleanenv "$SIF" FVSie --keywordfile=iet01.key
echo ">>> FVS exit code: $?   (0/10/20 all mean success; STOP 20 = normal)"
ls -la
EOF
```

> **Edit the `SIF=` line** to your own scratch path, and `--account` if you're not
> in `afflecklab`. `'cpu(all)'` must keep its quotes (the parens are shell
> metacharacters). Run `bash cluster/hellgate_probe.sh` once if you don't know your
> partition/account — see [docs/HELLGATE.md](docs/HELLGATE.md).

## 4. Submit and watch

```bash
sbatch run_fvs.sbatch
squeue --me                      # repeat until your job leaves the queue
```

## 5. Read the output (all in `~/fvs_test`)

```bash
cat fvs_test_*.out               # node, exit code, file listing
sacct -j <jobid> --format=JobID,State,ExitCode,Elapsed,MaxRSS,NodeList
cat iet01.sum                    # per-cycle summary: TPA, BA, volume by year
head -40 iet01.out               # the full FVS report
```

**What success looks like:** `State=COMPLETED`, `ExitCode=0:0`, and `iet01.sum`
shows a multi-cycle projection (stand growing 1990 → 2090, treatments removing
trees in the thinning scenarios). That means a real FVS run executed on a compute
node inside the GHCR container, with output on your filesystem. Done.

## What's next

- **Many stands in parallel** — turn a folder of `.key` files into a SLURM array:
  [cluster/README.md](cluster/README.md).
- **Generate keyword files from an inventory in R** — one per stand, or a
  parameter sweep: [scripts/r_workflow/README.md](scripts/r_workflow/README.md).
- **First time on a fresh cluster?** Run the probe and read the full runbook:
  [docs/HELLGATE.md](docs/HELLGATE.md).

## Why these specifics

- **`apptainer exec ... FVSie --keywordfile=name`**, not `echo name | FVSie`:
  the flag form runs non-interactively for *both* database-style and flat-file
  keyword files (it derives `.tre`/`.out`/`.sum` from the base name). Piping the
  name on stdin only works for fully database-self-contained files and otherwise
  drops FVS into interactive prompting.
- **`STOP 20` is normal completion** (and `STOP 10` = completed with warnings).
  Both are success — the runner treats exit 0/10/20 as success. Per-stand
  data/keyword problems are logged to the `FVS_Error` table in the output DB, not
  the exit code.
- **Output goes to the working directory**, so every run needs its own dir — which
  is exactly what the array runner gives each task.
