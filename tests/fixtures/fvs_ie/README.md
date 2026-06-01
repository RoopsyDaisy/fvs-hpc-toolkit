# Test fixture — Inland Empire (`ie`) FVS example

`iet01.key` + `iet01.tre` are an FVS example for the **Inland Empire (`ie`)**
variant — a flat-file keyword run (the `.key` reads its tree records from the
matching `.tre`), which is exactly the `FVSie --keywordfile=` path the cluster
batch runner uses.

**Provenance:** copied verbatim from the rFVS package's own test data
(`vendor/fvs-interface/rFVS/tests/iet01.{key,tre}`,
[USDAForestService/ForestVegetationSimulator-Interface](https://github.com/USDAForestService/ForestVegetationSimulator-Interface)).
FVS and its test data are works of the U.S. Forest Service (public domain);
vendored here so the test suite is self-contained (the submodule isn't always
checked out, and isn't present in the deliverable images).

Used by `tests/integration/test_fvs_iet01.R`, which runs the engine on it and
asserts a clean run **and a real multi-cycle projection** — it parses the `.sum`
output and requires several distinct projection cycles carrying positive stand
metrics (TPA/BA), so a degenerate "exited 0 but computed nothing" run fails.
(iet01 sends its summary to the `.sum` text file via `ECHOSUM`; it does not
request DB output, so `FVSOut.db` holds only admin tables.)

It is **not** a `data/` inventory fixture (the database track's
`FVS_StandInit`/`FVS_TreeInit` CSVs are still unshipped — see `data/README.md`);
it exercises the engine + the keyword-file invocation, not `build_input_db.R`.
