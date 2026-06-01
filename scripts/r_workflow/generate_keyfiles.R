#!/usr/bin/env Rscript
#
# R batch track, step 2: generate keyword files.
#
# Templates one database-style FVS keyword file per stand using rFVS's own
# generator, rFVS::fvsMakeKeyFile() (vendor/fvs-interface/rFVS/R/fvsMakeyFile.R),
# and emits a manifest the file-based batch runner consumes (cluster/run_local.sh
# locally, cluster/fvs_array.sbatch on Hellgate). Each keyword file reads its
# stand+tree records from the shared FVS_Data.db (DSNin/StandSQL/TreeSQL) and
# writes results to its own FVSOut.db (DSNOut) -- the standard "many keyword
# files share one inventory database" batch pattern. No FVS run happens here.
#
# Run build_input_db.R first to create the FVS_Data.db this points at.
#
# Usage:
#   Rscript scripts/r_workflow/generate_keyfiles.R [OUTDIR] [STANDS] [YEARS] [INPUT_DB]
#     OUTDIR    output dir for .key files + keyfiles.txt   (default outputs/r_batch)
#     STANDS    comma-separated STAND_IDs, or "all"        (default CARB_2,CARB_3,CARB_4)
#     YEARS     projection length in years                 (default 55)
#     INPUT_DB  FVS input database the keyfiles read from  (default <OUTDIR>/FVS_Data.db)
#
# To vary a treatment/Event-Monitor threshold across runs (the Monte Carlo
# pattern), add the relevant keyword records via fvsMakeKeyFile(moreKeywords=...).

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
  file.path(repo_root, "outputs", "r_batch")
stand_arg <- if (length(args) >= 2 && nzchar(args[2])) args[2] else "CARB_2,CARB_3,CARB_4"
years     <- if (length(args) >= 3 && nzchar(args[3])) as.integer(args[3]) else 55L
input_db  <- if (length(args) >= 4 && nzchar(args[4])) args[4] else
  file.path(outdir, "FVS_Data.db")

stand_ids <- if (identical(stand_arg, "all")) all_ids else
  trimws(strsplit(stand_arg, ",")[[1]])

cycle_length <- 10L
ncycles      <- as.integer(ceiling(years / cycle_length))

dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
outdir <- normalizePath(outdir)
if (!file.exists(input_db))
  stop("Input database not found: ", input_db,
       "\n  Run build_input_db.R first.")

# fvsMakeKeyFile writes the keyword file's DSNin/DSNOut by the *names* it's given;
# the runner stages the shared FVS_Data.db into each run dir and FVS writes
# FVSOut.db there, so we use bare names (resolved relative to each run dir).
manifest <- character(0)
for (id in stand_ids) {
  key <- file.path(outdir, paste0(id, ".key"))
  fvsMakeKeyFile(keyFileName = key, runTitle = id, standIDs = id,
                 inDataBase = basename(input_db), outDataBase = "FVSOut.db",
                 ncycles = ncycles)
  manifest <- c(manifest, normalizePath(key))
}

writeLines(manifest, file.path(outdir, "keyfiles.txt"))

cat(sprintf("\nGenerated %d keyword file(s) in %s\n", length(manifest), outdir))
cat(sprintf("Manifest:    %s\n", file.path(outdir, "keyfiles.txt")))
cat(sprintf("Input DB:    %s\n\n", normalizePath(input_db)))
cat("Run the batch locally with:\n")
cat(sprintf("  FVS_BIN=.devcontainer/fvs-bin VARIANT=ie FVS_INPUT=%s \\\n    cluster/run_local.sh %s outputs/r_runs\n\n",
            normalizePath(input_db), file.path(outdir, "keyfiles.txt")))
