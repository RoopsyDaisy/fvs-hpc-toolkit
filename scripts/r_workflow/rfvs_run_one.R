#!/usr/bin/env Rscript
# rFVS array driver — run ONE (stand x scenario) job from a jobs manifest.
#
# This is the per-task unit of the rFVS-in-the-loop batch (example
# 03-rfvs-insim): R drives FVS via the embedder, running the job's own R logic
# between cycles. Each job names a stand, a projection length, and a *config* R
# file (HOOKS) — so different array tasks run different R logic. The driver is
# itself variant- and scenario-agnostic; all the per-job behaviour lives in the
# config file.
#
# Usage:
#   Rscript rfvs_run_one.R <jobs.csv> <row> [OUTROOT]
#     jobs.csv  columns: run_id, stand_id, years, config   (config = path to a .R)
#     row       1-based row index (= $SLURM_ARRAY_TASK_ID)
#     OUTROOT   per-run dirs created as <OUTROOT>/<run_id>/ (default r_rfvs_runs)
# Env:
#   FVS_DATA_DIR  inventory CSV dir (default <repo>/data; sample: examples/inventory)
#   FVS_BIN       dir with FVS<variant> + .so (the image sets /opt/fvs/bin)
#   VARIANT       FVS variant -> FVS<variant> (default ie)

get_script_dir <- function() {
  a <- commandArgs(FALSE); f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) dirname(normalizePath(f)) else getwd()
}
repo_root <- normalizePath(file.path(get_script_dir(), "..", ".."))
source(file.path(get_script_dir(), "data_paths.R"))
source(file.path(repo_root, "scripts", "reference_scripts", "fvs_keyword_file_functions.R"))
suppressMessages(library(rFVS))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) stop("usage: rfvs_run_one.R <jobs.csv> <row> [OUTROOT]")
jobs_csv <- args[1]
row      <- as.integer(args[2])
outroot  <- if (length(args) >= 3 && nzchar(args[3])) args[3] else "r_rfvs_runs"

jobs <- read.csv(jobs_csv, stringsAsFactors = FALSE)
if (is.na(row) || row < 1 || row > nrow(jobs))
  stop(sprintf("row %s out of range (jobs.csv has %d rows)", args[2], nrow(jobs)))
job      <- jobs[row, ]
run_id   <- job$run_id
stand_id <- job$stand_id
years    <- as.integer(job$years)
cfg_path <- normalizePath(job$config, mustWork = TRUE)
# Per-job seed so stochastic hooks reproduce across reruns (NA if no seed column).
seed     <- if (!is.null(job$seed) && !is.na(job$seed)) as.integer(job$seed) else NA_integer_
if (!is.na(seed)) set.seed(seed)

# Engine dir: $FVS_BIN (the image sets /opt/fvs/bin), else the dev-container fallback.
fvs_bin <- if (nzchar(Sys.getenv("FVS_BIN"))) Sys.getenv("FVS_BIN") else
           file.path(repo_root, ".devcontainer", "fvs-bin")
fvs_bin <- normalizePath(fvs_bin)
prog    <- paste0("FVS", Sys.getenv("VARIANT", "ie"))

stands <- read_input_csv(repo_root, INPUT_STAND_CSV)
trees  <- read_input_csv(repo_root, INPUT_TREE_CSV)
stand  <- stands[stands$STAND_ID == stand_id, , drop = FALSE]
tree   <- trees[trees$STAND_ID == stand_id, , drop = FALSE]
if (nrow(stand) == 0) stop("stand not in StandInit: ", stand_id)
if (nrow(tree)  == 0) stop("no trees for stand: ", stand_id)
stand <- stand[1, , drop = FALSE]
tree$fvs.TREE_ID <- seq_len(nrow(tree))

# Load the per-job config in its own environment (so its hooks close over any
# locals it defines, and rFVS functions resolve via the search path).
cfg   <- new.env(parent = globalenv())
sys.source(cfg_path, envir = cfg)
hooks <- if (exists("HOOKS", envir = cfg)) get("HOOKS", envir = cfg) else list()
desc  <- if (exists("DESCRIPTION", envir = cfg)) get("DESCRIPTION", envir = cfg) else basename(cfg_path)
if (!is.list(hooks)) stop("config must define HOOKS as a (possibly empty) named list: ", cfg_path)

# Each run gets its own dir (write.FVSfiles writes a relative "temp" dir, and FVS
# writes its outputs into the cwd) -> no collisions across array tasks.
workdir <- file.path(getwd(), outroot, run_id)
dir.create(workdir, recursive = TRUE, showWarnings = FALSE)
old_wd  <- setwd(workdir); on.exit(setwd(old_wd), add = TRUE)
dir.create("temp", showWarnings = FALSE)

fvsLoad(prog, fvs_bin)
filename <- write.FVSfiles(trees = tree, stand = stand, years_out = years,
                           calibrate = TRUE, triple = FALSE, add_regen = FALSE)
fvsSetCmdLine(paste0("--keywordfile=", filename, ".key"))

# Run FVS, executing the job's R hooks at their stop points + the summary at end.
out  <- do.call(fvsInteractRun, c(hooks, list(SimEnd = fvsGetSummary)))
si   <- grep("SimEnd", names(out))
summ <- out[[ if (length(si)) si[length(si)] else length(out) ]]   # matrix

write.csv(as.data.frame(summ), "stand_summary.csv", row.names = FALSE)

# Provenance: stamp enough to reproduce this run. toolkit_sha is best-effort (git
# may be absent in the image / .git not mounted); image digest comes from the
# caller via $IMAGE (e.g. the sbatch passes `apptainer inspect` output).
toolkit_sha <- tryCatch(
  system2("git", c("-C", repo_root, "rev-parse", "--short", "HEAD"),
          stdout = TRUE, stderr = FALSE)[1], error = function(e) NA)
if (length(toolkit_sha) == 0 || is.na(toolkit_sha)) toolkit_sha <- "unknown"
writeLines(c(
  sprintf("run_id:      %s", run_id),
  sprintf("stand:       %s", stand_id),
  sprintf("years:       %d", years),
  sprintf("config:      %s", cfg_path),
  sprintf("desc:        %s", desc),
  sprintf("seed:        %s", if (is.na(seed)) "none" else seed),
  sprintf("toolkit_sha: %s", toolkit_sha),
  sprintf("image:       %s", Sys.getenv("IMAGE", "unset")),
  sprintf("engine_bin:  %s", fvs_bin),
  sprintf("run_at:      %s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
), "run_info.txt")

cat(sprintf("[ok] %s  (stand=%s, %dyr) — %s\n", run_id, stand_id, years, desc))
