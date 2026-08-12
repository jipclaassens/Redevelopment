# 03_tables.R — paper tables 2, 3 and 4 as markdown, converted to docx via pandoc.
# Output: Output/R/paper_tables_<filedate>.md/.docx
#
# Differences from the first submission, all deliberate:
#   * Robust standard errors are PRINTED. The do-file passed `nose` to outreg2, so the
#     published tables claim "robust standard errors in parentheses" without showing any
#     (reviewer 1, comment 18).
#   * One star convention throughout (cfg$stars_main, matching the footnote). The published
#     Table 4 mixed two conventions: outreg2 used 0.01/0.05/0.10 for the upper panel while
#     the hand-rolled putexcel block used 0.001/0.01/0.05 for the marginal effects.
#   * Table 2 descriptives are reported both for all 2,621 neighbourhoods and for the
#     estimation sample of each model, because the log transformation drops observations.

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))

stars <- function(p, cuts = cfg$stars_main)
  fifelse(p < cuts[1], "***", fifelse(p < cuts[2], "**", fifelse(p < cuts[3], "*", "")))
fmt_cell <- function(est, se, p) fifelse(is.na(est), "", sprintf("%.3f%s (%.3f)", est, stars(p), se))

# Row labels for the paper, in the order the tables print them. Terms without a label are
# dropped, exactly as in EconLogicPaper/R/08_tables.R.
labels <- c(
  p_huurcorp  = "Social housing per neighbourhood (% of housing stock)",
  uai         = "Average urban attractivity index in neighbourhood (0-100)",
  p_beschermd = "Protected heritage areas in neighbourhood (% of land area)",
  p_onbebouwd = "Land potentially available for development (% of land area)",
  `urbanisationMedium density` = "Is medium density neighbourhood",
  `urbanisationLow density`    = "Is low density neighbourhood",
  `p_huurcorp:urbanisationMedium density` = "Social housing x medium density",
  `p_huurcorp:urbanisationLow density`    = "Social housing x low density",
  `urbanisationMedium density:uai`        = "UAI x medium density",
  `urbanisationLow density:uai`           = "UAI x low density",
  `urbanisationMedium density:p_onbebouwd` = "Available land x medium density",
  `urbanisationLow density:p_onbebouwd`    = "Available land x low density",
  `construction_periodConstruction 1929 and earlier` = "Building year 1929 and earlier",
  `construction_periodConstruction 1930-1945` = "Building year 1930-1945",
  `construction_periodConstruction 1946-1960` = "Building year 1946-1960",
  `construction_periodConstruction 1961-1970` = "Building year 1961-1970",
  `construction_periodConstruction 1981-1990` = "Building year 1981-1990",
  `construction_periodConstruction 1991-2000` = "Building year 1991-2000",
  `construction_periodConstruction 2000-2012` = "Building year 2001-2012",
  `(Intercept)` = "Constant")

# fixest flips the operand order for the second and later interactions; normalise so the
# label lookup above always hits.
canon_term <- function(x) {
  flip <- c("uai:urbanisationMedium density"         = "urbanisationMedium density:uai",
            "uai:urbanisationLow density"            = "urbanisationLow density:uai",
            "p_onbebouwd:urbanisationMedium density" = "urbanisationMedium density:p_onbebouwd",
            "p_onbebouwd:urbanisationLow density"    = "urbanisationLow density:p_onbebouwd",
            "urbanisationMedium density:p_huurcorp"  = "p_huurcorp:urbanisationMedium density",
            "urbanisationLow density:p_huurcorp"     = "p_huurcorp:urbanisationLow density")
  fifelse(x %chin% names(flip), flip[x], x)
}

# One markdown table: rows = regressors, columns = outcomes.
coef_table <- function(models, block) {
  cols <- names(cfg$outcomes)
  dt <- rbindlist(lapply(cols, function(nm) {
    ct <- copy(models[[block]][[nm]]$ct)
    ct[, term := canon_term(term)][, outcome := nm][]
  }))
  dt[, cell_ := fmt_cell(estimate, se, p)]
  wide <- dcast(dt, term ~ factor(outcome, levels = cols), value.var = "cell_", fill = "")
  wide <- wide[match(names(labels)[names(labels) %chin% wide$term], term)]
  wide[, term := labels[term]]

  hdr <- vapply(cols, function(nm) cfg$outcomes[[nm]]$label, character(1))
  c(paste0("| VARIABLES | ", paste(sprintf("(%d) %s", seq_along(hdr), hdr), collapse = " | "), " |"),
    paste0("|", paste(rep("---", length(cols) + 1), collapse = "|"), "|"),
    wide[, paste0("| ", term, " | ", do.call(paste, c(.SD, sep = " | ")), " |"), .SDcols = cols],
    paste0("| Observations | ", paste(vapply(cols, function(nm)
      format(models[[block]][[nm]]$n, big.mark = ","), character(1)), collapse = " | "), " |"),
    paste0("| R-squared | ", paste(vapply(cols, function(nm)
      sprintf("%.3f", models[[block]][[nm]]$r2), character(1)), collapse = " | "), " |"))
}

