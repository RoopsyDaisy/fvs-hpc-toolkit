# Unit: scripts/r_workflow/data_paths.R -- the missing-input guard added for H1.
# No engine needed. Uses check()/INPUT_*_CSV from run_tests.R. Wrapped in an
# immediately-invoked function (not local()) so any return()/on.exit() works.
(function() {
  # the constants name the documented fixture files (data/README.md contract)
  check("data_paths/constants",
        identical(INPUT_STAND_CSV, "FVS_Lubrecht_2023_FVS_StandInit.csv") &&
        identical(INPUT_TREE_CSV,  "FVS_Lubrecht_2023_FVS_FVS_TreeInit.csv"))

  tmp <- tempfile("dp_")
  dir.create(file.path(tmp, "data"), recursive = TRUE, showWarnings = FALSE)

  # a missing input must stop() with a pointer to data/README.md,
  # not fall through to a raw read.csv "cannot open file" error
  check("data_paths/missing-errs", {
    e <- tryCatch(require_input_csv(tmp, "nope.csv"), error = function(e) e)
    inherits(e, "error") &&
      grepl("data/README.md", conditionMessage(e), fixed = TRUE)
  })

  # a present input is resolved and read (UTF-8-BOM read path)
  check("data_paths/reads-present", {
    csv <- file.path(tmp, "data", "x.csv")
    write.csv(data.frame(STAND_ID = c("A", "B"), V = 1:2), csv, row.names = FALSE)
    d <- read_input_csv(tmp, "x.csv")
    is.data.frame(d) && nrow(d) == 2L && all(c("STAND_ID", "V") %in% names(d))
  })
})()
