# Integration: run the real FVS engine on a known-good upstream example and
# assert a clean run + a real multi-cycle projection. Exercises the same
# `FVS<variant> --keywordfile=` invocation the cluster batch runner
# (cluster/fvs_run_one.sh) uses, against a guaranteed-valid, variant-matched
# fixture. Self-skips where the engine isn't present, so the unit layer still
# runs on a plain R host (lab PC). Uses check()/skip()/FIXTURE_DIR from
# run_tests.R.
#
# Variant-parametrized: CASES below is keyed by FVS variant. Today only `ie`
# (the variant CI builds) has a fixture, so the others are inert. To add one:
#   1. drop <example>.key (+ .tre if flat-file) under tests/fixtures/fvs_<v>/,
#   2. add a CASES row (variant, dir, key, tre-or-NA, stand-id echoed in output),
#   3. ensure that variant is actually built (FVS_VARIANT / the build matrix),
# and it runs automatically. A row whose binary isn't in the image self-skips.
CASES <- list(
  list(variant = "ie", dir = "fvs_ie", key = "iet01.key",
       tre = "iet01.tre", stand = "S248112")
)

for (case in CASES) (function(case) {
  prog <- paste0("FVS", case$variant)
  tag  <- function(name) paste0("fvs/", case$variant, "-", name)  # e.g. fvs/ie-projection

  bd  <- Sys.getenv("FVS_BIN", "")
  exe <- if (nzchar(bd) && file.exists(file.path(bd, prog))) file.path(bd, prog)
         else { w <- Sys.which(prog); if (nzchar(w)) unname(w) else "" }
  if (!nzchar(exe)) return(skip(tag("run"), paste(prog, "not on PATH/FVS_BIN")))

  fxd <- file.path(FIXTURE_DIR, case$dir)
  inputs <- c(case$key, if (!is.na(case$tre)) case$tre)  # .tre must sit next to .key
  run <- tempfile(paste0(case$variant, "_")); dir.create(run)
  file.copy(file.path(fxd, inputs), run)
  old <- setwd(run); on.exit(setwd(old), add = TRUE)

  st <- suppressWarnings(system2(exe, paste0("--keywordfile=", case$key),
                                 stdout = "run.console", stderr = "run.console"))

  # the main text output (.out preferred, else .sum / console), as one vector
  outfiles <- list.files(run, pattern = "\\.(out|sum)$", full.names = TRUE)
  outtxt   <- unlist(lapply(outfiles, readLines, warn = FALSE))

  # FVS STOP codes 0/10/20 are all non-fatal completions (see docs/HELLGATE_FVS.md).
  check(tag("exit"), isTRUE(st %in% c(0L, 10L, 20L)))

  # it must produce a non-empty main output file (.out or run summary .sum)
  check(tag("output"),
        length(outfiles) >= 1 && any(file.info(outfiles)$size > 0))

  # the run must not report a FATAL error in the main output
  check(tag("no-fatal"),
        !any(grepl("FATAL", outtxt, ignore.case = TRUE)))

  # No FVS-formatted error/warning messages in the output (borrowed from
  # microfvs's test_fvs_build.py, which asserts "ERROR:"/"WARNING:" absent). The
  # colon form is FVS's message prefix, distinct from the words appearing in
  # prose/column headers. On failure we print the offending lines so the match
  # can be calibrated against the real .out.
  check(tag("no-error-msgs"), {
    hits <- grep("(ERROR|WARNING):", outtxt, ignore.case = TRUE, value = TRUE)
    if (length(hits))
      cat("    [", tag("no-error-msgs"), "] matched:\n",
          paste("      |", utils::head(hits, 10), collapse = "\n"), "\n", sep = "")
    length(hits) == 0
  })

  # FVS actually ingested our keyword file (the stand id is echoed in the run
  # header) -- guards against a boilerplate-only / empty run passing the above.
  check(tag("read-stand"), any(grepl(case$stand, outtxt, fixed = TRUE)))

  # The real correctness signal: FVS must have computed a multi-cycle PROJECTION
  # with non-zero stand metrics, not merely exited 0 (it returns 0 even on
  # per-stand errors). The example sends its summary to the .sum text file via
  # ECHOSUM (it does not request DB output -- FVSOut.db holds only admin tables),
  # so we parse the .sum. Each data row is one projection cycle:
  #   <4-digit year> <age> <TPA> <BA> ... (~24 numeric fields); case headers
  #   start with -999 and are skipped. Format-tolerant: we match by the
  #   leading-year shape and read TPA/BA positionally, so it survives column
  #   drift across FVS versions.
  sumf <- list.files(run, pattern = "\\.sum$", full.names = TRUE)
  cycle_row <- function(line) {                       # numeric fields, or NULL if not a cycle row
    toks <- strsplit(trimws(line), "\\s+")[[1]]
    if (length(toks) < 6 || !grepl("^(19|20)[0-9]{2}$", toks[1])) return(NULL)
    suppressWarnings(as.numeric(toks))                # [1]=year [2]=age [3]=TPA [4]=BA ...
  }
  check(tag("projection"), {
    if (!length(sumf)) FALSE else {
      rows <- Filter(Negate(is.null),
                     lapply(readLines(sumf[1], warn = FALSE), cycle_row))
      yrs <- vapply(rows, `[`, numeric(1), 1L)
      tpa <- vapply(rows, `[`, numeric(1), 3L)
      ba  <- vapply(rows, `[`, numeric(1), 4L)
      # >= 3 distinct projection cycles, and most carry positive stand metrics.
      # "most" (not all): a thinning/shelterwood prescription can drive a cycle's
      # stand very low -- a degenerate "ran but computed nothing" run instead
      # yields no rows or all-zeros, which this still fails.
      length(rows) >= 3 && length(unique(yrs)) >= 3 &&
        mean(tpa > 0, na.rm = TRUE) > 0.5 && mean(ba > 0, na.rm = TRUE) > 0.5
    }
  })

  # one-line provenance in the log (engine version + run id come from .sum row 1)
  cat(sprintf("  %s/%s: exit=%s, %d output files, .sum=%s bytes\n",
              case$variant, case$key, st, length(list.files(run)),
              if (length(sumf)) file.info(sumf[1])$size else 0))
})(case)
