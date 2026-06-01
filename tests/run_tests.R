#!/usr/bin/env Rscript
# Test harness for fvs-hpc-toolkit.
#
# Plain base-R (no testthat dependency). Two layers:
#   - unit/        pure R, no engine: the data-path guard + the keyword writer.
#                  Runs anywhere R is installed (a workstation, CI host).
#   - integration/ runs the real FVS engine on the upstream iet01 'ie' example;
#                  self-skips where FVS<variant> isn't on PATH/FVS_BIN.
#
# Exits non-zero if any check fails.
#
#   On a host with R (unit tests; integration self-skips):
#       Rscript tests/run_tests.R
#   Inside the engine image (runs everything, FVS is on PATH):
#       apptainer exec fvs_ie.sif Rscript tests/run_tests.R
#       docker run --rm -v "$PWD:/w" -w /w <image> Rscript tests/run_tests.R

get_script_dir <- function() {
  a <- commandArgs(FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) dirname(normalizePath(f)) else getwd()
}
TESTS_DIR   <- get_script_dir()
REPO_ROOT   <- normalizePath(file.path(TESTS_DIR, ".."))
FIXTURE_DIR <- file.path(TESTS_DIR, "fixtures")

# Shared assertion harness.
.results <- list()
check <- function(name, expr) {
  ok <- tryCatch(isTRUE(expr), error = function(e) {
    message(sprintf("  [%s] error: %s", name, conditionMessage(e))); FALSE
  })
  .results[[name]] <<- ok
  cat(sprintf("CHECK %-30s %s\n", name, if (ok) "PASS" else "FAIL"))
}
skip <- function(name, why)
  cat(sprintf("CHECK %-30s SKIP (%s)\n", name, why))

# Units under test (paths mirror the repo + the in-image bind layout).
source(file.path(REPO_ROOT, "scripts", "r_workflow", "data_paths.R"))
source(file.path(REPO_ROOT, "scripts", "reference_scripts",
                 "fvs_keyword_file_functions.R"))

# Run every test file (each calls check()/skip() at source time).
test_files <- c(
  list.files(file.path(TESTS_DIR, "unit"),        pattern = "\\.R$", full.names = TRUE),
  list.files(file.path(TESTS_DIR, "integration"), pattern = "\\.R$", full.names = TRUE))
for (f in test_files) {
  cat(sprintf("\n# %s\n", sub(paste0(REPO_ROOT, "/?"), "", f)))
  source(f)
}

failed <- names(Filter(isFALSE, .results))
cat(sprintf("\n%d checks, %d failed\n", length(.results), length(failed)))
if (length(failed)) {
  cat(sprintf("TESTS FAILED: %s\n", paste(failed, collapse = ", ")))
  quit(status = 1)
}
cat("ALL TESTS PASSED\n")
