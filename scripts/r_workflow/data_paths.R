# Shared input-data resolution for the R workflows.
#
# The workflows read the inventory CSVs from <repo>/data/. Those files are
# gitignored and not shipped (see data/README.md), so resolve them through here:
# a missing file then fails with an actionable pointer instead of a raw read.csv
# "cannot open file" error. Sourced by build_input_db.R, generate_keyfiles.R,
# generate_sweep.R and project_stand.R.

INPUT_STAND_CSV <- "FVS_Lubrecht_2023_FVS_StandInit.csv"
INPUT_TREE_CSV  <- "FVS_Lubrecht_2023_FVS_FVS_TreeInit.csv"

# Absolute path to an input CSV under <repo_root>/data, or stop with a pointer
# to data/README.md if it isn't present.
require_input_csv <- function(repo_root, filename) {
  p <- file.path(repo_root, "data", filename)
  if (!file.exists(p)) {
    stop(sprintf(
      paste0("Required input not found: %s\n",
             "  The R workflows need the inventory CSVs in data/ ",
             "(gitignored, not shipped).\n",
             "  See data/README.md for the expected files, schema, ",
             "and how to obtain them."),
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
