# Scenario config: HARVEST-LARGEST — a diameter-limit cut computed in R.
#
# This is the case the keyword-file Event Monitor can't easily express: at
# TARGET_YEAR, look at the *live* tree list, find the DBH cutoff for the largest
# share of stems, and remove those — a decision made from the running simulation's
# state, in R. Shows why you'd reach for the rFVS-in-the-loop pattern at all.

DESCRIPTION <- "Harvest the largest ~30% of stems by DBH at 2043 (R-computed, fvsCutNow)"

.target_year  <- 2043
.keep_below_q <- 0.70   # cut at/above this DBH quantile -> removes the top ~30%

HOOKS <- list(
  AfterEM1 = function() {
    yr <- as.numeric(fvsGetEventMonitorVariables("Year"))
    if (!length(yr) || yr != .target_year) return(invisible())
    dbh <- fvsGetTreeAttrs("dbh")$dbh                 # one value per live tree record
    thr <- as.numeric(stats::quantile(dbh, .keep_below_q))
    fvsCutNow(as.numeric(dbh >= thr))                 # 1 = cut, 0 = keep, per record
  }
)
