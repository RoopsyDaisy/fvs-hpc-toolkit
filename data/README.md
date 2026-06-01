# Inventory inputs (you supply these)

The R **database-style** workflow (`scripts/r_workflow/build_input_db.R`) reads
forest-inventory CSVs from this `data/` directory and writes them into an
FVS-native SQLite database (`FVS_StandInit` + `FVS_TreeInit` tables). Those CSVs
are **not shipped** — they're your stand data — and are gitignored.

Expected files (the Lubrecht example set; rename in
[`scripts/r_workflow/data_paths.R`](../scripts/r_workflow/data_paths.R) to use
your own):

```
data/FVS_Lubrecht_2023_FVS_StandInit.csv      # one row per stand
data/FVS_Lubrecht_2023_FVS_FVS_TreeInit.csv   # one row per tree record
```

Both are read as UTF-8-BOM (as Excel / the FVS database tools export them). The
column names must match FVS's `FVS_StandInit` / `FVS_TreeInit` schema — the same
columns the FVS GUI and the Forest Service database tools produce.

You don't need any of this for the **self-contained example** in
[`../examples/iet01/`](../examples/iet01/) or for keyword files that carry their
own tree data inline — only for the R-generated database batch. See
[`../scripts/r_workflow/README.md`](../scripts/r_workflow/README.md).
