#!/usr/bin/env Rscript
#
# R batch track, step 2 (sweep variant): generate a *parameter sweep* of keyword
# files.
#
# Where generate_keyfiles.R emits one keyword file per stand, this emits one
# keyword file per (stand x treatment-combination) cell of a parameter grid --
# the structured-sweep / Monte Carlo pattern. Each combination injects a thinning
# treatment into the stand's keyword file via rFVS::fvsMakeKeyFile(moreKeywords=),
# so the whole sweep runs through the existing file-based batch (cluster/) and
# every run writes to its own FVSOut.db. A sweep_manifest.csv maps each run back
# to the parameter values that produced it, so results aggregate cleanly.
#
# This replaces the pruned Python Monte-Carlo tooling: R builds the grid
# (expand.grid, with optional random subsampling), FVS does the simulation, and
# RSQLite aggregates the per-run FVSOut.db files (see the README for the join).
#
# Run build_input_db.R first to create the FVS_Data.db the keyfiles read from.
#
# Usage:
#   Rscript scripts/r_workflow/generate_sweep.R [OUTDIR] [STANDS] [YEARS] [INPUT_DB]
#     OUTDIR    output dir for .key files + manifests        (default outputs/r_sweep)
#     STANDS    comma-separated STAND_IDs, or "all"          (default CARB_2,CARB_3,CARB_4)
#     YEARS     projection length in years                   (default 55)
#     INPUT_DB  FVS input database the keyfiles read from    (default <OUTDIR>/FVS_Data.db)
#
# Sweep grid (env vars, so the positional args stay identical to generate_keyfiles.R):
#   SWEEP_RESID_BA   comma list of residual basal areas (ft2/acre) to thin to;
#                    the literal "none" = an un-thinned baseline cell
#                                                            (default none,60,100,140)
#   SWEEP_THIN_YEAR  calendar year the thinning is scheduled (default 2033)
#   SWEEP_SAMPLE     if set to an integer N, randomly sample N cells from the full
#                    grid instead of running it exhaustively (Monte Carlo)
#                                                            (default "" = full grid)
#   SWEEP_SEED       RNG seed for SWEEP_SAMPLE               (default 1)
#
# The treatment is a thin-from-below to a residual basal area (FVS keyword
# ThinBBA). To sweep a different treatment or an Event-Monitor threshold, change
# treat_record() below -- the grid/manifest/batch plumbing is treatment-agnostic.

suppressMessages(library(rFVS))

get_script_dir <- function() {
  a <- commandArgs(FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) dirname(normalizePath(f)) else getwd()
}
repo_root <- normalizePath(file.path(get_script_dir(), "..", ".."))
source(file.path(get_script_dir(), "data_paths.R"))

# stand list comes from the StandInit CSV (so "all" works without opening the DB)
all_ids <- read_input_csv(repo_root, INPUT_STAND_CSV)$STAND_ID

args      <- commandArgs(trailingOnly = TRUE)
outdir    <- if (length(args) >= 1 && nzchar(args[1])) args[1] else
  file.path(repo_root, "outputs", "r_sweep")
stand_arg <- if (length(args) >= 2 && nzchar(args[2])) args[2] else "CARB_2,CARB_3,CARB_4"
years     <- if (length(args) >= 3 && nzchar(args[3])) as.integer(args[3]) else 55L
input_db  <- if (length(args) >= 4 && nzchar(args[4])) args[4] else
  file.path(outdir, "FVS_Data.db")

stand_ids <- if (identical(stand_arg, "all")) all_ids else
  trimws(strsplit(stand_arg, ",")[[1]])

cycle_length <- 10L
ncycles      <- as.integer(ceiling(years / cycle_length))

# --- sweep grid -------------------------------------------------------------
resid_ba  <- trimws(strsplit(Sys.getenv("SWEEP_RESID_BA", "none,60,100,140"), ",")[[1]])
thin_year <- as.integer(Sys.getenv("SWEEP_THIN_YEAR", "2033"))
n_sample  <- Sys.getenv("SWEEP_SAMPLE", "")
seed      <- as.integer(Sys.getenv("SWEEP_SEED", "1"))

grid <- expand.grid(stand_id = stand_ids, resid_ba = resid_ba,
                    KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)

if (nzchar(n_sample)) {
  n <- min(as.integer(n_sample), nrow(grid))
  set.seed(seed)
  grid <- grid[sample(nrow(grid), n), , drop = FALSE]
}

# FVS keyword record for one treatment cell: a thin-from-below to a residual
# basal area, scheduled at thin_year. "none" => no record => un-thinned baseline.
# FVS keyword fields are 10 columns wide; the keyword occupies columns 1-10.
treat_record <- function(resid_ba) {
  if (identical(resid_ba, "none")) return(character(0))
  sprintf("%-10s%10d%10s", "ThinBBA", thin_year, resid_ba)
}

# --- generate ---------------------------------------------------------------
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
outdir <- normalizePath(outdir)
if (!file.exists(input_db))
  stop("Input database not found: ", input_db,
       "\n  Run build_input_db.R first.")

manifest <- character(0)
runs     <- data.frame(run_id = character(0), stand_id = character(0),
                       resid_ba = character(0), thin_year = integer(0),
                       stringsAsFactors = FALSE)

for (i in seq_len(nrow(grid))) {
  sid <- grid$stand_id[i]
  rba <- grid$resid_ba[i]
  # unique run id (= keyfile base = batch run dir) so each cell gets its own
  # output dir + FVSOut.db even when many cells share a STAND_ID.
  tag    <- if (identical(rba, "none")) "baseline" else paste0("ba", rba)
  run_id <- paste(sid, tag, sep = "__")
  key    <- file.path(outdir, paste0(run_id, ".key"))

  more <- treat_record(rba)
  fvsMakeKeyFile(keyFileName = key, runTitle = run_id, standIDs = sid,
                 inDataBase = basename(input_db), outDataBase = "FVSOut.db",
                 ncycles = ncycles,
                 moreKeywords = if (length(more)) more else NULL)

  manifest <- c(manifest, normalizePath(key))
  runs <- rbind(runs, data.frame(run_id = run_id, stand_id = sid,
                                 resid_ba = rba, thin_year = thin_year,
                                 stringsAsFactors = FALSE))
}

writeLines(manifest, file.path(outdir, "keyfiles.txt"))
write.csv(runs, file.path(outdir, "sweep_manifest.csv"), row.names = FALSE)

cat(sprintf("\nGenerated %d sweep keyword file(s) in %s\n", length(manifest), outdir))
cat(sprintf("  stands:     %d   x treatment cells: %d\n",
            length(unique(runs$stand_id)), length(unique(runs$resid_ba))))
cat(sprintf("Manifest:     %s\n", file.path(outdir, "keyfiles.txt")))
cat(sprintf("Sweep map:    %s  (run_id -> parameters)\n", file.path(outdir, "sweep_manifest.csv")))
cat(sprintf("Input DB:     %s\n\n", normalizePath(input_db)))
cat("Run the batch locally with:\n")
cat(sprintf("  FVS_BIN=.devcontainer/fvs-bin VARIANT=ie FVS_INPUT=%s \\\n    cluster/run_local.sh %s outputs/r_sweep_runs\n\n",
            normalizePath(input_db), file.path(outdir, "keyfiles.txt")))
cat("Then aggregate run_id -> FVSOut.db results against sweep_manifest.csv (see README).\n\n")
