# 10_papertables.R — Tables 3 and 4 of the revised paper, plus the removals table.
# Output: Output/R/revised_tables_<filedate>.md/.docx
#
# These replace the log-linear tables that 03_tables.R still produces. 03 is kept because
# 04_validate.R needs it to reproduce the first submission; it is no longer the paper's table.
#
# Specification: Poisson pseudo-maximum likelihood on GROSS additions per process, neighbourhood
# land area as exposure, municipal fixed effects, standard errors clustered on municipality.
# New construction enters as two separate processes, infill and expansion, on the same footing as
# the others.

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))
source(file.path(.rd_script_dir, "05_revision.R"))
suppressPackageStartupMessages(library(fixest))

stars    <- function(p) fifelse(p < cfg$stars_main[1], "***", fifelse(p < cfg$stars_main[2], "**", fifelse(p < cfg$stars_main[3], "*", "")))
fmt_cell <- function(est, se, p) fifelse(is.na(est), "", sprintf("%.3f%s (%.3f)", est, stars(p), se))
p_two    <- function(z) 2 * pnorm(-abs(z))

# Column order for the revised tables: new construction is split and sits between the two other
# additive processes, so the table reads from most to least redevelopment-like.
cols <- c(all = "All additions", sn = "Replacement", nb_in = "New build: infill",
          nb_out = "New build: expansion", div = "Within-building", trf = "Transformation")

labs <- c(
  p_huurcorp  = "Social housing per neighbourhood (% of housing stock)",
  uai         = "Average urban attractivity index in neighbourhood (0-100)",
  p_beschermd = "Protected heritage areas in neighbourhood (% of land area)",
  p_onbebouwd = "Land potentially available for development (% of land area)",
  `construction_periodConstruction 1929 and earlier` = "Building year 1929 and earlier",
  `construction_periodConstruction 1930-1945` = "Building year 1930-1945",
  `construction_periodConstruction 1946-1960` = "Building year 1946-1960",
  `construction_periodConstruction 1961-1970` = "Building year 1961-1970",
  `construction_periodConstruction 1981-1990` = "Building year 1981-1990",
  `construction_periodConstruction 1991-2000` = "Building year 1991-2000",
  `construction_periodConstruction 2000-2012` = "Building year 2001-2012")

# Table 4 additionally reports the density main effects and the interaction terms. fixest writes
# the first interaction as "variable:level" and later ones as "level:variable", so both spellings
# are mapped to the same row.
labs4 <- c(
  labs[1:4],
  `urbanisationMedium density` = "Is medium density neighbourhood",
  `urbanisationLow density`    = "Is low density neighbourhood",
  `p_huurcorp:urbanisationMedium density` = "Social housing x medium density",
  `p_huurcorp:urbanisationLow density`    = "Social housing x low density",
  `urbanisationMedium density:uai`        = "UAI x medium density",
  `urbanisationLow density:uai`           = "UAI x low density",
  `urbanisationMedium density:p_onbebouwd` = "Available land x medium density",
  `urbanisationLow density:p_onbebouwd`    = "Available land x low density",
  labs[5:11])

rhs   <- "p_huurcorp + uai + p_beschermd + p_onbebouwd + construction_period"
rhs_x <- paste("p_huurcorp * urbanisation + uai * urbanisation + p_beschermd +",
               "p_onbebouwd * urbanisation + construction_period")

