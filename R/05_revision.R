# 05_revision.R — the specifications the referees asked for, alongside the published baseline.
# Output: Output/R/revision_<filedate>.rds and revision_tables_<filedate>.md/.docx
#
# Addresses three points of the revision plan:
#
#   1.1  Sample selection. ln() of a zero or negative change is missing, so neighbourhoods
#        without net growth leave the sample (transformation loses 35%). Poisson
#        pseudo-maximum likelihood with land area as exposure keeps them: it is defined at
#        zero, its coefficients are semi-elasticities just like the log-linear ones, and it
#        is the natural model for a count.
#
#   1.2  Gross versus net. The published column 1 and column 3 are gross while 2, 4 and 5
#        are net, although the manuscript calls all five net additions. The Poisson
#        specification uses GROSS additions per process throughout, which is both internally
#        consistent and what a count model requires (a net change can be negative).
#        Removals are reported separately rather than netted away.
#
#   1.5  Spatial structure (referee 2, point 5). Municipal fixed effects absorb the local
#        policy regime, standard errors are clustered on municipality, and a Randstad
#        interaction tests whether the associations differ between the conurbation and the
#        rest of the country. A residual intraclass correlation quantifies how much spatial
#        dependence the municipal level actually captures.

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))
suppressPackageStartupMessages(library(fixest))

## -- province -----------------------------------------------------------------------
# From the 20260812 export onwards the province is a column and 01_load_perwijk.R has
# already built it. For older vintages, fall back to the neighbourhood x year panel, whose
# provincie_rel is the row order of the CBS 2012 province layer (verified against one
# municipality per province: Groningen 0 ... Limburg 11).
add_province <- function(wijk) {
  if ("provincie" %in% names(wijk)) return(wijk[])
  p <- unique(fread(cfg$file_perwijk_jaar, select = c("WK_CODE", "provincie_rel")))
  setnames(p, c("wk_code", "provincie_rel"))
  stopifnot(!anyDuplicated(p$wk_code))
  wijk <- merge(wijk, p, by = "wk_code", all.x = TRUE)
  wijk[, provincie := factor(cfg$provinces[provincie_rel + 1L], levels = cfg$provinces)]
  wijk[, randstad  := factor(fifelse(as.character(provincie) %chin% cfg$randstad, "Randstad", "Rest"),
                             levels = c("Rest", "Randstad"))]
  if (wijk[is.na(provincie), .N]) rd_log("WARNING: %d neighbourhoods without a province", wijk[is.na(provincie), .N])
  wijk[]
}

## -- gross additions per process --------------------------------------------------
# One entry per column, mirroring cfg$outcomes but counting additions only.
# NOTE ON LABELS. These are GROSS additions, not the net change the log-linear models used.
# The labels say so, because otherwise a column headed "Replacement" silently changes meaning
# between the published table (units built minus units demolished on replacement sites) and the
# Poisson table (units built on replacement sites). Removals are a separate outcome with their own
# logic; Table 1 continues to report both sides.
cfg$gross <- list(
  all = list(label = "All additions",              expr = quote(count_sn_nieuwbouw + count_nieuwbouw + count_toevoeging + count_transformatie_plus)),
  sn  = list(label = "Replacement: construction",  expr = quote(count_sn_nieuwbouw)),
  nb  = list(label = "New build",                  expr = quote(count_nieuwbouw)),
  div = list(label = "Within-building: additions", expr = quote(count_toevoeging)),
  trf = list(label = "Transformation: to resid.",  expr = quote(count_transformatie_plus))
)
# Mirrors the split that 01_load_perwijk.R appends to cfg$outcomes; gross and net coincide
# for new build, since it has no removal counterpart.
cfg$gross_nb_split <- list(
  nb_in  = list(label = "New build: infill",    expr = quote(count_nieuwbouw_infill)),
  nb_out = list(label = "New build: expansion", expr = quote(count_nieuwbouw_expansion))
)

add_gross <- function(wijk) {
  g <- cfg$gross
  if (all(c("count_nieuwbouw_infill", "count_nieuwbouw_expansion") %in% names(wijk))) {
    g <- c(g, cfg$gross_nb_split)
    cfg$gross <<- g
  }
  for (nm in names(g)) wijk[, (paste0("gross_", nm)) := eval(g[[nm]]$expr)]
  wijk[]
}

