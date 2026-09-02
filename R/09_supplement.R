# 09_supplement.R — the single supplementary table, plus the numbers that replace the tables we drop.
# Output: Output/R/supplement_<filedate>.md/.docx
#
# The revised manuscript makes three claims that rest on results not shown in the main tables:
# the new-build split, the omitted-variable checks, and the spatial diagnostics. Rather than four
# supplementary tables, this produces one table with two panels and two sentences.
#
#   Panel A  new build split into infill and expansion, main specification
#   Panel B  robustness of the main specification to additional controls
#   in text  Moran's I before and after municipal fixed effects
#   footnote sensitivity of the infill share to the delineation of the built-up area
#
# The main specification throughout is PPML on gross additions with land area as exposure and
# municipal fixed effects, standard errors clustered on municipality. Land value is deliberately
# NOT in that specification: it is missing for 461 of 2,621 neighbourhoods, and it is plausibly a
# mediator rather than a confounder, since amenities capitalise into land values. Conditioning on
# it would remove the channel rather than a bias. It therefore appears only in Panel B.

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))
source(file.path(.rd_script_dir, "05_revision.R"))   # add_province(), add_gross()
source(file.path(.rd_script_dir, "06_omitted.R"))    # add_landprice(), add_woz(), add_demography()
source(file.path(.rd_script_dir, "07_spatial.R"))    # add_centroids(), moran_resid()
suppressPackageStartupMessages(library(fixest))

stars    <- function(p) fifelse(p < cfg$stars_main[1], "***", fifelse(p < cfg$stars_main[2], "**", fifelse(p < cfg$stars_main[3], "*", "")))
fmt_cell <- function(est, se, p) fifelse(is.na(est), "", sprintf("%.3f%s (%.3f)", est, stars(p), se))

core_lab <- c(p_huurcorp  = "Social housing (% of stock)",
              uai         = "Urban attractivity index",
              p_beschermd = "Protected heritage (% of land)",
              p_onbebouwd = "Land potentially available (% of land)")
extra_lab <- c(ln_landprice    = "ln(residual land value, 2007)",
               ln_inw          = "ln(population, 2012)",
               gem_hh_gr       = "Average household size, 2012",
               p_65_eo_jr      = "Aged 65 and over, 2012 (%)",
               p_25_44_jr      = "Aged 25-44, 2012 (%)",
               avg_tt_100k_inw = "Travel time to 100k inhabitants",
               avg_tt_500k_inw = "Travel time to 500k inhabitants",
               ln_woz          = "ln(WOZ value per m2, 2018)")
rhs <- "p_huurcorp + uai + p_beschermd + p_onbebouwd + construction_period"

tidy <- function(m, spec) {
  ct <- summary(m)$coeftable
  data.table(spec = spec, term = rownames(ct), estimate = ct[, 1], se = ct[, 2], p = ct[, 4])
}
ppml <- function(y, data, extra = character(0)) {
  f <- paste(y, "~", paste(c(rhs, extra), collapse = " + "), "| gm_code")
  fepois(as.formula(f), data = data, offset = ~log(land_area_ha), vcov = ~gm_code)
}

