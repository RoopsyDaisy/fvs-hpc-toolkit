# 01 · single run — one FVS simulation on a compute node

**Pattern:** the smallest correct thing — submit **one** FVS run as a SLURM job
that `apptainer exec`s the engine on a **compute node** (never the login node).
Everything else here scales this up.

`iet01.key` + `iet01.tre` are a self-contained Inland Empire example (the keyword
file carries its own tree data), so this needs **no inventory, no R** — just the
engine image.

## Run it (on Hellgate)

```bash
# pull the engine image once (skip if you already have it on scratch)
cd /mnt/beegfs/scratch/$USER
apptainer pull fvs_ie.sif docker://ghcr.io/roopsydaisy/fvs-containers-engine:ie

# work dir on scratch with this example's files
mkdir -p run-single && cd run-single
cp ~/fvs-hpc-toolkit/examples/01-single-run/{iet01.key,iet01.tre,run.sbatch} .

# submit — outputs land here, in your scratch work dir
SIF=/mnt/beegfs/scratch/$USER/fvs_ie.sif sbatch run.sbatch
squeue --me
```

## What success looks like

```bash
cat fvs_*.out                  # node name, FVS exit code, file listing
sacct -j <jobid> --format=JobID,State,ExitCode,Elapsed,NodeList   # COMPLETED 0:0
cat iet01.sum                  # per-cycle summary: TPA, BA, volume by year
```

`State=COMPLETED`, `FVS exit code: 20` (normal), and `iet01.sum` showing a
multi-cycle projection (the file runs an unthinned control + two thinning
scenarios, so you'll see removals in the thinned ones). That's a real FVS run, on
a compute node, in the GHCR container — the foundation the other two examples build
on. *(This is the exact path first validated on Hellgate: job 2215378 on hgcpu2-3.)*

## Notes

- **`--keywordfile=`, not stdin** — works for both database-style and flat-file
  keyword files (FVS derives `.tre`/`.out`/`.sum` from the base name, non-interactively).
- **`STOP 20` = normal completion** (`STOP 10` = with warnings); both are success.
- **Output goes to the working directory**, so every run needs its own dir — which
  is exactly what the array in [02-parallel-batch](../02-parallel-batch/) gives each task.
