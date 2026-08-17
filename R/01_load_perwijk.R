# 01_load_perwijk.R — read the GeoDMS neighbourhood export and build the analysis variables.
# Line-by-line port of the DATA PREPARATION block of stata/Redevelopment_regressie.do
# (lines 9-210). Output: Output/R/perwijk_<filedate>.rds
#
# Every derived variable carries the do-file line number it comes from, so the two can be
# diffed by hand. Deliberate faithfulness to Stata quirks is marked with STATA:.

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))

# Read the export and lower-case the column names, which is what Stata's
# `import delimited` does. Everything downstream then refers to lower-case names.
load_perwijk <- function(file = cfg$file_perwijk()) {
  stopifnot(file.exists(file))
  dt <- fread(file)
  setnames(dt, tolower(names(dt)))
  rd_log("Read %s: %d neighbourhoods, %d columns", basename(file), nrow(dt), ncol(dt))

  # -- resolve the abbreviated names the do-file uses (do-file lines 20-27) ----------
  # STATA: `rename pandfootprint pandfootprint` and `rename total_area total_area` look
  # like no-ops but actually rename pandfootprint_2012 -> pandfootprint via abbreviation.
  setnames(dt, pick_col(dt, "modus_buildingyear_2012"), "bouwjaar")
  setnames(dt, pick_col(dt, "mean_uai"),                "uai")
  setnames(dt, pick_col(dt, "pandfootprint"),           "pandfootprint")
  setnames(dt, pick_col(dt, "wegspoor"),                "wegspoor")
  setnames(dt, pick_col(dt, "water_"),                  "water_area")
  setnames(dt, pick_col(dt, "opp_besch"),               "opp_besch")
  setnames(dt, pick_col(dt, "count_transformatie_p"),   "count_transformatie_plus")
  setnames(dt, pick_col(dt, "count_transformatie_m"),   "count_transformatie_min")

  # -- construction-period categories (do-file lines 41-50) --------------------------
  # STATA: the last label reads "Construction 2000-2012" while the condition is >= 2001;
  # Table 3 prints "2001-2012". Kept as-is for the replication, relabelled in 03_tables.R.
  dt[, construction_period := fcase(
    is.na(bouwjaar),                 NA_character_,
    bouwjaar <= 1929,                "Construction 1929 and earlier",
    bouwjaar <= 1945,                "Construction 1930-1945",
    bouwjaar <= 1960,                "Construction 1946-1960",
    bouwjaar <= 1970,                "Construction 1961-1970",
    bouwjaar <= 1980,                "Construction 1971-1980",
    bouwjaar <= 1990,                "Construction 1981-1990",
    bouwjaar <= 2000,                "Construction 1991-2000",
    default =                        "Construction 2000-2012")]
  # `encode` orders levels alphabetically; relevel to the Stata base category (ib5.).
  dt[, construction_period := relevel(factor(construction_period), ref = cfg$cp_ref)]

  # -- areas (do-file lines 83-84) ---------------------------------------------------
  # GeoDMS writes null, not 0, when a neighbourhood contains no road/railway or no surface
  # water (the sum runs over an empty selection). A null here silently removes the
  # neighbourhood from every model via land_area and p_onbebouwd, which is what happened in
  # the 20250603 export. Semantically the value is zero, so patch it and say so out loud.
  for (v in c("wegspoor", "water_area")) {
    n_na <- dt[is.na(get(v)), .N]
    if (n_na > 0L) {
      warning(sprintf("%s is null for %d neighbourhoods; treated as 0. Fix with MakeDefined(..., 0) in the GeoDMS export.", v, n_na), call. = FALSE)
      rd_log("WARNING: %s null for %d neighbourhoods -> set to 0", v, n_na)
      dt[is.na(get(v)), (v) := 0]
    }
  }
  # Areas are exported in km2; 1 km2 = 100 ha.
  dt[, land_area    := total_area - water_area]
  dt[, land_area_ha := land_area * 100]

  # -- new build split, when the export carries it (reviewer 1, comment 1) ------------
  # Extending cfg$outcomes here means 02/03/05/06/07 gain two columns automatically. The
  # split is checked against the unsplit total, because a mismatch would silently mean the
  # BBG-2000 overlay classified some objects into neither category.
  if (all(c("count_nieuwbouw_infill", "count_nieuwbouw_expansion") %in% names(dt))) {
    gap <- dt[, sum(count_nieuwbouw_infill + count_nieuwbouw_expansion) - sum(count_nieuwbouw)]
    if (gap != 0L) stop(sprintf("New build split does not add up: infill + expansion - total = %d", gap))
    cfg$outcomes <<- c(cfg$outcomes, cfg$outcomes_nb_split)
    rd_log("New build split present: %s infill, %s expansion (sums to count_nieuwbouw)",
           format(dt[, sum(count_nieuwbouw_infill)], big.mark = ","),
           format(dt[, sum(count_nieuwbouw_expansion)], big.mark = ","))
  }

  # -- dependent variables (do-file lines 80, 90-95) ---------------------------------
  # Counts first (needed for the descriptives and for the Poisson revision), logs after.
  for (nm in names(cfg$outcomes)) {
    dt[, (paste0("cnt_", nm))    := eval(cfg$outcomes[[nm]]$expr)]
    dt[, (paste0("cnt_ha_", nm)) := get(paste0("cnt_", nm)) / land_area_ha]
    # STATA: ln() of zero or a negative net change is missing -> the observation is
    # dropped from that model. stata_log() reproduces this; see 04_validate.R.
    dt[, (paste0("ln_", nm))     := stata_log(get(paste0("cnt_ha_", nm)))]
  }

  # -- explanatory variables (do-file lines 118-123) ----------------------------------
  dt[, p_beschermd := opp_besch / land_area * 100]
  dt[p_beschermd > 100, p_beschermd := 100]                       # do-file line 119
  dt[, uai := uai * 100]                                          # do-file line 120
  dt[, p_onbebouwd := ((land_area - wegspoor - pandfootprint) / land_area) * 100]

  # -- density category ---------------------------------------------------------------
  dt[, urbanisation := relevel(factor(cfg$urb_levels[as.character(urbanisationk_rel)],
                                      levels = unname(cfg$urb_levels)), ref = cfg$urb_ref)]

  # -- municipality, for the fixed-effects specification the revision needs ------------
  # CBS neighbourhood codes are "WK" + 4-digit municipality code + 2-digit neighbourhood.
  # STATA: the do-file drops wk_code (line 208), which is why no municipal identifier was
  # available for the first submission. We keep it.
  dt[, gm_code := paste0("GM", substr(wk_code, 3, 6))]

  # -- province, from the 20260812 export onwards -------------------------------------
  # Older vintages have no regional identifier; 05_revision.R then falls back to joining
  # provincie_rel from the neighbourhood x year panel.
  if ("prv_name" %in% names(dt)) {
    dt[, provincie := factor(gsub("_", "-", prv_name))]
    dt[, randstad  := factor(fifelse(as.character(provincie) %chin% cfg$randstad, "Randstad", "Rest"),
                             levels = c("Rest", "Randstad"))]
    rd_log("Province from the export: %d provinces, %d neighbourhoods in the Randstad",
           uniqueN(dt$provincie), dt[randstad == "Randstad", .N])
  }

  # -- neighbourhood centroid, from the 20260812_updates export onwards -----------------
  # GeoDMS writes an rdc point to CSV as "x_y" (metres, EPSG:28992). Split it into two
  # numeric columns; 07_spatial.R uses these and only falls back to the CBS boundary file
  # when the column is absent.
  if ("wk_centroide" %in% names(dt)) {
    dt[, c("x_rd", "y_rd") := tstrsplit(wk_centroide, "_", fixed = TRUE, type.convert = TRUE)]
    rd_log("Centroids from the export: %d of %d parsed", dt[!is.na(x_rd) & !is.na(y_rd), .N], nrow(dt))
  }

  # -- extra covariates requested by the referees --------------------------------------
  present <- intersect(names(cfg$extra_vars), names(dt))
  if (length(present)) rd_log("Extra covariates present: %s", paste(present, collapse = ", "))

  dt[]
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_01", ifnotfound = FALSE))) {
  wijk <- load_perwijk()
  saveRDS(wijk, cfg$file_wijk_rds)
  rd_log("Written: %s", cfg$file_wijk_rds)

  rd_log("Neighbourhoods: %d in %d municipalities", nrow(wijk), uniqueN(wijk$gm_code))
  rd_log("Missing covariates: p_huurcorp %d, bouwjaar %d",
         wijk[is.na(p_huurcorp), .N], wijk[is.na(bouwjaar), .N])

  # How many observations does each log outcome lose, and why? This is the diagnostic
  # behind the sample-selection point in the revision plan (section 1.1).
  diag <- rbindlist(lapply(names(cfg$outcomes), function(nm) {
    y <- wijk[[paste0("cnt_", nm)]]
    data.table(outcome = cfg$outcomes[[nm]]$label,
               n_total = length(y), n_zero = sum(y == 0, na.rm = TRUE),
               n_negative = sum(y < 0, na.rm = TRUE),
               n_logged = sum(!is.na(wijk[[paste0("ln_", nm)]])))
  }))
  rd_log("Observations lost to the log transformation:")
  print(diag)
}
