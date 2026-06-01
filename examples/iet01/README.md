# `iet01` — a self-contained FVS example

`iet01.key` + `iet01.tre` are an Inland Empire (`ie`) variant FVS example: a
flat-file keyword run (the `.key` reads its tree records from the matching
`.tre`). It needs **no inventory database and no R** — just the FVS engine — so
it's the fastest way to prove a container/cluster works end to end.

Run it by hand on a node: see [../../QUICKSTART.md](../../QUICKSTART.md).

Run it through the batch runner locally (native engine or image):

```bash
echo "$PWD/iet01.key" > keyfiles.txt
VARIANT=ie SIF=/path/to/fvs_ie.sif ../../cluster/run_local.sh keyfiles.txt runs
# (or FVS_BIN=/dir/with/FVSie instead of SIF for a native binary)
```

It runs three scenarios in one file — an unthinned control plus two thinning
prescriptions — and projects each multiple cycles, so a successful run produces a
real multi-cycle `iet01.sum` (TPA/BA/volume by year) with the thinnings visibly
removing trees. A degenerate "exited 0 but computed nothing" run is therefore easy
to spot.

**Provenance:** copied verbatim from the rFVS package's own test data
(`ForestVegetationSimulator-Interface/rFVS/tests/iet01.{key,tre}`). FVS and its
test data are works of the U.S. Forest Service (public domain).
