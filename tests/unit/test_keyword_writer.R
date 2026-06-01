# Unit: scripts/reference_scripts/fvs_keyword_file_functions.R -- write.FVSfiles(),
# the flat-file keyword/tree writer the interactive track (project_stand.R) uses.
# Builds a minimal 1-stand / 2-tree input with the documented FVS columns (see
# data/README.md) and asserts a .key with the expected control records and a
# .tre with one line per tree. No engine needed. Uses check() from run_tests.R.
# Immediately-invoked function (not local()) so setwd()'s on.exit() fires.
(function() {
  stand <- data.frame(
    STAND_ID = "T1", FOREST = 1, PV_CODE = 260, AGE = 60,
    ASPECT = 180, SLOPE = 30, ELEVFT = 4000,
    SITE_SPECIES = "PP", SITE_INDEX = 70, NUM_PLOTS = 1, INV_YEAR = 1990,
    DG_TRANS = 1, DG_MEASURE = 10, HTG_TRANS = 1, HTG_MEASURE = 10,
    MORT_MEASURE = 10, stringsAsFactors = FALSE)

  tree <- data.frame(
    PLOT_ID     = c(1L, 1L),
    fvs.TREE_ID = c(1L, 2L),     # project_stand.R assigns consecutive ids
    TREE_COUNT  = c(1, 1),
    HISTORY     = c(1, 1),
    SPECIES     = c(122, 202),   # FIA codes (ponderosa pine, Douglas-fir)
    DIAMETER    = c(8.0, 12.0),
    DG          = c(1.0, 1.5),
    HT          = c(40, 60),
    HTTOPK      = c(NA, NA),     # exercises the missing-value -> blanks path
    HTG         = c(2, 3),
    CRRATIO     = c(40, 55),
    DAMAGE1 = c(0, 0), SEVERITY1 = c(0, 0),
    DAMAGE2 = c(0, 0), SEVERITY2 = c(0, 0),
    DAMAGE3 = c(0, 0), SEVERITY3 = c(0, 0),
    TOPOCODE    = c(1, 1),
    AGE         = c(60, 60),
    stringsAsFactors = FALSE)

  wd <- tempfile("kw_"); dir.create(wd)
  dir.create(file.path(wd, "temp"))              # write.FVSfiles writes into ./temp
  old <- setwd(wd); on.exit(setwd(old), add = TRUE)

  fn   <- write.FVSfiles(trees = tree, stand = stand, years_out = 50,
                         calibrate = TRUE, triple = FALSE, add_regen = FALSE)
  keyf <- paste0(fn, ".key")
  tref <- paste0(fn, ".tre")

  check("keyword/files-written", file.exists(keyf) && file.exists(tref))

  check("keyword/key-records", {
    k <- readLines(keyf, warn = FALSE)
    all(vapply(c("STDIDENT", "STDINFO", "NUMCYCLE", "PROCESS", "STOP"),
               function(kw) any(grepl(paste0("^", kw), k)), logical(1)))
  })

  # one flat tree record per input tree (guards the TOPOCODE write path: a
  # zero-length column there silently emits an empty .tre -- see commit msg)
  check("keyword/tre-one-line-per-tree", {
    length(readLines(tref, warn = FALSE)) == nrow(tree)
  })
})()