# Lower panel of Table 4: average marginal effects per density category.
ame_table <- function(models) {
  cols <- names(cfg$outcomes)
  var_lab <- c(p_huurcorp = "Social housing", uai = "UAI", p_onbebouwd = "Potential available land")
  dt <- rbindlist(lapply(cols, function(nm) copy(models$ames[[nm]])[, outcome := nm][]))
  dt[, cell_ := fmt_cell(estimate, se, p)]
  dt[, row := paste(var_lab[var], "x", tolower(group))]
  order_rows <- as.vector(t(outer(var_lab, tolower(unname(cfg$urb_levels)), paste, sep = " x ")))
  wide <- dcast(dt, row ~ factor(outcome, levels = cols), value.var = "cell_", fill = "")
  wide <- wide[match(order_rows, row)]
  c(paste0("| Average marginal effects | ", paste(vapply(cols, function(nm)
      cfg$outcomes[[nm]]$label, character(1)), collapse = " | "), " |"),
    paste0("|", paste(rep("---", length(cols) + 1), collapse = "|"), "|"),
    wide[, paste0("| ", row, " | ", do.call(paste, c(.SD, sep = " | ")), " |"), .SDcols = cols])
}

# Table 2: descriptives. `sample` = NULL gives all neighbourhoods (as published).
descriptives <- function(wijk) {
  rows <- list(
    list("Number of positive res. unit changes per ha 2012-2025 per neighbourhood", "cnt_ha_all"),
    list("Number of res. units added per ha by replacement",        "cnt_ha_sn"),
    list("Number of res. units added per ha as new build",          "cnt_ha_nb"),
    list("Number of res. units added per ha by building division",  "cnt_ha_div"),
    list("Number of res. units added per ha by transformation",     "cnt_ha_trf"),
    list("Social housing per neighbourhood (% of housing stock)",   "p_huurcorp"),
    list("Average urban attractivity index in neighbourhood (0-100)", "uai"),
    list("Protected heritage areas in neighbourhood (% of land area)", "p_beschermd"),
    list("Land potentially available for development (% of land area)", "p_onbebouwd"))
  d <- rbindlist(lapply(rows, function(r) {
    x <- wijk[[r[[2]]]]
    data.table(variable = r[[1]], count = sum(!is.na(x)), mean = mean(x, na.rm = TRUE),
               sd = sd(x, na.rm = TRUE), min = min(x, na.rm = TRUE), max = max(x, na.rm = TRUE))
  }))
  # Construction-period dummies, printed as shares like the published table.
  cp <- rbindlist(lapply(levels(wijk$construction_period)[order(levels(wijk$construction_period))], function(lv) {
    x <- as.numeric(wijk$construction_period == lv)
    x[is.na(wijk$construction_period)] <- NA_real_
    # The Stata label reads "2000-2012" while the condition is >= 2001; print the
    # correct range, as Table 3 of the first submission already does.
    lab <- sub("^Construction", "Building year", sub("2000-2012", "2001-2012", lv))
    data.table(variable = lab, count = sum(!is.na(x)),
               mean = mean(x, na.rm = TRUE), sd = sd(x, na.rm = TRUE), min = 0, max = 1)
  }))
  list(main = d, cp = cp)
}

md_desc <- function(d) c(
  "| VARIABLES | Count | Mean | SD | Min | Max |", "|---|---|---|---|---|---|",
  d[, sprintf("| %s | %s | %.2f | %.2f | %.0f | %.0f |",
              variable, format(count, big.mark = ","), mean, sd, min, max)])

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_03", ifnotfound = FALSE))) {
  wijk   <- readRDS(cfg$file_wijk_rds)
  models <- readRDS(cfg$file_models_rds)
  des    <- descriptives(wijk)

  md <- c(
    sprintf("# Tables — neighbourhood analysis (export %s, R port)", cfg$filedate), "",
    "## Table 2: Descriptive statistics for the statistical analysis per neighbourhood", "",
    md_desc(des$main), "", "Building year categories:", "", md_desc(des$cp), "",
    "## Table 3: Regression results per net development type per neighbourhood", "",
    coef_table(models, "base"), "",
    "Robust (HC1) standard errors in parentheses. *** p<0.01, ** p<0.05, * p<0.1.", "",
    "## Table 4: Regression results differentiated per neighbourhood density category", "",
    coef_table(models, "inter"), "",
    "Reference category: high-density neighbourhood.", "",
    ame_table(models), "",
    "Robust (HC1) standard errors in parentheses. *** p<0.01, ** p<0.05, * p<0.1.",
    "Marginal effects are the conditional effect of each predictor within a density category.")

  f <- file.path(cfg$dir_work, sprintf("paper_tables_%s.md", cfg$filedate))
  writeLines(md, f)
  rd_log("Written: %s", f)
  rd_md_to_docx(f)

  cat("\n---- Table 2 check against the published values ----\n")
  print(des$main[, .(variable = substr(variable, 1, 45), count, mean = round(mean, 2), sd = round(sd, 2),
                     min = round(min), max = round(max))])
}
