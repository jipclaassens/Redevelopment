# 06_omitted.R — omitted-variable robustness (referee 2, point 3).
# Output: Output/R/omitted_tables_<filedate>.md/.docx
#
# Referee 2 objects that house prices and other determinants are missing, and that dismissing
# their omission is unconvincing. This adds them one block at a time:
#
#   (0) full sample   PPML + municipal fixed effects, all neighbourhoods
#   (1) base          the same, on the sample where every control is observed
#   (2) + land value  residual land value per m2, 2007 (per PC4, averaged) — PRE-period
#   (3) + demography  population, household size, age structure, 2012        — PRE-period
#   (4) + access      travel time to 100k and 500k inhabitants, 2020         — post-period
#   (5) + WOZ         property value per m2, residential land use, 2018      — post-period
#
# (1) minus (0) is the sample effect; everything after that is the effect of controlling.
# Columns 4 and 5 use variables dated after the start of the observation period, so they are
# robustness checks and must not be presented as the main specification.

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))
source(file.path(.rd_script_dir, "05_revision.R"))   # add_province(), add_gross(), cfg$gross
suppressPackageStartupMessages(library(fixest))

# Land price: from the neighbourhood x year panel, time-invariant, one value per
# neighbourhood. Highly skewed (median 94, max 2,908 EUR/m2), hence logs.
add_landprice <- function(wijk) {
  lp <- unique(fread(cfg$file_perwijk_jaar, select = c("WK_CODE", "landprice")))
  setnames(lp, c("wk_code", "landprice"))
  stopifnot(!anyDuplicated(lp$wk_code))
  wijk <- merge(wijk, lp, by = "wk_code", all.x = TRUE)
  wijk[, ln_landprice := stata_log(landprice)]
  rd_log("Land price observed for %d of %d neighbourhoods", wijk[!is.na(ln_landprice), .N], nrow(wijk))
  wijk[]
}

# WOZ value per m2 for residential land use (bg2015_groep == 1). `r2017` is the numeric
# neighbourhood code, so pad it back to the "WK" + 6 digits form.
add_woz <- function(wijk) {
  if (!file.exists(cfg$file_woz)) { rd_log("WOZ file not reachable; skipping"); return(wijk[]) }
  w <- fread(cfg$file_woz)[bg2015_groep == 1L, .(wk_code = sprintf("WK%06d", r2017), woz = wozm2_mean)]
  w <- unique(w, by = "wk_code")
  wijk <- merge(wijk, w, by = "wk_code", all.x = TRUE)
  wijk[, ln_woz := stata_log(woz)]
  rd_log("WOZ observed for %d of %d neighbourhoods", wijk[!is.na(ln_woz), .N], nrow(wijk))
  wijk[]
}

# Population enters in logs; the 2012 export has neighbourhoods with zero inhabitants
# (industrial estates, port areas), which stata_log turns into NA.
add_demography <- function(wijk) {
  wijk[, ln_inw := stata_log(aant_inw)]
  wijk[]
}

stars    <- function(p) fifelse(p < cfg$stars_main[1], "***", fifelse(p < cfg$stars_main[2], "**", fifelse(p < cfg$stars_main[3], "*", "")))
fmt_cell <- function(est, se, p) fifelse(is.na(est), "", sprintf("%.3f%s (%.3f)", est, stars(p), se))

terms_lab <- c(p_huurcorp      = "Social housing (% of stock)",
               uai             = "Urban attractivity index",
               p_beschermd     = "Protected heritage (% of land)",
               p_onbebouwd     = "Land potentially available (% of land)",
               ln_landprice    = "ln(residual land value 2007)",
               ln_inw          = "ln(population 2012)",
               gem_hh_gr       = "Average household size 2012",
               p_65_eo_jr      = "Aged 65 and over 2012 (%)",
               p_25_44_jr      = "Aged 25-44 2012 (%)",
               avg_tt_100k_inw = "Travel time to 100k inhabitants",
               avg_tt_500k_inw = "Travel time to 500k inhabitants",
               ln_woz          = "ln(WOZ value per m2, 2018)")

blocks <- list(
  base   = character(0),
  price  = "ln_landprice",
  demog  = c("ln_landprice", "ln_inw", "gem_hh_gr", "p_65_eo_jr", "p_25_44_jr"),
  access = c("ln_landprice", "ln_inw", "gem_hh_gr", "p_65_eo_jr", "p_25_44_jr",
             "avg_tt_100k_inw", "avg_tt_500k_inw"),
  woz    = c("ln_landprice", "ln_inw", "gem_hh_gr", "p_65_eo_jr", "p_25_44_jr",
             "avg_tt_100k_inw", "avg_tt_500k_inw", "ln_woz"))

rhs_core <- "p_huurcorp + uai + p_beschermd + p_onbebouwd + construction_period"

