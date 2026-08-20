# 08_nbsplit.R — the new-build split into infill and expansion (reviewer 1, comments 1 and 4).
# Output: Output/R/nbsplit_tables_<filedate>.md/.docx
#
# "New build" mixed genuine outward expansion with infill on formerly non-residential land.
# GeoDMS now splits it on whether the object lay inside the built-up area at the start of the
# observation period. Three delineations are exported so the choice can be defended:
#
#   bbg2012   built-up area contour 2012, Odijk et al. method   <- the one the paper uses
#   augm      population centres 2011 UNION built-up area 2000    (the earlier stopgap)
#   kern2011  CBS population centres 2011 only                    (right vintage, residential only)
#   bbg2000   built-up area contour 2000 only                     (covers non-residential, too early)
#
# The 2012 contour supersedes the union. It has the right vintage and covers both residential and
# non-residential built-up land, so it needs no combination of sources. The three earlier variants
# are retained as a sensitivity check: bbg2000 predates the study start by twelve years, so land
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
    bbg2012  = "count_nieuwbouw_infill",
    augm     = "count_nieuwbouw_infill_augm2011",
    kern2011 = "count_nieuwbouw_infill_kern2011",
    bbg2000  = "count_nieuwbouw_infill_bbg2000")
  variants <- variants[vapply(variants, function(v) v %chin% names(wijk), logical(1))]
  rbindlist(lapply(names(variants), function(v) {
    col <- variants[[v]]
    if (!col %in% names(wijk)) return(NULL)
    inf <- wijk[, sum(get(col))]
    data.table(delineation = v, infill = inf, expansion = tot - inf,
               infill_share = inf / tot)
  }))
}

# Share of ALL net additions realised inside the built-up contour, MEASURED rather than assumed.
#
# The neighbourhood export splits only new construction, so a figure derived from it has to treat
# replacement, within-building changes and transformation as inside the contour by construction.
# That is an assumption, and Eric rightly questioned it: replacement can and does occur outside the
# contour. The monthly export now carries every process counted inside the contour as well, so the
# share can be measured. Both are reported, because the difference between them is itself the
# answer to the question.
read_monthly <- function(f) {
  d <- fread(f)
  cols <- setdiff(names(d), "Label")
  as.list(colSums(d[, ..cols]))
}
net_of <- function(t) {
  (t$SN_Nieuwbouw - t$SN_Sloop) + t$Nieuwbouw +
    (t$toevoeging - t$Onttrekking) + (t$Transformatie_Plus - t$Transformatie_Min)
}
inside_measured <- function() {
  fa <- cfg$file_monthly(); fb <- cfg$file_monthly_inside()
  if (!file.exists(fa) || !file.exists(fb)) return(NULL)
  a <- read_monthly(fa); b <- read_monthly(fb)
  procs <- c(SN_Nieuwbouw = "Replacement: construction", SN_Sloop = "Replacement: demolition",
             Nieuwbouw = "New build", toevoeging = "Within-building: additions",
             Onttrekking = "Within-building: removals",
             Transformatie_Plus = "Transformation: to residential",
             Transformatie_Min = "Transformation: from residential")
  per <- rbindlist(lapply(names(procs), function(k) data.table(
    process = procs[[k]], total = a[[k]], inside = b[[k]], share = b[[k]] / a[[k]])))
  net_all <- net_of(a); net_in <- net_of(b)
  assumed <- net_all - (a$Nieuwbouw - b$Nieuwbouw)
  list(per = per, net_all = net_all, net_in = net_in, assumed = assumed)
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_08", ifnotfound = FALSE))) {
  wijk <- add_gross(add_province(readRDS(cfg$file_wijk_rds)))
  stopifnot("count_nieuwbouw_infill" %chin% names(wijk))

  sens <- sensitivity(wijk)
  rd_log("Infill share by delineation: %s",
         paste(sprintf("%s %.1f%%", sens$delineation, 100 * sens$infill_share), collapse = ", "))

  ins <- inside_measured()
  if (is.null(ins)) stop("Monthly series missing; cannot measure the inside share.")

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
    "| Delineation | Infill | Expansion | Infill share of new build |",
    "|---|---|---|---|",
    sapply(seq_len(nrow(sens)), function(i) sprintf("| %s | %s | %s | %.1f%% |",
      c(bbg2012  = "Built-up area contour 2012 (used in the paper)",
        augm     = "Population centres 2011 + built-up area 2000",
        kern2011 = "Population centres 2011 only",
        bbg2000  = "Built-up area 2000 only")[sens$delineation[i]],
      format(sens$infill[i], big.mark = ","), format(sens$expansion[i], big.mark = ","),
      100 * sens$infill_share[i])), "",
    "## Share of each process realised inside the 2012 contour", "",
    "| Process | Total | Inside the contour | Share |", "|---|---|---|---|",
    ins$per[, sprintf("| %s | %s | %s | %.1f%% |", process, format(total, big.mark = ","),
                      format(inside, big.mark = ","), 100 * share)], "",
    sprintf("Measured across all processes, %s of %s net additions fall inside the contour, or %.1f%%.",
            format(ins$net_in, big.mark = ","), format(ins$net_all, big.mark = ","),
            100 * ins$net_in / ins$net_all),
    sprintf(paste("Treating every process other than new build as inside the contour, as an analysis",
                  "that splits only new construction must, would give %.1f%%. The difference of %s",
                  "dwellings is redevelopment that takes place outside the built-up contour."),
            100 * ins$assumed / ins$net_all, format(ins$assumed - ins$net_in, big.mark = ",")), "",
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
  cat("
---- measured share inside the contour ----
"); print(ins$per)
  cat(sprintf("net inside %s of %s = %.1f%% (assumption-based: %.1f%%)
",
      format(ins$net_in, big.mark = ","), format(ins$net_all, big.mark = ","),
      100 * ins$net_in / ins$net_all, 100 * ins$assumed / ins$net_all))
  cat("\n---- pseudo-R2 ----\n"); print(round(pr2, 3))
}