## -- estimation --------------------------------------------------------------------
tidy_fit <- function(m, what) {
  ct <- summary(m)$coeftable
  data.table(spec = what, term = rownames(ct), estimate = ct[, 1], se = ct[, 2], p = ct[, 4])
}

rhs <- "p_huurcorp + uai + p_beschermd + p_onbebouwd + construction_period"

estimate_revision <- function(wijk) {
  res <- list(specs = list(), fit = list())
  for (nm in names(cfg$outcomes)) {
    y_log <- paste0("ln_", nm)        # published dependent variable (log net per ha)
    y_cnt <- paste0("gross_", nm)     # count of gross additions

    # (1) as published: OLS on the log of the net change per hectare, HC1.
    m1 <- feols(as.formula(paste(y_log, "~", rhs)), data = wijk, vcov = "hetero")

    # (2) PPML: gross additions, land area as exposure, no fixed effects.
    #     E[y] = L * exp(Xb), so the coefficients are comparable to those of (1).
    m2 <- fepois(as.formula(paste(y_cnt, "~", rhs)), data = wijk,
                 offset = ~log(land_area_ha), vcov = "hetero")

    # (3) PPML + municipal fixed effects, standard errors clustered on municipality.
    m3 <- fepois(as.formula(paste(y_cnt, "~", rhs, "| gm_code")), data = wijk,
                 offset = ~log(land_area_ha), vcov = ~gm_code)

    # (4) PPML + Randstad interaction, clustered on municipality. Municipal fixed effects
    #     would absorb the Randstad dummy, so this specification uses province effects.
    m4 <- fepois(as.formula(paste(y_cnt, "~ p_huurcorp * randstad + uai * randstad +",
                                  "p_beschermd + p_onbebouwd * randstad + construction_period")),
                 data = wijk, offset = ~log(land_area_ha), vcov = ~gm_code)

    fits <- list(published = m1, ppml = m2, ppml_fe = m3, ppml_randstad = m4)
    res$specs[[nm]] <- rbindlist(Map(tidy_fit, fits, names(fits)))
    # feols reports R2, fepois has no R2 — report McFadden's pseudo-R2 there instead.
    res$fit[[nm]] <- data.table(spec = names(fits),
                                n = vapply(fits, nobs, integer(1)),
                                fit = vapply(fits, function(m)
                                  if (inherits(m, "fixest") && m$method == "feols")
                                    fitstat(m, "r2")$r2 else fitstat(m, "pr2")$pr2, numeric(1)))
    rd_log("%-16s N: published %5d -> PPML %5d (+%d)", cfg$outcomes[[nm]]$label,
           nobs(m1), nobs(m2), nobs(m2) - nobs(m1))
  }

  # Spatial-dependence diagnostic. Regress the residuals of the published baseline on
  # municipality dummies: the R2 is the share of residual variance that lies BETWEEN
  # municipalities, i.e. an intraclass correlation. A sizeable value means the residuals are
  # spatially dependent and conventional robust standard errors are too small.
  res$icc <- rbindlist(lapply(names(cfg$outcomes), function(nm) {
    m <- feols(as.formula(paste0("ln_", nm, " ~ ", rhs)), data = wijk, vcov = "hetero")
    d <- data.table(r = resid(m), gm = wijk[obs(m), gm_code])
    data.table(outcome = cfg$outcomes[[nm]]$label,
               icc = fitstat(feols(r ~ 1 | gm, data = d), "r2")$r2)
  }))
  res
}

## -- reporting ----------------------------------------------------------------------
stars    <- function(p) fifelse(p < cfg$stars_main[1], "***", fifelse(p < cfg$stars_main[2], "**", fifelse(p < cfg$stars_main[3], "*", "")))
fmt_cell <- function(est, se, p) fifelse(is.na(est), "", sprintf("%.3f%s (%.3f)", est, stars(p), se))

main_terms <- c(p_huurcorp = "Social housing (% of stock)",
                uai = "Urban attractivity index",
                p_beschermd = "Protected heritage (% of land)",
                p_onbebouwd = "Land potentially available (% of land)")

