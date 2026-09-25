# 08_tables.R — paper tables (v2, per hectare) from the stage-1/2 results, as markdown.
# Output: R_werk/paper_tabellen<suffix>_<area>_<date>.md — main stage-2 table (5 specs),
# robustness table, stage-1 table and AMEs. Stars: *** p<0.01, ** p<0.05, * p<0.1.
# SEs are clustered on gemeente in both stages (stage 1: clogit with cluster()); see 06/07.

# Locate the directory this script lives in, so 00_config.R can be sourced no matter what
# the current working directory is: when run via Rscript, the path comes from the --file=
# command-line argument; otherwise fall back to getwd().
if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))

# Formatting helpers: stars() maps p-values to significance stars (fifelse is data.table's
# fast vectorised if-else); fmt_cell() renders one table cell as "estimate*** (se)".
stars    <- function(p) fifelse(p < .01, "***", fifelse(p < .05, "**", fifelse(p < .1, "*", "")))
fmt_cell <- function(est, se, p) sprintf("%.3f%s (%.3f)", est, stars(p), se)

# Named lookup vector: raw regressor names (as they appear in the model output) to readable
# row labels for the paper. Its ORDER also fixes the row order of the stage-2 tables, and
# terms without a label here are silently dropped from those tables (see md_table below).
labels <- c(
  iv = "Inclusive value", acq_ha = "Acquisition costs (EUR M per ha)",
  acq_mln = "Acquisition costs (EUR M per site)", ln_site_ha = "ln(site area, ha)",
  p_owner_occupier_buurt = "Share owner-occupiers neighbourhood (pp)",
  p_socialhousing_buurt  = "Share social housing neighbourhood (pp)",
  isprotectheritageareaTRUE = "Protected townscape",
  is_natura2000TRUE = "Natura 2000", vol_dlnp = "Price volatility (sd Δln p)",
  bouwperiode_incbouwperiode_tm1925    = "Construction period incumbent: pre-1926",
  bouwperiode_incbouwperiode_1926_1950 = "Construction period: 1926–1950",
  bouwperiode_incbouwperiode_1951_1965 = "Construction period: 1951–1965",
  bouwperiode_incbouwperiode_1966_1973 = "Construction period: 1966–1973",
  bouwperiode_incbouwperiode_1974_1981 = "Construction period: 1974–1981",
  bouwperiode_incbouwperiode_1982_1991 = "Construction period: 1982–1991",
  bouwperiode_incbouwperiode_1992_2001 = "Construction period: 1992–2001",
  `(Intercept)` = "Constant")

# Same idea for stage 1: ASC = alternative-specific constant, one per development-type
# cluster, measured relative to the omitted reference alternative (noted below).
asc_labels <- c(rv_ha = "Residual value (EUR M per ha)", rv_mln = "Residual value (EUR M per site)",
  rv_ha_margin = "Residual value incl. 7% margin (EUR M per ha)",
  alt_f2 = "ASC apartment high-density", alt_f3 = "ASC semi-detached",
  alt_f4 = "ASC apartment mid-density", alt_f5 = "ASC terraced",
  alt_f6 = "ASC detached large")   # reference: detached-teardown (cluster 1)

# Stage-1 table: the main model (per hectare) next to the two comparison models from 06.
# Columns without a model in the rds (older runs) are left out.
stage1_table <- function(s1) {
  mods <- list("per ha (main)" = list(b = s1$coef, V = s1$vcov, n = s1$n_est, ll = s1$loglik[["main"]]),
               "+ site characteristics" = if (!is.null(s1$coef_cov))
                 list(b = s1$coef_cov, V = s1$vcov_cov, n = s1$n_cov, ll = s1$loglik[["cov"]]),
               "7% margin" = if (!is.null(s1$coef_margin))
                 list(b = s1$coef_margin, V = s1$vcov_margin, n = s1$n_est, ll = s1$loglik[["margin"]]),
               "per site (previous)" = if (!is.null(s1$coef_total))
                 list(b = s1$coef_total, V = s1$vcov_total, n = s1$n_est, ll = s1$loglik[["total"]]))
  mods <- Filter(Negate(is.null), mods)
  cell <- function(m, t) {
    if (!t %in% names(m$b)) return("")
    se <- sqrt(diag(m$V))[[t]]
    fmt_cell(m$b[[t]], se, 2 * pnorm(-abs(m$b[[t]] / se)))
  }
  row <- function(lbl, cells) paste0("| ", lbl, " | ", paste(cells, collapse = " | "), " |")
  c(paste0("| | ", paste(names(mods), collapse = " | "), " |"),
    paste0("|", paste(rep("---", length(mods) + 1), collapse = "|"), "|"),
    vapply(names(asc_labels), function(t) row(asc_labels[[t]], vapply(mods, cell, "", t = t)), ""),
    row("Site characteristics x type", ifelse(names(mods) == "+ site characteristics", "yes", "no")),
    row("N sites", vapply(mods, function(m) format(m$n, big.mark = ","), "")),
    row("Log-likelihood", vapply(mods, function(m) format(round(m$ll, 1), big.mark = ","), "")),
    "", paste("SEs clustered on gemeente; reference type: detached teardown. Site characteristics:",
              "ln(site area), share social housing, protected townscape and building period (four groups",
              "plus unknown), each interacted with the type (35 coefficients, not shown); estimated on the",
              "sites where all characteristics are observed."))
}

