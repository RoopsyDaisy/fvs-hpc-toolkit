# Integration: the rFVS-in-the-loop driver (rfvs_run_one.R) + the bundled configs.
# Asserts the per-job R config genuinely changes the projection — runs a baseline
# and a harvest_largest job on one stand and checks (a) both produce a multi-cycle
# summary and (b) removing the largest stems leaves LESS basal area than the
# untreated baseline. Locks the copy-and-adapt template against an rFVS/image bump.
#
# Self-skips where FVS<variant> isn't available. Uses check()/skip()/REPO_ROOT
# from run_tests.R.

local({
  variant <- Sys.getenv("VARIANT", "ie")
  prog    <- paste0("FVS", variant)
  bd      <- Sys.getenv("FVS_BIN", "")
  have    <- (nzchar(bd) && file.exists(file.path(bd, prog))) || nzchar(Sys.which(prog))
  if (!have) return(skip("rfvs/insim", paste(prog, "not on PATH/FVS_BIN")))

  driver <- file.path(REPO_ROOT, "scripts", "r_workflow", "rfvs_run_one.R")
  cfgdir <- file.path(REPO_ROOT, "examples", "03-rfvs-insim", "configs")
  if (!file.exists(driver) || !dir.exists(cfgdir))
    return(skip("rfvs/insim", "driver or configs missing"))

  # Use the bundled sample (so it runs with no data/ checkout) and pass our library
  # paths to the subprocess (renv locally; default libs in the image) so it finds rFVS.
  Sys.setenv(FVS_DATA_DIR = file.path(REPO_ROOT, "examples", "inventory"))
  Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))

  wd <- tempfile("rfvs_test"); dir.create(wd, recursive = TRUE)
  jobs <- data.frame(
    run_id   = c("t_baseline", "t_harvest"),
    stand_id = c("CARB_2", "CARB_2"),
    years    = c(60L, 60L),
    config   = file.path(cfgdir, c("baseline.R", "harvest_largest.R")),
    seed     = c(1L, 2L), stringsAsFactors = FALSE)
  jobs_csv <- file.path(wd, "jobs.csv"); write.csv(jobs, jobs_csv, row.names = FALSE)

  old <- setwd(wd); on.exit(setwd(old), add = TRUE)   # outputs land under wd/runs
  for (r in c(1, 2))
    system2("Rscript", c(shQuote(driver), shQuote(jobs_csv), r, "runs"),
            stdout = FALSE, stderr = FALSE)

  read_summ <- function(id) {
    f <- file.path("runs", id, "stand_summary.csv")
    if (file.exists(f)) read.csv(f, check.names = FALSE) else NULL
  }
  base <- read_summ("t_baseline"); harv <- read_summ("t_harvest")
  fin  <- function(s) if (is.null(s)) NA else s$ATBA[s$Year == max(s$Year)][1]

  check("rfvs/baseline-cycles",  !is.null(base) && nrow(base) >= 3)
  check("rfvs/harvest-cycles",   !is.null(harv) && nrow(harv) >= 3)
  check("rfvs/config-changes-projection", isTRUE(fin(harv) < fin(base)))
})
