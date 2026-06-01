# Scenario config: BASELINE — project the stand with no treatment.
#
# A config is just an R file defining DESCRIPTION + HOOKS. HOOKS is a named list
# of rFVS stop-point -> function; the driver (rfvs_run_one.R) runs them via
# fvsInteractRun. An empty list = no between-cycle R action.

DESCRIPTION <- "Baseline projection — no treatment"

HOOKS <- list()
