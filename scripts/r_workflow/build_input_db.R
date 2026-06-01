#!/usr/bin/env Rscript
#
# R batch track, step 1: build the FVS *input* database.
#
# Writes the Lubrecht inventory CSVs into an FVS-native SQLite database with the
# canonical FVS_StandInit and FVS_TreeInit tables. FVS reads from this via the
# Database Extension (DSNin / StandSQL / TreeSQL). The CSV column names already
# match the FVS schema, so this is a direct dbWriteTable -- no remapping.
#
# Usage:
#   Rscript scripts/r_workflow/build_input_db.R [OUTPUT_DB] [STANDS]
#     OUTPUT_DB  path of the SQLite database to write   (default outputs/r_batch/FVS_Data.db)
#     STANDS     comma-separated STAND_IDs, or "all"    (default all)

suppressMessages(library(RSQLite))

get_script_dir <- function() {
  a <- commandArgs(FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) dirname(normalizePath(f)) else getwd()
}
repo_root <- normalizePath(file.path(get_script_dir(), "..", ".."))
source(file.path(get_script_dir(), "data_paths.R"))

stands <- read_input_csv(repo_root, INPUT_STAND_CSV)
trees  <- read_input_csv(repo_root, INPUT_TREE_CSV)

args <- commandArgs(trailingOnly = TRUE)
out_db    <- if (length(args) >= 1 && nzchar(args[1])) args[1] else
  file.path(repo_root, "outputs", "r_batch", "FVS_Data.db")
stand_arg <- if (length(args) >= 2 && nzchar(args[2])) args[2] else "all"

if (!identical(stand_arg, "all")) {
  ids    <- trimws(strsplit(stand_arg, ",")[[1]])
  stands <- stands[stands$STAND_ID %in% ids, , drop = FALSE]
  trees  <- trees[trees$STAND_ID %in% ids, , drop = FALSE]
}

dir.create(dirname(out_db), recursive = TRUE, showWarnings = FALSE)
if (file.exists(out_db)) unlink(out_db)
con <- dbConnect(SQLite(), out_db)
dbWriteTable(con, "FVS_StandInit", stands, overwrite = TRUE)
dbWriteTable(con, "FVS_TreeInit",  trees,  overwrite = TRUE)
dbDisconnect(con)

cat(sprintf("Wrote %s\n  FVS_StandInit: %d stands\n  FVS_TreeInit:  %d trees\n",
            normalizePath(out_db), nrow(stands), nrow(trees)))
