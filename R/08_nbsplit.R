# 08_nbsplit.R — the new-build split into infill and expansion (reviewer 1, comments 1 and 4).
# Output: Output/R/nbsplit_tables_<filedate>.md/.docx
#
# "New build" mixed genuine outward expansion with infill on formerly non-residential land.
# GeoDMS now splits it on whether the object lay inside the built-up area at the start of the
# observation period. Three delineations are exported so the choice can be defended:
#
#   augm      population centres 2011 UNION built-up area 2000   <- the one the paper uses
#   kern2011  CBS population centres 2011 only                    (right vintage, residential only)
#   bbg2000   built-up area contour 2000 only                     (covers non-residential, too early)
#
# Neither single delineation works: bbg2000 predates the study start by twelve years, so land
# urbanised during the Vinex period counts as expansion; kern2011 has the right vintage but is
# defined on population and excludes business parks and port areas, where much infill happens.

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))
source(file.path(.rd_script_dir, "05_revision.R"))   # add_province(), add_gross()
suppressPackageStartupMessages(library(fixest))

stars    <- function(p) fifelse(p < cfg$stars_main[1], "***", fifelse(p < cfg$stars_main[2], "**", fifelse(p < cfg$stars_main[3], "*", "")))
fmt_cell <- function(est, se, p) fifelse(is.na(est), "", sprintf("%.3f%s (%.3f)", est, stars(p), se))

main_terms <- c(p_huurcorp  = "Social housing (% of stock)",
                uai         = "Urban attractivity index",
                p_beschermd = "Protected heritage (% of land)",
                p_onbebouwd = "Land potentially available (% of land)")
rhs <- "p_huurcorp + uai + p_beschermd + p_onbebouwd + construction_period"

# How much does the infill share depend on which contour is used?
sensitivity <- function(wijk) {
  tot <- wijk[, sum(count_nieuwbouw)]
  variants <- list(
    augm     = "count_nieuwbouw_infill",
    kern2011 = "count_nieuwbouw_infill_kern2011",
    bbg2000  = "count_nieuwbouw_infill_bbg2000")
  rbindlist(lapply(names(variants), function(v) {
    col <- variants[[v]]
    if (!col %in% names(wijk)) return(NULL)
    inf <- wijk[, sum(get(col))]
    data.table(delineation = v, infill = inf, expansion = tot - inf,
               infill_share = inf / tot)
  }))
}

# Share of ALL net additions realised inside the existing urban fabric, under each contour.
# Replacement, within-building and transformation are inside by construction; of new build,
# only the infill part counts.
fabric_share <- function(wijk, infill_col) {
  s <- function(v) wijk[, sum(get(v))]
  repl <- s("count_sn_nieuwbouw") - s("count_sn_sloop")
  wib  <- s("count_toevoeging")   - s("count_onttrekking")
  trf  <- s("count_transformatie_plus") - s("count_transformatie_min")
  nb   <- s("count_nieuwbouw")
  inf  <- s(infill_col)
  total <- repl + wib + trf + nb
  list(total = total, inside = repl + wib + trf + inf,
       share = (repl + wib + trf + inf) / total)
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_08", ifnotfound = FALSE))) {
  wijk <- add_gross(add_province(readRDS(cfg$file_wijk_rds)))
  stopifnot("count_nieuwbouw_infill" %chin% names(wijk))

  sens <- sensitivity(wijk)
  rd_log("Infill share by delineation: %s",
         paste(sprintf("%s %.1f%%", sens$delineation, 100 * sens$infill_share), collapse = ", "))

  fab <- rbindlist(lapply(
    c(augm = "count_nieuwbouw_infill", kern2011 = "count_nieuwbouw_infill_kern2011",
      bbg2000 = "count_nieuwbouw_infill_bbg2000"),
    function(col) as.data.table(fabric_share(wijk, col))), idcol = "delineation")

  # Does splitting improve the fit, as reviewer 1 suggests? Compare the pooled new-build model
  # with the two separate ones, on the same specification.
  fits <- list(
    nb     = fepois(as.formula(paste("gross_nb ~", rhs, "| gm_code")), data = wijk,
                    offset = ~log(land_area_ha), vcov = ~gm_code),
    nb_in  = fepois(as.formula(paste("gross_nb_in ~", rhs, "| gm_code")), data = wijk,
                    offset = ~log(land_area_ha), vcov = ~gm_code),
    nb_out = fepois(as.formula(paste("gross_nb_out ~", rhs, "| gm_code")), data = wijk,
                    offset = ~log(land_area_ha), vcov = ~gm_code))
  ct <- rbindlist(Map(function(m, s) {
    c2 <- summary(m)$coeftable
    data.table(spec = s, term = rownames(c2), estimate = c2[, 1], se = c2[, 2], p = c2[, 4])
  }, fits, names(fits)))
  ct[, cell_ := fmt_cell(estimate, se, p)]
  wide <- dcast(ct[term %chin% names(main_terms)], term ~ factor(spec, levels = names(fits)),
                value.var = "cell_", fill = "")
  wide <- wide[match(names(main_terms)[names(main_terms) %chin% wide$term], term)]
  wide[, term := main_terms[term]]
  pr2 <- vapply(fits, function(m) fitstat(m, "pr2")$pr2, numeric(1))
  ns  <- vapply(fits, nobs, integer(1))

  md <- c(sprintf("# New build split into infill and expansion (export %s)", cfg$filedate), "",
    "Reviewer 1, comments 1 and 4. The split is on whether the object lay inside the built-up",
    "area at the start of the observation period.", "",
    "## Sensitivity to the delineation", "",
    "| Delineation | Infill | Expansion | Infill share of new build | Share of ALL net additions inside the existing fabric |",
    "|---|---|---|---|---|",
    sapply(seq_len(nrow(sens)), function(i) sprintf("| %s | %s | %s | %.1f%% | %.1f%% |",
      c(augm = "Population centres 2011 + built-up area 2000 (used in the paper)",
        kern2011 = "Population centres 2011 only",
        bbg2000  = "Built-up area 2000 only")[sens$delineation[i]],
      format(sens$infill[i], big.mark = ","), format(sens$expansion[i], big.mark = ","),
      100 * sens$infill_share[i],
      100 * fab$share[match(sens$delineation[i], fab$delineation)])), "",
    sprintf("Total net additions: %s.", format(fab$total[1], big.mark = ",")),
    "Without the split, the share realised inside the existing fabric was reported as the sum of",
    "replacement, within-building changes and transformation alone.", "",
    "## Does the split improve the fit? (PPML, municipal fixed effects)", "",
    "| | New build (pooled) | Infill | Expansion |", "|---|---|---|---|",
    wide[, paste0("| ", term, " | ", do.call(paste, c(.SD, sep = " | ")), " |"), .SDcols = names(fits)],
    paste0("| Observations | ", paste(format(ns, big.mark = ","), collapse = " | "), " |"),
    paste0("| Pseudo-R2 | ", paste(sprintf("%.3f", pr2), collapse = " | "), " |"), "",
    "Standard errors clustered on municipality. *** p<0.01, ** p<0.05, * p<0.1.")

  f <- file.path(cfg$dir_work, sprintf("nbsplit_tables_%s.md", cfg$filedate))
  writeLines(md, f)
  rd_log("Written: %s", f)
  rd_md_to_docx(f)

  cat("\n---- sensitivity ----\n"); print(sens)
  cat("\n---- share inside the existing fabric ----\n"); print(fab)
  cat("\n---- pseudo-R2 ----\n"); print(round(pr2, 3))
}