tidy <- function(m, s) {
  ct <- summary(m)$coeftable
  data.table(spec = s, term = rownames(ct), estimate = ct[, 1], se = ct[, 2], p = ct[, 4])
}
render <- function(fits, labels, headers = NULL) {
  dt <- rbindlist(Map(tidy, fits, names(fits)))
  dt[, cell_ := fmt_cell(estimate, se, p)]
  # Every estimated term must be either labelled or deliberately hidden, otherwise a coefficient
  # can vanish from the table without anyone noticing. This is what dropped the interaction terms
  # from an earlier version.
  unlabelled <- setdiff(unique(dt$term), names(labels))
  if (length(unlabelled)) rd_log("NOTE: not shown in this table: %s", paste(unlabelled, collapse = ", "))
  wide <- dcast(dt[term %chin% names(labels)], term ~ factor(spec, levels = names(fits)),
                value.var = "cell_", fill = "")
  wide <- wide[match(names(labels)[names(labels) %chin% wide$term], term)]
  wide[, term := labels[term]]
  rows <- wide[, paste0("| ", term, " | ", do.call(paste, c(.SD, sep = " | ")), " |"), .SDcols = names(fits)]
  blank <- paste(rep("", length(fits)), collapse = " | ")
  # Omitted categories carry no estimate; name them rather than leaving a silent gap.
  ins_ref <- function(rows, after_label, text) {
    i <- grep(after_label, rows, fixed = TRUE)
    if (!length(i)) return(rows)
    append(rows, paste0("| ", text, " | ", blank, " |"), after = i[1] - 1L)
  }
  rows <- ins_ref(rows, "Building year 1981-1990", "Building year 1971-1980 (reference)")
  rows <- ins_ref(rows, "Is medium density neighbourhood", "Is high density neighbourhood (reference)")
  hdr <- if (is.null(headers)) unname(cols)[match(names(fits), names(cols))] else headers
  c(paste0("| VARIABLES | ", paste(sprintf("(%d) %s", seq_along(fits), hdr), collapse = " | "), " |"),
    paste0("|", paste(rep("---", length(fits) + 1), collapse = "|"), "|"),
    rows,
    # With municipal fixed effects each municipality has its own intercept, so there is no single
    # constant to report. Say so, rather than leaving readers to wonder where it went.
    paste0("| Municipal fixed effects | ", paste(rep("Yes", length(fits)), collapse = " | "), " |"),
    paste0("| Observations | ", paste(vapply(fits, function(m) format(nobs(m), big.mark = ","), character(1)), collapse = " | "), " |"),
    paste0("| Municipalities | ", paste(vapply(fits, function(m) format(unname(m$fixef_sizes[1]), big.mark = ","), character(1)), collapse = " | "), " |"),
    paste0("| Pseudo-R2 | ", paste(vapply(fits, function(m) sprintf("%.3f", fitstat(m, "pr2")$pr2), character(1)), collapse = " | "), " |"))
}

