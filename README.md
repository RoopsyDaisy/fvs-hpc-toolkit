# fvs-hpc-toolkit

Scripts and docs for running the **Forest Vegetation Simulator (FVS)** at scale on
an HPC cluster — built and tested for the University of Montana **Hellgate**
research cluster (Apptainer + SLURM), but portable to any Apptainer/SLURM site.

This repo is the **user-facing toolkit**: the batch orchestration, the R
keyword-file generators, and the runbooks. It does **not** build FVS — it runs the
prebuilt **engine container** published from
[`fvs-containers`](https://github.com/RoopsyDaisy/fvs-containers):

```
ghcr.io/roopsydaisy/fvs-containers-engine:ie     # FVS CLI + R + rFVS
```

So there are two repos, coupled only by that published image:

| Repo | Role | You touch it when… |
| --- | --- | --- |
| **fvs-containers** | builds + publishes the FVS engine image to GHCR | the FVS version or the image itself changes |
| **fvs-hpc-toolkit** (this) | runs batches *against* that image | you run simulations, or adapt the workflow |

Everything here is meant to be **cloned/forked and modified** for your own runs —
change the treatment in `generate_sweep.R`, the concurrency cap, the manifest
logic. The container stays fixed; the workflow is yours.

## Get started

Start with the **[example workflows](examples/)** — three runnable, copy-and-adapt
patterns, each a minimal version of a real HPC workflow:

1. **[01-single-run](examples/01-single-run/)** — one FVS run as a SLURM job on a
   compute node. *Prove the path works; start here.*
2. **[02-parallel-batch](examples/02-parallel-batch/)** — generate N keyword files
   → SLURM array → aggregate (incl. **Monte Carlo** sweeps).
3. **[03-rfvs-insim](examples/03-rfvs-insim/)** — R drives FVS with custom logic
   *between cycles*, one (stand × scenario) per array task.

Then the references:
- **[docs/HELLGATE.md](docs/HELLGATE.md)** — the full Hellgate runbook: first-time
  cluster probe, storage, partitions/account, scratch→projects.
- **[cluster/README.md](cluster/README.md)** — the array runners in detail.
- **[scripts/r_workflow/README.md](scripts/r_workflow/README.md)** — the R
  generators + the rFVS driver, under the hood.

First-time setup (`TK`, `SIF`, a scratch work dir) is in
[docs/HELLGATE.md](docs/HELLGATE.md); every example assumes it.

## Layout

```
examples/             three runnable workflow patterns (the front door)
  01-single-run/        one FVS run as a SLURM job
  02-parallel-batch/    N keyfiles → array → aggregate (+ Monte Carlo sweep)
  03-rfvs-insim/        R-in-the-loop array; per-job R config in configs/
  inventory/            bundled 3-stand sample so the examples run from a clone
cluster/              SLURM + Apptainer runners
  fvs_array.sbatch      CLI array — one task per keyword file
  fvs_rfvs_array.sbatch rFVS array — one task per (stand × scenario) job
  fvs_run_one.sh        per-task CLI unit (isolated run dir → FVS --keywordfile=)
  run_local.sh          run a batch with no scheduler/container (workstation/CI)
  build_sif.sh          convert an OCI image to a .sif (if not pulling from GHCR)
  hellgate_probe.sh     first-contact cluster probe (partitions, account, egress…)
scripts/
  r_workflow/           R generators (keyfiles, sweep, rFVS jobs) + the rFVS driver
  reference_scripts/    FVS's own R helpers, reused not reinvented
tests/                 pure-R unit tests + an integration test against the image
docs/                  Hellgate runbook + the RCI onboarding docs
```

## The one contract

Anything here assumes a container (a `.sif` or OCI image) that puts
`FVS<variant>` (e.g. `FVSie`), `R`, and `rFVS` on `PATH`. The
`fvs-containers-engine` image satisfies it; so would any equivalent FVS image.

## License

MIT — see [LICENSE](LICENSE). FVS itself is a work of the U.S. Forest Service
(public domain).
