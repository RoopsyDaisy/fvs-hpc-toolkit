# Shared input-data resolution for the R workflows.
#
# The workflows read the inventory CSVs from a data directory, default <repo>/data/
# (gitignored, you supply your own — see data/README.md). Set the env var
# FVS_DATA_DIR to read from elsewhere — e.g. the bundled 3-stand sample that ships
# with the repo so Track A runs straight from a clone:
#     FVS_DATA_DIR=examples/inventory
# A relative FVS_DATA_DIR is resolved against the repo root; an absolute one is
# used as-is. Resolving through here means a missing file fails with an actionable
# pointer instead of a raw read.csv "cannot open file" error. Sourced by
# build_input_db.R, generate_keyfiles.R, generate_sweep.R and project_stand.R.

INPUT_STAND_CSV <- "FVS_Lubrecht_2023_FVS_StandInit.csv"
INPUT_TREE_CSV  <- "FVS_Lubrecht_2023_FVS_FVS_TreeInit.csv"

# Absolute path to an input CSV in the data dir (FVS_DATA_DIR or <repo_root>/data),
# or stop with a pointer to data/README.md if it isn't present.
require_input_csv <- function(repo_root, filename) {
  data_dir <- Sys.getenv("FVS_DATA_DIR", "")
  base <- if (!nzchar(data_dir)) file.path(repo_root, "data")
          else if (startsWith(data_dir, "/")) data_dir
          else file.path(repo_root, data_dir)
  p <- file.path(base, filename)
  if (!file.exists(p)) {
    stop(sprintf(
      paste0("Required input not found: %s\n",
             "  Put your inventory CSVs in data/ (see data/README.md), or run the\n",
             "  bundled 3-stand sample with  FVS_DATA_DIR=examples/inventory ."),
      p), call. = FALSE)
  }
  p
}

# Read an input CSV (UTF-8-BOM, as exported by Excel / the FVS DB tools) after
# the existence check.
read_input_csv <- function(repo_root, filename) {
  read.csv(require_input_csv(repo_root, filename),
           fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
}