# Hazard battery (09): row labels for the H1-H4 table; order = row order in the table.
hz_labels <- c(iv = "Inclusive value", acq_ha = "Acquisition costs (EUR M per ha)",
  ln_site_ha = "ln(site area, ha)",
  vol_roll  = "Regional volatility (rolling 5y sd)", g_roll  = "Regional growth expectation",
  vol_rollG = "Regional volatility (municipality)",  g_rollG = "Regional growth (municipality)",
  vol_nl    = "National volatility", g_nl = "National growth", year_c = "Linear trend (year)")

# Build the stage-1 scope table (residual-value coefficient per OAD scope) from the
# $scope element of the stage-1 rds. Returns markdown lines, or NULL for old rds files.
scope_table_stage1 <- function(s1) {
  if (is.null(s1$scope)) return(NULL)
  order <- intersect(c("nl", "base", "urban1500", "rural"), names(s1$scope))
  cells <- vapply(order, function(k) {
    b  <- s1$scope[[k]]$coef[["rv_ha"]]
    se <- sqrt(diag(s1$scope[[k]]$vcov))[["rv_ha"]]
    fmt_cell(b, se, 2 * pnorm(-abs(b / se)))
  }, character(1))
  ns <- vapply(order, function(k) format(s1$scope[[k]]$n, big.mark = ","), character(1))
  c(paste0("| | ", paste(order, collapse = " | "), " |"),
    paste0("|", paste(rep("---", length(order) + 1), collapse = "|"), "|"),
    paste0("| Residual value (EUR M per ha) | ", paste(cells, collapse = " | "), " |"),
    paste0("| N SN sites | ", paste(ns, collapse = " | "), " |"),
    "", "ASCs included in every scope; full ASC sets available on request. SEs clustered on gemeente.")
}

# Build the hazard H1-H4 table from the hazard rds (skipped if 09 has not run yet).
hazard_table <- function(hz) {
  specs <- unique(hz$specs$spec)
  dt <- copy(hz$specs)[term %chin% names(hz_labels)]
  dt[, cell_ := fmt_cell(estimate, se_cluster, p)]
  wide <- dcast(dt, term ~ factor(spec, levels = specs), value.var = "cell_", fill = "")
  wide <- wide[match(names(hz_labels)[names(hz_labels) %chin% wide$term], term)]
  wide[, term := hz_labels[term]]
  c(paste0("| | ", paste(specs, collapse = " | "), " |"),
    paste0("|", paste(rep("---", length(specs) + 1), collapse = "|"), "|"),
    wide[, paste0("| ", term, " | ", do.call(paste, c(.SD, sep = " | ")), " |"), .SDcols = specs],
    paste0("| Site-years (events) | ", paste(rep(sprintf("%s (%s)",
           format(hz$n_site_jaren, big.mark = ","), format(hz$n_events, big.mark = ",")),
           length(specs)), collapse = " | "), " |"),
    "", "All specs on the identical site-year sample; H1-H3 include year fixed effects, H4 replaces them by a linear trend plus the national series (indicative identification).")
}

# Build one markdown table (rows = regressors, columns = specifications) from the long
# stage-2 results table (one row per spec x term). Returns a character vector of markdown
# lines. NOTE: it edits its input by reference (:=), so callers pass copy(s2$specs).
md_table <- function(dt, spec_order) {
  # Keep only the requested specs (%chin% is data.table's fast %in% for strings). The
  # gemeente-level volatility variable is renamed so it shares the "Price volatility" row
  # with the base variant; := then adds a formatted "est*** (se)" cell column by reference.
  dt <- dt[spec %chin% spec_order]
  dt[term == "vol_dlnp_gem", term := "vol_dlnp"]
  dt[, cell_ := fmt_cell(estimate, se_cluster, p)]
  # dcast reshapes long to wide: one row per term, one column per spec. factor(levels=)
  # fixes the column order to spec_order; fill = "" leaves an empty cell where a term does
  # not occur in a spec (see README, data.table primer).
  wide <- dcast(dt, term ~ factor(spec, levels = spec_order), value.var = "cell_", fill = "")
  # Reorder the rows to follow the labels vector (terms without a label are dropped), then
  # replace the raw term names with the readable labels.
  wide <- wide[match(names(labels)[names(labels) %chin% wide$term], term)]
  wide[, term := labels[term]]
  # Grouped aggregation (by = spec): sample sizes are constant within a spec, so take the
  # first value per group and format with "." as thousands separator for the footer rows.
  ns <- dt[, .(n = format(n[1], big.mark = ","), n_y1 = format(n_y1[1], big.mark = ",")), by = spec]
  # Assemble the markdown lines: header with spec names, divider, one row per term (.SD is
  # the subset of spec columns, pasted together with " | "), and two footer rows with the
  # total N and the number of redeveloped sites per spec.
  header <- paste0("| ", paste(c("", spec_order), collapse = " | "), " |")
  divider <- paste0("|", paste(rep("---", length(spec_order) + 1), collapse = "|"), "|")
  rows <- wide[, paste0("| ", term, " | ", do.call(paste, c(.SD, sep = " | ")), " |"), .SDcols = spec_order]
  footer <- c(paste0("| N | ", paste(ns[match(spec_order, spec), n], collapse = " | "), " |"),
            paste0("| N redeveloped | ", paste(ns[match(spec_order, spec), n_y1], collapse = " | "), " |"))
  c(header, divider, rows, footer)
}