# Average marginal effect of `var` within each density category, from the interaction model.
ame <- function(m, var, groups) {
  b <- coef(m); V <- vcov(m)
  rbindlist(lapply(groups, function(g) {
    a <- setNames(rep(0, length(b)), names(b)); a[var] <- 1
    if (g != cfg$urb_ref) {
      nm <- intersect(c(paste0(var, ":urbanisation", g), paste0("urbanisation", g, ":", var)), names(b))
      if (!length(nm)) return(NULL)
      a[nm[1]] <- 1
    }
    est <- sum(a * b); se <- sqrt(drop(t(a) %*% V %*% a))
    data.table(var = var, group = g, estimate = est, se = se, p = p_two(est / se))
  }))
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_10", ifnotfound = FALSE))) {
  wijk <- add_gross(add_province(readRDS(cfg$file_wijk_rds)))
  stopifnot(all(names(cols) %chin% names(cfg$gross)))

  ppml   <- function(y, f) fepois(as.formula(paste0("gross_", y, " ~ ", f, " | gm_code")),
                                  data = wijk, offset = ~log(land_area_ha), vcov = ~gm_code)
  fits3  <- lapply(setNames(names(cols), names(cols)), ppml, f = rhs)
  fits4  <- lapply(setNames(names(cols), names(cols)), ppml, f = rhs_x)
  groups <- unname(cfg$urb_levels)

  # Table 4 lower panel: marginal effects per density category.
  var_lab <- c(p_huurcorp = "Social housing", uai = "UAI", p_onbebouwd = "Available land")
  ames <- rbindlist(lapply(names(cols), function(nm)
    rbindlist(lapply(names(var_lab), ame, m = fits4[[nm]], groups = groups))[, spec := nm][]))
  ames[, cell_ := fmt_cell(estimate, se, p)]
  ames[, row := paste(var_lab[var], "x", tolower(group))]
  order_rows <- as.vector(t(outer(var_lab, tolower(groups), paste, sep = " x ")))
  aw <- dcast(ames, row ~ factor(spec, levels = names(cols)), value.var = "cell_", fill = "")
  aw <- aw[match(order_rows, row)]

  # Removals: the other side of the three processes that have one.
  rem <- list(sn = "count_sn_sloop", div = "count_onttrekking", trf = "count_transformatie_min")
  fits_r <- lapply(names(rem), function(k) {
    wijk[, y_ := get(rem[[k]])]
    fepois(as.formula(paste("y_ ~", rhs, "| gm_code")), data = wijk,
           offset = ~log(land_area_ha), vcov = ~gm_code)
  })
  names(fits_r) <- names(rem)
  cols_r <- c(sn = "Replacement: demolition", div = "Within-building: consolidation",
              trf = "Transformation: from resid.")

  ## -- Table 2: descriptives matching the estimated models -------------------
  # The published Table 2 described net change per hectare, which no longer matches what is
  # estimated. These rows are gross additions per hectare, one per column of Table 3, with the
  # removal side underneath so that both sides of Table 5 are documented too.
  desc_rows <- c(
    setNames(paste0("gross_", names(cols)), paste("Units added per ha,", tolower(unname(cols)))),
    "Units removed per ha, replacement (demolition)"      = "count_sn_sloop",
    "Units removed per ha, within-building (consolidation)" = "count_onttrekking",
    "Units removed per ha, transformation (from resid.)"  = "count_transformatie_min",
    "Social housing per neighbourhood (% of housing stock)" = "p_huurcorp",
    "Average urban attractivity index in neighbourhood (0-100)" = "uai",
    "Protected heritage areas in neighbourhood (% of land area)" = "p_beschermd",
    "Land potentially available for development (% of land area)" = "p_onbebouwd")
  per_ha <- grepl("per ha", names(desc_rows))
  desc <- rbindlist(Map(function(lab, v, ph) {
    x <- wijk[[v]]
    if (ph) x <- x / wijk$land_area_ha
    data.table(variable = lab, count = sum(!is.na(x)), mean = mean(x, na.rm = TRUE),
               sd = sd(x, na.rm = TRUE), min = min(x, na.rm = TRUE), max = max(x, na.rm = TRUE))
  }, names(desc_rows), desc_rows, per_ha))
  cp <- rbindlist(lapply(sort(levels(wijk$construction_period)), function(lv) {
    x <- as.numeric(wijk$construction_period == lv)
    x[is.na(wijk$construction_period)] <- NA_real_
    data.table(variable = sub("^Construction", "Building year", sub("2000-2012", "2001-2012", lv)),
               count = sum(!is.na(x)), mean = mean(x, na.rm = TRUE), sd = sd(x, na.rm = TRUE),
               min = 0, max = 1)
  }))
  md_desc <- function(d, dec = 2) c(
    "| VARIABLES | Count | Mean | SD | Min | Max |", "|---|---|---|---|---|---|",
    d[, sprintf(paste0("| %s | %s | %.", dec, "f | %.", dec, "f | %.2f | %.2f |"),
                variable, format(count, big.mark = ","), mean, sd, min, max)])

  md <- c(
    sprintf("# Revised Tables 2, 3, 4 and 5 (export %s)", cfg$filedate), "",
    "## Table 2. Descriptive statistics", "",
    "Dependent variables are gross additions per hectare of neighbourhood land area, matching what",
    "the models estimate. Removals are shown separately because they are modelled separately.", "",
    md_desc(desc), "", "Building year categories:", "", md_desc(cp), "",
    "## Table 3", "",
    "*Table 3: Poisson estimates of gross residential unit additions per neighbourhood, by",
    "development process, January 2012 to December 2025. Neighbourhood land area enters as an",
    "exposure term, so the coefficients describe additions per hectare and can be read as",
    "semi-elasticities. All models include municipal fixed effects, which absorb the intercept;",
    "robust standard errors clustered on municipality in parentheses. *** p<0.01, ** p<0.05,",
    "* p<0.1. Municipalities represented by a single neighbourhood are absorbed by their own fixed",
    "effect and drop out, as does any municipality in which the process concerned did not occur at",
    "all, which is why the number of municipalities differs slightly between columns.*", "",
    render(fits3, labs), "",
    "## Table 4", "",
    "*Table 4: The models of Table 3 with the social housing share, the urban attractivity index and",
    "the share of available land interacted with neighbourhood density category; high density is the",
    "reference category. The lower panel reports average marginal effects within each density",
    "category, computed from the interaction model. Specification, fixed effects and standard errors",
    "as in Table 3.*", "",
    render(fits4, labs4), "",
    "**Average marginal effects by density category**", "",
    paste0("| | ", paste(sprintf("(%d) %s", seq_along(cols), unname(cols)), collapse = " | "), " |"),
    paste0("|", paste(rep("---", length(cols) + 1), collapse = "|"), "|"),
    aw[, paste0("| ", row, " | ", do.call(paste, c(.SD, sep = " | ")), " |"), .SDcols = names(cols)], "",
    "## Table 5", "",
    "*Table 5: Poisson estimates of gross residential unit removals per neighbourhood, for the three",
    "development processes that have a removal side, January 2012 to December 2025. Specification,",
    "fixed effects and standard errors as in Table 3.*", "",
    render(fits_r, labs, headers = unname(cols_r)))

  f <- file.path(cfg$dir_work, sprintf("revised_tables_%s.md", cfg$filedate))
  writeLines(md, f)
  rd_log("Written: %s", f)
  rd_md_to_docx(f)
}
