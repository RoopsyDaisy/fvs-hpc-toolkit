# Scenario config: THIN — a stand-wide thinning driven from R.
#
# At TARGET_YEAR, cut a fixed proportion of every tree record via fvsCutNow().
# This is the simplest "R reaches in and treats the stand mid-simulation" pattern;
# swap the body for any rule you can compute in R (see harvest_largest.R for one
# that inspects the live trees first).
#
# fvsCutNow() must run at the AfterEM1 stop point (rFVS enforces this), so the
# hook is keyed there. It takes a per-tree-record cut proportion (0 = keep,
# 1 = cut); a scalar is recycled to every record.

DESCRIPTION <- "Thin 50% of TPA at 2043 (R-driven, fvsCutNow)"

.target_year <- 2043
.cut_frac    <- 0.50

HOOKS <- list(
  AfterEM1 = function() {
    yr <- as.numeric(fvsGetEventMonitorVariables("Year"))
    if (length(yr) && yr == .target_year) fvsCutNow(.cut_frac)
  }
)
