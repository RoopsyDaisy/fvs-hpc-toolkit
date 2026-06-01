# Bundled inventory sample (3 stands)

A tiny **3-stand subset** (`CARB_2`, `CARB_3`, `CARB_4`; 32 tree records) of the
Lubrecht inventory, in FVS's `FVS_StandInit` / `FVS_TreeInit` CSV schema. It ships
so the **Track A batch** ([`../../scripts/r_workflow/README.md`](../../scripts/r_workflow/README.md))
runs straight from a clone — no data to supply, nothing to `scp`:

```bash
export FVS_DATA_DIR=examples/inventory
apptainer exec --env FVS_DATA_DIR="$FVS_DATA_DIR" "$SIF" \
  Rscript scripts/r_workflow/build_input_db.R outputs/r_batch/FVS_Data.db all
# …then generate_keyfiles.R + run the batch (see the Track A README)
```

`FVS_DATA_DIR` (read by [`../../scripts/r_workflow/data_paths.R`](../../scripts/r_workflow/data_paths.R))
points the workflows at this directory instead of the default `data/`. For real
work, put your full inventory CSVs in `data/` and omit `FVS_DATA_DIR` — see
[`../../data/README.md`](../../data/README.md).

Verified end to end: 3 stands → `FVS_Data.db` → 3 keyword files → batch → a real
7-cycle projection (2023→2083) per stand.
