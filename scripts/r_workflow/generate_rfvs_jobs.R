#!/usr/bin/env Rscript
# Expand a (stand x scenario) grid into a jobs.csv for the rFVS array
# (example 03-rfvs-insim). Each scenario is a config .R file; the job manifest
# is one row per (stand, config) cell -> array task N runs row N via
# rfvs_run_one.R. This is the rFVS counterpart to generate_sweep.R.
#
# Usage:
#   Rscript generate_rfvs_jobs.R <OUTDIR> <STANDS> <YEARS> [CONFIGS_DIR]
#     OUTDIR       where to write jobs.csv
#     STANDS       comma list (CARB_2,CARB_3) or "all"
#     YEARS        projection length (e.g. 80)
#     CONFIGS_DIR  dir of scenario .R files
#                  (default: examples/03-rfvs-insim/configs)

get_script_dir <- function() {
  a <- commandArgs(FALSE); f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) dirname(normalizePath(f)) else getwd()
}
repo_root <- normalizePath(file.path(get_script_dir(), "..", ".."))
source(file.path(get_script_dir(), "data_paths.R"))

args        <- commandArgs(trailingOnly = TRUE)
outdir      <- if (length(args) >= 1 && nzchar(args[1])) args[1] else file.path(repo_root, "outputs", "r_rfvs")
stands_arg  <- if (length(args) >= 2 && nzchar(args[2])) args[2] else "all"
years       <- if (length(args) >= 3 && nzchar(args[3])) as.integer(args[3]) else 80L
configs_dir <- if (length(args) >= 4 && nzchar(args[4])) args[4] else
               file.path(repo_root, "examples", "03-rfvs-insim", "configs")

stopifnot(dir.exists(configs_dir))
configs <- normalizePath(list.files(configs_dir, pattern = "\\.R$", full.names = TRUE))
if (!length(configs)) stop("no .R config files in ", configs_dir)

stands <- if (identical(stands_arg, "all")) {
  unique(read_input_csv(repo_root, INPUT_STAND_CSV)$STAND_ID)
} else {
  trimws(strsplit(stands_arg, ",")[[1]])
}

grid <- expand.grid(stand_id = stands, config = configs,
                    KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
grid$run_id <- paste0(grid$stand_id, "__", sub("\\.R$", "", basename(grid$config)))
grid$years  <- years
# A deterministic per-job seed (base from $RFVS_SEED) so stochastic hooks are
# reproducible across reruns: same jobs.csv -> same draws. The driver set.seed()s it.
seed_base   <- suppressWarnings(as.integer(Sys.getenv("RFVS_SEED", "1")))
if (is.na(seed_base)) seed_base <- 1L
grid$seed   <- seed_base + seq_len(nrow(grid))
grid <- grid[, c("run_id", "stand_id", "years", "config", "seed")]

dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
jobs_csv <- file.path(outdir, "jobs.csv")
write.csv(grid, jobs_csv, row.names = FALSE)

cat(sprintf("\nWrote %s  (%d jobs = %d stands x %d scenarios)\n",
            jobs_csv, nrow(grid), length(stands), length(configs)))
cat("Scenarios: ", paste(sub("\\.R$", "", basename(configs)), collapse = ", "), "\n", sep = "")
cat("\nRun one job locally (engine on PATH inside the image, or set FVS_BIN):\n")
cat(sprintf("  Rscript %s/scripts/r_workflow/rfvs_run_one.R %s 1 r_rfvs_runs\n", repo_root, jobs_csv))
cat("\nOr submit the whole grid as a SLURM array (see cluster/fvs_rfvs_array.sbatch):\n")
cat(sprintf("  sbatch --array=1-%d%%50 --export=SIF=...,JOBS=%s,DRIVER=%s/scripts/r_workflow/rfvs_run_one.R,FVS_DATA_DIR=$FVS_DATA_DIR cluster/fvs_rfvs_array.sbatch\n\n",
            nrow(grid), jobs_csv, repo_root))