estimate_omitted <- function(wijk) {
  # Fixed estimation sample: complete cases on every control, so the columns differ only in
  # what is controlled for and never in who is in the regression.
  need <- unique(unlist(blocks))
  sub <- wijk[complete.cases(wijk[, ..need])]
  rd_log("Common sample with all controls observed: %d of %d neighbourhoods", nrow(sub), nrow(wijk))

  out <- list()
  for (nm in names(cfg$outcomes)) {
    y <- paste0("gross_", nm)
    fits <- c(
      list(full = fepois(as.formula(paste(y, "~", rhs_core, "| gm_code")), data = wijk,
                         offset = ~log(land_area_ha), vcov = ~gm_code)),
      lapply(blocks, function(extra) {
        f <- paste(y, "~", paste(c(rhs_core, extra), collapse = " + "), "| gm_code")
        fepois(as.formula(f), data = sub, offset = ~log(land_area_ha), vcov = ~gm_code)
      }))
    out[[nm]] <- list(
      ct = rbindlist(Map(function(m, s) {
        c2 <- summary(m)$coeftable
        data.table(spec = s, term = rownames(c2), estimate = c2[, 1], se = c2[, 2], p = c2[, 4])
      }, fits, names(fits))),
      n = vapply(fits, nobs, integer(1)))
    rd_log("%-16s full %d, common sample %d", cfg$outcomes[[nm]]$label, nobs(fits$full), nobs(fits$base))
  }
  list(models = out, sample = sub)
}

spec_table <- function(res, nm) {
  specs <- c("full", "base", "price", "demog", "access", "woz")
  hdr   <- c("all neighbourhoods", "common sample", "+ land value", "+ demography",
             "+ accessibility", "+ WOZ")
  dt <- res$models[[nm]]$ct[term %chin% names(terms_lab)]
  dt[, cell_ := fmt_cell(estimate, se, p)]
  wide <- dcast(dt, term ~ factor(spec, levels = specs), value.var = "cell_", fill = "")
  wide <- wide[match(names(terms_lab)[names(terms_lab) %chin% wide$term], term)]
  wide[, term := terms_lab[term]]
  c(sprintf("**%s**", cfg$outcomes[[nm]]$label), "",
    paste0("| | ", paste(hdr, collapse = " | "), " |"),
    paste0("|", paste(rep("---", length(specs) + 1), collapse = "|"), "|"),
    wide[, paste0("| ", term, " | ", do.call(paste, c(.SD, sep = " | ")), " |"), .SDcols = specs],
    paste0("| Observations | ", paste(format(res$models[[nm]]$n[specs], big.mark = ","), collapse = " | "), " |"), "")
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_06", ifnotfound = FALSE))) {
  wijk <- add_demography(add_woz(add_landprice(add_gross(add_province(readRDS(cfg$file_wijk_rds))))))
  res  <- estimate_omitted(wijk)
  saveRDS(res$models, file.path(cfg$dir_work, sprintf("omitted_%s.rds", cfg$filedate)))

  # What do the new controls proxy for? Correlations with the four core regressors.
  core <- c(social = "p_huurcorp", uai = "uai", heritage = "p_beschermd", land = "p_onbebouwd")
  cors <- rbindlist(lapply(unique(unlist(blocks)), function(v) {
    r <- vapply(core, function(k) cor(res$sample[[v]], res$sample[[k]], use = "complete.obs"), numeric(1))
    data.table(variable = unname(terms_lab[v]), social = r[["social"]], uai = r[["uai"]],
               heritage = r[["heritage"]], land = r[["land"]])
  }))

  md <- c(sprintf("# Omitted variables (export %s)", cfg$filedate), "",
    "Referee 2, point 3. Controls are added block by block on a fixed estimation sample, so",
    "the columns differ only in what is controlled for. Column 1 is the same specification on",
    "all neighbourhoods, which shows that restricting to the common sample changes little.", "",
    "Land value (2007) and the demographic variables (2012) predate the observation period and",
    "can enter the main specification. Travel times (2020) and WOZ values (2018) do not: they",
    "are reported as robustness checks only.", "",
    unlist(lapply(names(cfg$outcomes), function(nm) spec_table(res, nm))),
    "## What the new controls proxy for", "",
    "Correlation with the four core regressors, on the estimation sample.", "",
    "| | Social housing | UAI | Heritage | Available land |", "|---|---|---|---|---|",
    cors[, sprintf("| %s | %.2f | %.2f | %.2f | %.2f |", variable, social, uai, heritage, land)], "",
    "Standard errors clustered on municipality. *** p<0.01, ** p<0.05, * p<0.1.")

  f <- file.path(cfg$dir_work, sprintf("omitted_tables_%s.md", cfg$filedate))
  writeLines(md, f)
  rd_log("Written: %s", f)
  rd_md_to_docx(f)
  cat("\n---- correlations with the core regressors ----\n"); print(cors)
}