# One table per outcome: rows = the four main regressors, columns = specifications.
spec_table <- function(res, nm) {
  specs <- c("published", "ppml", "ppml_fe", "ppml_randstad")
  # In the Randstad column the reference group is the rest of the country, so the main
  # effects there are the associations OUTSIDE the Randstad; the difference is tabulated
  # separately below.
  hdr   <- c("OLS, log net change (as published)", "PPML, gross additions",
             "PPML + municipality FE", "PPML, outside Randstad")
  dt <- res$specs[[nm]][term %chin% names(main_terms)]
  dt[, cell_ := fmt_cell(estimate, se, p)]
  wide <- dcast(dt, term ~ factor(spec, levels = specs), value.var = "cell_", fill = "")
  wide <- wide[match(names(main_terms)[names(main_terms) %chin% wide$term], term)]
  wide[, term := main_terms[term]]
  f <- res$fit[[nm]]
  c(sprintf("**%s**", cfg$outcomes[[nm]]$label), "",
    paste0("| | ", paste(hdr, collapse = " | "), " |"),
    paste0("|", paste(rep("---", length(specs) + 1), collapse = "|"), "|"),
    wide[, paste0("| ", term, " | ", do.call(paste, c(.SD, sep = " | ")), " |"), .SDcols = specs],
    paste0("| Observations | ", paste(format(f[match(specs, spec), n], big.mark = ","), collapse = " | "), " |"),
    paste0("| R2 / pseudo-R2 | ", paste(sprintf("%.3f", f[match(specs, spec), fit]), collapse = " | "), " |"), "")
}

# Randstad differences: the interaction terms, one row per regressor.
randstad_table <- function(res) {
  cols <- names(cfg$outcomes)
  dt <- rbindlist(lapply(cols, function(nm)
    copy(res$specs[[nm]])[spec == "ppml_randstad" & grepl("randstadRandstad", term)][, outcome := nm][]))
  dt[, term := sub(":randstadRandstad|randstadRandstad:", "", term)]
  dt[, cell_ := fmt_cell(estimate, se, p)]
  wide <- dcast(dt[term %chin% c(names(main_terms), "")], term ~ factor(outcome, levels = cols),
                value.var = "cell_", fill = "")
  wide <- wide[match(names(main_terms)[names(main_terms) %chin% wide$term], term)]
  wide[, term := main_terms[term]]
  c(paste0("| Difference in the Randstad | ", paste(vapply(cols, function(nm)
      cfg$outcomes[[nm]]$label, character(1)), collapse = " | "), " |"),
    paste0("|", paste(rep("---", length(cols) + 1), collapse = "|"), "|"),
    wide[, paste0("| ", term, " | ", do.call(paste, c(.SD, sep = " | ")), " |"), .SDcols = cols])
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_05", ifnotfound = FALSE))) {
  wijk <- add_gross(add_province(readRDS(cfg$file_wijk_rds)))
  res  <- estimate_revision(wijk)
  saveRDS(res, file.path(cfg$dir_work, sprintf("revision_%s.rds", cfg$filedate)))

  md <- c(sprintf("# Revision specifications (export %s)", cfg$filedate), "",
    "Each column adds one of the referees' requests to the published baseline.",
    "PPML is Poisson pseudo-maximum likelihood on GROSS additions per process, with",
    "neighbourhood land area as exposure, so its coefficients are semi-elasticities and",
    "directly comparable with the log-linear ones. Unlike the published specification it",
    "retains neighbourhoods without net growth.", "",
    "## Main regressors per development process", "",
    unlist(lapply(names(cfg$outcomes), function(nm) spec_table(res, nm))),
    "## Randstad versus the rest of the country", "",
    "Interaction terms from the PPML specification: the additional association inside the",
    "Randstad provinces, relative to the rest of the country.", "",
    randstad_table(res), "",
    "## Spatial dependence", "",
    "Share of the residual variance of the published baseline that lies between",
    "municipalities (an intraclass correlation). A sizeable value means the residuals are",
    "spatially dependent, so the published heteroskedasticity-robust standard errors",
    "understate uncertainty and clustering on municipality is required.", "",
    "| Outcome | Residual ICC (municipality) |", "|---|---|",
    res$icc[, sprintf("| %s | %.3f |", outcome, icc)], "",
    "Robust standard errors in parentheses; clustered on municipality where fixed effects",
    "or the Randstad interaction are used. *** p<0.01, ** p<0.05, * p<0.1.")

  f <- file.path(cfg$dir_work, sprintf("revision_tables_%s.md", cfg$filedate))
  writeLines(md, f)
  rd_log("Written: %s", f)
  rd_md_to_docx(f)

  cat("\n---- residual intraclass correlation by municipality ----\n"); print(res$icc)
}
