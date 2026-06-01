# Scenario config: HARVEST-LARGEST — a TPA-weighted diameter cut computed in R.
#
# At TARGET_YEAR, remove the largest stems (by DBH) until ~CUT_SHARE of the
# stand's TPA (stems/acre) is cut. It is **TPA-weighted on purpose**: FVS tree
# records carry expansion factors, so "the largest 30% of *records*" is not "30%
# of *stems*". This is the case the keyword-file Event Monitor can't easily
# express — a decision read from the live tree list and weighted correctly, in R.

DESCRIPTION <- "Harvest largest stems until ~30% of TPA is cut at 2043 (R-computed, TPA-weighted, fvsCutNow)"

.target_year <- 2043
.cut_share   <- 0.30   # fraction of stand TPA (stems) to remove, from the top down

HOOKS <- list(
  AfterEM1 = function() {
    yr <- as.numeric(fvsGetEventMonitorVariables("Year"))
    if (!length(yr) || yr != .target_year) return(invisible())
    ta    <- fvsGetTreeAttrs(c("dbh", "tpa"))   # one row per live tree record
    ord   <- order(ta$dbh, decreasing = TRUE)   # largest DBH first
    share <- ta$tpa[ord] / sum(ta$tpa)          # each record's share of stand TPA
    cum   <- cumsum(share)
    # Cut whole records from the top until cumulative removed stems reach the
    # target; the record that crosses it is cut partially so the removed TPA is
    # ~exactly .cut_share. (cum - share = cumulative TPA *before* this record.)
    pc <- pmin(1, pmax(0, (.cut_share - (cum - share)) / share))
    propcut <- numeric(nrow(ta)); propcut[ord] <- pc
    fvsCutNow(propcut)                           # per-record cut proportion, 0..1
  }
)
