#!/usr/bin/env Rscript
#
# R interactive track: drive FVS as a library via rFVS (the "R drives FVS" example).
#
# Mirrors the course reference workflow
# (scripts/reference_scripts/fvs_growth_projection.R) but adapted to run in this
# container: CSV inputs instead of the network Excel file, and the engine from
# .devcontainer/fvs-bin instead of a Windows FVSbin path. It generates a flat-file
# keyword + tree file with the reference write.FVSfiles(), loads the FVS shared
# library, runs it cycle-by-cycle with fvsInteractRun(), and harvests per-cycle
# tree lists + the stand summary into R *in memory* (no output database).
#
# This is the counterpart to the file-based batch track (build_input_db.R +
# generate_keyfiles.R): use this when you need R logic *between* FVS cycles; use
# the batch track to run many stands/scenarios at scale.
#
# Usage:
#   Rscript scripts/r_workflow/project_stand.R [STAND_ID] [YEARS] [FVS_BIN]
#     STAND_ID  stand to project           (default CARB_2)
#     YEARS     projection length in years (default 55)
#     FVS_BIN   dir containing FVSie.so    (default .devcontainer/fvs-bin)

get_script_dir <- function() {
  a <- commandArgs(FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) dirname(normalizePath(f)) else getwd()
}
repo_root <- normalizePath(file.path(get_script_dir(), "..", ".."))
source(file.path(get_script_dir(), "data_paths.R"))
source(file.path(repo_root, "scripts", "reference_scripts",
                 "fvs_keyword_file_functions.R"))
suppressMessages(library(rFVS))

stands <- read_input_csv(repo_root, INPUT_STAND_CSV)
trees  <- read_input_csv(repo_root, INPUT_TREE_CSV)

args     <- commandArgs(trailingOnly = TRUE)
stand_id <- if (length(args) >= 1 && nzchar(args[1])) args[1] else "CARB_2"
years    <- if (length(args) >= 2 && nzchar(args[2])) as.integer(args[2]) else 55L
fvs_bin  <- if (length(args) >= 3 && nzchar(args[3])) args[3] else
  file.path(repo_root, ".devcontainer", "fvs-bin")
fvs_bin  <- normalizePath(fvs_bin)  # absolute: survives the setwd() below

stand <- stands[stands$STAND_ID == stand_id, , drop = FALSE]
tree  <- trees[trees$STAND_ID == stand_id, , drop = FALSE]
if (nrow(stand) == 0) stop("stand not in StandInit: ", stand_id)
if (nrow(tree)  == 0) stop("no trees for stand: ", stand_id)
stand <- stand[1, , drop = FALSE]
tree$fvs.TREE_ID <- seq_len(nrow(tree))  # consecutive ids so output trees link back

# write.FVSfiles() writes into a relative "temp" dir; run from a per-stand workdir
workdir <- file.path(repo_root, "outputs", "r_project", stand_id)
dir.create(workdir, recursive = TRUE, showWarnings = FALSE)
old_wd <- setwd(workdir)
on.exit(setwd(old_wd), add = TRUE)
dir.create("temp", showWarnings = FALSE)

# pull a tree list out of the running simulation at a cycle stop point (rFVS API)
fetchTrees <- function() {
  tl <- fvsGetTreeAttrs(c("id", "plot", "age", "species", "dbh", "ht",
                          "cratio", "tpa", "mcuft", "bdft"))
  tl$year <- fvsGetEventMonitorVariables("year")
  tl
}

fvsLoad("FVSie", fvs_bin)
filename <- write.FVSfiles(trees = tree, stand = stand, years_out = years,
                           calibrate = TRUE, triple = FALSE, add_regen = FALSE)
fvsSetCmdLine(paste0("--keywordfile=", filename, ".key"))

# run FVS, executing R at the AfterEM1 stop point each cycle and at SimEnd
fvs_output <- fvsInteractRun(AfterEM1 = "fetchTrees()", SimEnd = fvsGetSummary)

# combine the per-cycle tree lists and map variant species codes to FIA
spp <- as.data.frame(fvsGetSpeciesCodes()); spp$spp_num <- seq_len(nrow(spp))
tree_list <- NULL
for (j in seq_len(length(fvs_output) - 1)) {
  nt <- fvs_output[[j]]$AfterEM1
  if (is.null(nt)) next
  nt <- merge(nt, spp, by.x = "species", by.y = "spp_num", all.x = TRUE)
  tree_list <- rbind(tree_list, nt)
}
stand_summary <- fvs_output[[length(fvs_output)]]

write.csv(tree_list, "tree_list.csv", row.names = FALSE)
write.csv(stand_summary, "stand_summary.csv", row.names = FALSE)

cat(sprintf("\nStand %s: projected %d years via rFVS::fvsInteractRun\n",
            stand_id, years))
cat(sprintf("Per-cycle tree records: %d   |   summary cycles: %d\n",
            if (is.null(tree_list)) 0L else nrow(tree_list), nrow(stand_summary)))
cat(sprintf("Outputs: %s/{tree_list.csv,stand_summary.csv}\n\n", workdir))
cat("Stand summary (head):\n")
print(utils::head(stand_summary))
