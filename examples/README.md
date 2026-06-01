# Example workflows

Three runnable, copy-and-adapt examples — each a minimal version of a real HPC
workflow pattern for FVS. Start at the top; each builds on the one before.

| | Example | Pattern | Reach for it when… |
| --- | --- | --- | --- |
| **01** | [single-run](01-single-run/) | one FVS run as a SLURM job on a compute node | you want to prove the path works, or run a single stand |
| **02** | [parallel-batch](02-parallel-batch/) | generate N keyword files → SLURM **array** → aggregate (incl. **Monte Carlo** sweeps) | running the same simulation over many stands / parameters; logic fits in keyword records |
| **03** | [rfvs-insim](03-rfvs-insim/) | R drives FVS via `rFVS`, custom logic **between cycles**, one (stand × scenario) per array task | you must inspect the live stand mid-run and decide in R (custom harvest rules, in-sim Monte Carlo) |

## The shape they all share

Every one is **generate → run → aggregate**, and only the middle phase is compute:

- **Generate** (light): build inputs — keyword files, a job manifest. Quick; do it
  with `apptainer exec` or in an interactive shell.
- **Run** (the compute): a **SLURM array**, one task per stand/scenario, fanned
  across compute nodes, non-interactive. *Never the login node.*
- **Aggregate** (light): collect the per-run outputs.

The interactive `apptainer shell` is for **developing** a workflow — prototype one
stand, debug a keyfile or a config — not for running campaigns. That's what the
arrays are for. Get this shape right at 3 stands and it's identical at 30,000.

All three run from a clone with **no data to supply** (they use the bundled
[`../examples/inventory/`](inventory/) 3-stand sample, or a self-contained keyword
file). Swap in your own inventory (see [`../data/README.md`](../data/README.md)) for
real work.

## Prerequisites

A pulled engine image + the toolkit clone. See the [toolkit README](../README.md)
for the one-time setup (`TK`, `SIF`, a scratch work dir) and
[`docs/HELLGATE.md`](../docs/HELLGATE.md) for the cluster runbook (first-contact
probe, partitions, account, scratch→projects).

## The machinery behind them

The examples are thin; the reusable parts live in:
- [`../cluster/`](../cluster/) — the SLURM array runners + `run_local.sh`.
- [`../scripts/r_workflow/`](../scripts/r_workflow/) — the R generators + the rFVS
  driver ([reference](../scripts/r_workflow/README.md)).
