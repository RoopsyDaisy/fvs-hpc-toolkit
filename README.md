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

- **[QUICKSTART.md](QUICKSTART.md)** — run one FVS stand on a compute node, by
  hand, in ~5 minutes (pull the image → submit → read the output). Start here.
- **[docs/HELLGATE.md](docs/HELLGATE.md)** — the full Hellgate runbook: first-time
  cluster probe, storage, partitions/account, and the parallel array batch.
- **[cluster/README.md](cluster/README.md)** — the batch runner (`fvs_array.sbatch`)
  in detail.
- **[scripts/r_workflow/README.md](scripts/r_workflow/README.md)** — generating
  keyword files in R (one per stand, or a parameter sweep).

## Layout

```
cluster/              SLURM + Apptainer batch runner
  fvs_array.sbatch      one array task per keyword file
  fvs_run_one.sh        per-task unit (isolated run dir → FVS --keywordfile=)
  run_local.sh          run the same batch with no scheduler/container (testing)
  build_sif.sh          convert an OCI image to a .sif (if not pulling from GHCR)
  hellgate_probe.sh     first-contact cluster probe (partitions, account, egress…)
scripts/
  r_workflow/           R keyword-file generators (database-style batch + rFVS)
  reference_scripts/    FVS's own R helpers, reused not reinvented
examples/iet01/        a self-contained FVS example that runs out of the box
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
