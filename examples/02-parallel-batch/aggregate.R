#!/usr/bin/env Rscript
# Aggregate a parameter-sweep / Monte Carlo batch: join each run's FVSOut.db
# summary back onto the sweep manifest (run_id -> parameters), so you can compare
# trajectories across treatments. Run from your work dir after the array finishes,
# inside the engine image (RSQLite comes from it):
#     apptainer exec "$SIF" Rscript aggregate.R [SWEEP_DIR] [RUNS_DIR]
#       SWEEP_DIR  dir holding sweep_manifest.csv  (default: sweep)
#       RUNS_DIR   dir holding <run_id>/FVSOut.db  (default: r_sweep_runs)
suppressMessages(library(RSQLite))

args      <- commandArgs(trailingOnly = TRUE)
sweep_dir <- if (length(args) >= 1 && nzchar(args[1])) args[1] else "sweep"
runs_dir  <- if (length(args) >= 2 && nzchar(args[2])) args[2] else "r_sweep_runs"

man <- read.csv(file.path(sweep_dir, "sweep_manifest.csv"), stringsAsFactors = FALSE)

agg <- do.call(rbind, lapply(seq_len(nrow(man)), function(i) {
  db <- file.path(runs_dir, man$run_id[i], "FVSOut.db")
  if (!file.exists(db)) { message("missing: ", db); return(NULL) }
  con <- dbConnect(SQLite(), db); on.exit(dbDisconnect(con))
  s <- dbGetQuery(con, "SELECT Year, BA, Tpa, MCuFt FROM FVS_Summary2 ORDER BY Year, RowID")
  # last row per Year = post-treatment value (FVS writes pre- + post-thin rows in a
  # treatment year); keeps a thinning visible as the residual, not the pre-thin BA.
  s <- s[!duplicated(s$Year, fromLast = TRUE), ]
  cbind(man[i, , drop = FALSE], s, row.names = NULL)
}))

out <- "sweep_aggregated.csv"
write.csv(agg, out, row.names = FALSE)
cat(sprintf("Wrote %s : %d rows from %d runs\n",
            out, nrow(agg), length(unique(agg$run_id))))

# Quick comparison: mean final-year basal area by treatment.
fin <- agg[agg$Year == max(agg$Year), ]
cat("\nMean final-year BA by residual-BA treatment:\n")
print(aggregate(BA ~ resid_ba, data = fin, FUN = function(x) round(mean(x), 1)),
      row.names = FALSE)