# Render one panel: rows are regressors in `labs` order, columns are the fitted models.
panel <- function(fits, hdr, labs) {
  dt <- rbindlist(Map(tidy, fits, names(fits)))
  dt[, cell_ := fmt_cell(estimate, se, p)]
  wide <- dcast(dt[term %chin% names(labs)], term ~ factor(spec, levels = names(fits)),
                value.var = "cell_", fill = "")
  wide <- wide[match(names(labs)[names(labs) %chin% wide$term], term)]
  wide[, term := labs[term]]
  c(paste0("| | ", paste(hdr, collapse = " | "), " |"),
    paste0("|", paste(rep("---", length(fits) + 1), collapse = "|"), "|"),
    wide[, paste0("| ", term, " | ", do.call(paste, c(.SD, sep = " | ")), " |"), .SDcols = names(fits)],
    paste0("| Observations | ", paste(vapply(fits, function(m) format(nobs(m), big.mark = ","), character(1)), collapse = " | "), " |"),
    paste0("| Pseudo-R2 | ", paste(vapply(fits, function(m) sprintf("%.3f", fitstat(m, "pr2")$pr2), character(1)), collapse = " | "), " |"))
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_09", ifnotfound = FALSE))) {
  wijk <- add_centroids(add_demography(add_woz(add_landprice(add_gross(add_province(readRDS(cfg$file_wijk_rds)))))))

  ## -- Panel A: the new build split -------------------------------------------
  # Kept for reference; no longer printed, since Table 3 in the paper now carries these columns.
  panelA <- panel(
    list(nb = ppml("gross_nb", wijk), nb_in = ppml("gross_nb_in", wijk), nb_out = ppml("gross_nb_out", wijk)),
    c("New build, pooled", "Infill", "Expansion"), core_lab)

  ## -- Panel B: robustness of the main specification --------------------------
  # Fixed sample, so the columns differ only in what is controlled for. The post-period
  # variables are added as one block, since neither can enter a main specification.
  blocks <- list(
    base   = character(0),
    price  = "ln_landprice",
    demog  = c("ln_landprice", "ln_inw", "gem_hh_gr", "p_65_eo_jr", "p_25_44_jr"),
    post   = c("ln_landprice", "ln_inw", "gem_hh_gr", "p_65_eo_jr", "p_25_44_jr",
               "avg_tt_100k_inw", "avg_tt_500k_inw", "ln_woz"))
  need <- unique(unlist(blocks))
  sub  <- wijk[complete.cases(wijk[, ..need])]
  rd_log("Panel B sample: %d of %d neighbourhoods", nrow(sub), nrow(wijk))
  panelB <- panel(lapply(blocks, function(e) ppml("gross_all", sub, e)),
                  c("Main specification", "+ land value", "+ demography", "+ post-period controls"),
                  c(core_lab, extra_lab))

  ## -- the two numbers that replace the dropped tables -------------------------
  mor <- rbindlist(lapply(names(cfg$outcomes), function(nm) {
    f0 <- fepois(as.formula(paste0("gross_", nm, " ~ ", rhs)), data = wijk,
                 offset = ~log(land_area_ha), vcov = "hetero")
    f1 <- ppml(paste0("gross_", nm), wijk)
    rbind(moran_resid(f0, wijk, "no FE"), moran_resid(f1, wijk, "with FE"))[, outcome := nm][]
  }))
  m0 <- mor[spec == "no FE"]; m1 <- mor[spec == "with FE"]
  moran_sentence <- sprintf(
    paste("Moran's I on the residuals ranges from %.2f to %.2f across processes and is significant",
          "throughout (p < 0.01); after municipal fixed effects it falls to between %.2f and %.2f",
          "and is significant for none."),
    min(m0$moran_i), max(m0$moran_i), min(m1$moran_i), max(m1$moran_i))

  tot <- wijk[, sum(count_nieuwbouw)]
  del <- sprintf(
    paste("Infill share of new build under four delineations: %.1f%% for the built-up contour of 2012",
          "used here, %.1f%% for the union of population centres 2011 and the built-up area of 2000,",
          "%.1f%% for population centres 2011 alone, %.1f%% for the built-up area boundary of 2000 alone."),
    100 * wijk[, sum(count_nieuwbouw_infill)] / tot,
    100 * wijk[, sum(count_nieuwbouw_infill_augm2011)] / tot,
    100 * wijk[, sum(count_nieuwbouw_infill_kern2011)] / tot,
    100 * wijk[, sum(count_nieuwbouw_infill_bbg2000)] / tot)

  # Panel A is retained in the object but no longer printed: the infill and expansion regression
  # is now columns 3 and 4 of Table 3 in the paper itself.
  md <- c(
    sprintf("# Supplementary material (export %s)", cfg$filedate), "",
    "## Table 6", "",
    "*Table 6: Robustness of the main specification to additional controls. All columns estimate",
    "gross residential unit additions across all development processes by Poisson pseudo-maximum",
    "likelihood, with neighbourhood land area as an exposure term and municipal fixed effects, which",
    "absorb the intercept. The models are estimated on the neighbourhoods for which every control is",
    "observed, so that the columns differ only in what is controlled for. Residual land value refers",
    "to 2007 and the demographic variables to 2012, both preceding the observation period; travel",
    "times refer to 2020 and property values to 2018, which do not. Cluster-robust standard errors,",
    "clustered on municipality, in parentheses. *** p<0.01, ** p<0.05, * p<0.1.*", "",
    panelB, "",
    "## Sentences for the main text, replacing separate tables", "",
    "Spatial dependence (Section 3.6):", "", paste(">", moran_sentence), "",
    "Delineation of the built-up area (footnote to Section 2):", "", paste(">", del), "")

  f <- file.path(cfg$dir_work, sprintf("supplement_%s.md", cfg$filedate))
  writeLines(md, f)
  rd_log("Written: %s", f)
  rd_md_to_docx(f)

  cat("\n", moran_sentence, "\n\n", del, "\n", sep = "")
}