## ---------------------------------------------------------------------------
# Guard: the block below runs only when this file is executed directly as a script
# (sys.nframe() == 0) or when a caller has set run_08 <- TRUE before sourcing it.
# Sourcing the file without that flag just loads the helpers and label vectors above.
if (sys.nframe() == 0L || isTRUE(get0("run_08", ifnotfound = FALSE))) {
  # Load the saved stage-1 (conditional logit) and stage-2 (binomial logit) estimation
  # results; paths come from cfg (00_config.R).
  s1 <- readRDS(cfg$file_stage1_rds)
  s2 <- readRDS(cfg$file_stage2_rds)
  hz <- if (file.exists(cfg$file_hazard_rds)) readRDS(cfg$file_hazard_rds) else NULL

  # Build the whole markdown document as one character vector (one element per line):
  # title and scope, the stage-1 table (stage1_table: main model plus comparisons), the two
  # stage-2 tables via md_table (copy() protects s2$specs, since md_table edits its input
  # by reference), and the AME table, scaled x100 from proportions to percentage points.
  out <- c(
    sprintf("# Paper tables (v2, per hectare): %s, BAG %s, sample %s, price level %d", cfg$area, cfg$bag_date, cfg$stage1_sample, cfg$price_level_year),
    "", sprintf("Scope: OAD ≥ %d (base). SEs clustered on gemeente; *** p<0.01 ** p<0.05 * p<0.1.", cfg$oad_min),
    paste("Residual value (stage 1) and acquisition costs (stage 2) are per hectare. In stage 2 the area",
          "of a redeveloped site is that of its original (demolished) buildings, formed with the same rule",
          "as the unchanged sites; stage 2 controls for its log. Main analysis: sites with dwellings before."),
    "", "## Stage 1: conditional logit of the development type (SN sites)", "",
    stage1_table(s1),
    "", "## Stage 2: binomial logit of redevelopment, main specifications", "",
    md_table(copy(s2$specs), intersect(c("base", "no_size", "urban1500", "nl"), s2$specs$spec)),
    "", "urban1500 and nl use the inclusive value of their own stage-1 scope.",
    "", "## Stage 2: robustness", "",
    md_table(copy(s2$specs), intersect(c("no_bp", "winsor", "vol_muni", "excl2012", "n2000", "bbg_imput",
                                         "stage1_cov", "margin7", "total"), s2$specs$spec)),
    "", paste("stage1_cov: inclusive value from the stage-1 model with site characteristics x type.",
              "margin7: inclusive value from the stage-1 model with a developer margin of 7% in the residual value.",
              "total: the previous specification, with inclusive value and acquisition costs for the",
              "whole site and no size control."),
    "", "## Urban vs rural: stage 1 (residual-value coefficient per scope)", "",
    scope_table_stage1(s1),
    "", "## Urban vs rural: stage 2", "",
    md_table(copy(s2$specs), intersect(c("nl", "base", "urban1500", "rural"), s2$specs$spec)),
    "", "Each scope uses the inclusive value of its own stage-1 scope.",
    if ("nonres" %in% s2$specs$spec) c(
      "", "## Stage 2: sites with only non-residential buildings before (separate model)", "",
      md_table(copy(s2$specs), "nonres"),
      "", paste("Redeveloped sites where only non-residential buildings were demolished, against potential sites",
                "formed from the unchanged non-residential stock with the same rule (OAD >= 1000).")),
    if (!is.null(hz)) c(
      "", "## Discrete-time hazard: real-options battery (H1-H4)", "",
      hazard_table(hz)),
    "", "## Average marginal effects (base, percentage points)", "",
    "| | AME (pp) |", "|---|---|",
    s2$ame[, sprintf("| %s | %.3f |", labels[term], 100 * ame)])

  # Write the file to the work directory; the name is stamped with sample suffix, area
  # and BAG date so runs on different samples never overwrite each other.
  outfile <- file.path(cfg$dir_work, sprintf("paper_tabellen%s_%s_%s.md", cfg$sample_suffix, cfg$area, cfg$bag_date))
  writeLines(out, outfile, useBytes = FALSE)
  rd_log("Written: %s", outfile)
  rd_md_to_docx(outfile)
}
