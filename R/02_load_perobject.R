# 02_load_perobject.R — read PerObject_Export (GeoDMS mmd), add labels and
# reconstruct the hedonic incumbent value (issue #16, step 0 preparation).
#
# Price reconstruction (agreement #13/#20): GeoDMS exports raw components; here
# we build price = exp(constant + sum(coef * characteristic)) per WP4 using the
# coefficients CSV (PriceCoefficients_WP4_<date>.csv, spec 'redev').
# Object-specific: lnsize (obj_floor_area_res_m2), bouwperiode (obj_building_year).
# Region proxies (incumbent has no NVM characteristics): reg_<wp4>_{lotsize,nrooms,
# d_maintgood,d_highrise}. d_hoogte_onbekend: no regional average available -> 0.
# Price level: trans_year_<cfg$price_level_year>. Location: lntt_500k_2024, lntt_ovknoop, uai_2012.
# Non-residential incumbent (Transformatie_Min, SN_Sloop_nw, Onveranderd_NW): obj_nonres_eur_m2_2023 x
# cleaned floor area (GeoDMS NietWoonWaardering: hall or other, calibrated on the local dwelling WOZ).

# Determine the folder this script lives in: when run via Rscript, commandArgs()
# contains --file=<path>; when sourced interactively we fall back to getwd().
# Then load the shared settings (cfg) and the mmd reader used below.
if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))
source(file.path(.rd_script_dir, "01_read_mmd.R"))

## ---------------------------------------------------------------------------
## Coefficients
## ---------------------------------------------------------------------------
# Read the hedonic coefficient CSV (one row per model term, one column per WP4 housing
# type). stopifnot() aborts immediately if expected columns are missing, so a wrong or
# outdated file fails loudly here instead of yielding silent zero coefficients later.
read_coefficients <- function(pad = cfg$file_coef) {
  co <- fread(pad, sep = ";", na.strings = "")
  stopifnot(all(c("coef_name", cfg$wp4_names) %in% names(co)))
  # Guards against silent errors (25-09): a duplicated term would be recycled like the old
  # building-period bug, and a term that the price formula below does not use is dropped from
  # every price without a warning (that is how the green and water terms went missing).
  stopifnot("duplicated term in the coefficient file" = !anyDuplicated(co$coef_name))
  unused <- setdiff(co$coef_name[!co$coef_name %like% "^bouwperiode_|^trans_year_"], cfg$price_terms)
  if (length(unused)) stop("Coefficient file has terms the price formula does not use: ", paste(unused, collapse = ", "))
  co
}

# For one model term, return a coefficient PER OBJECT: each object gets the value from
# the column of its own WP4 type (match() finds that column). An unknown term or an
# empty cell yields 0, so that term simply drops out of the price for those objects.
coef_for <- function(co, term, wp4) {
  # wp4: character vector of cfg$wp4_names values; unknown term or missing coef -> 0
  row <- co[coef_name == term]
  if (!nrow(row)) return(rep(0, length(wp4)))
  out <- as.numeric(row[1, cfg$wp4_names, with = FALSE])[match(wp4, cfg$wp4_names)]
  fifelse(is.na(out), 0, out)
}

## ---------------------------------------------------------------------------
## Read + labels
## ---------------------------------------------------------------------------
load_perobject <- function(dir_mmd = cfg$dir_mmd) {
  rd_log("Reading mmd: %s", dir_mmd)
  x <- read_mmd(dir_mmd)
  # setnames() lowercases all column names in place (data.table edits x by reference)
  setnames(x, tolower(names(x)))

  # classification ids -> labels (255 = null)
  # GeoDMS exports 0-based category codes, R vectors are 1-based, hence the +1L when
  # indexing the label vectors from cfg. := adds the label columns by reference; codes
  # outside the known range (the 255 null sentinel) become NA. See README, data.table primer.
  x[, redev_type_lbl   := fifelse(redev_type   < length(cfg$redev_types), cfg$redev_types[redev_type + 1L], NA_character_)]
  x[, obj_housetype_lbl := fifelse(obj_housetype < length(cfg$wp4_names),  cfg$wp4_names[obj_housetype + 1L], NA_character_)]

  # null sentinels -> NA
  # GeoDMS writes "no data" as extreme sentinel numbers (65535, -2^31+1). The pattern
  # x[condition, col := value] overwrites only the rows matching the condition, in place.
  if ("obj_building_year" %in% names(x))    x[obj_building_year >= 65535L, obj_building_year := NA_integer_]
  if ("obj_floor_area_res_m2" %in% names(x)) x[obj_floor_area_res_m2 <= -2147483647L, obj_floor_area_res_m2 := NA_integer_]
  if ("redev_yearmonth" %in% names(x))       x[redev_yearmonth <= -2147483647L, redev_yearmonth := NA_integer_]
  # OAD is uint32: objects whose point falls outside every CBS buurt polygon get the
  # uint32 null (2^32-1) instead of a density. Left as-is these pass the urban scope
  # filter (oad >= cfg$oad_min) as if they were the densest places in the country
  # (found 30-07: 251 sites, all in the export's OAD column). NA is the honest value;
  # 06/07/09 already drop sites with !is.na(oad).
  if ("oad" %in% names(x)) x[oad >= 4294967295, oad := NA_integer_]
  # NietWoonWaardering columns (export from 25-09): uint32 and int32 nulls, uint8 codes -> labels
  if ("obj_pand_n_woningen" %in% names(x))     x[obj_pand_n_woningen >= 4294967295, obj_pand_n_woningen := NA_real_]
  if ("obj_floor_area_clean_m2" %in% names(x)) x[obj_floor_area_clean_m2 <= -2147483647L, obj_floor_area_clean_m2 := NA_integer_]
  code_to_label <- function(code, labels) fifelse(code < length(labels), labels[code + 1L], NA_character_)
  if ("obj_nonres_class" %in% names(x))    x[, obj_nonres_class    := code_to_label(obj_nonres_class, cfg$nonres_classes)]
  if ("obj_floor_area_flag" %in% names(x)) x[, obj_floor_area_flag := code_to_label(obj_floor_area_flag, cfg$floor_area_flags)]
  if ("obj_gebruiksdoel" %in% names(x))    x[, obj_gebruiksdoel    := code_to_label(obj_gebruiksdoel, cfg$gebruiksdoelen)]

  # role assignment: plus rows = new state, min rows + Onveranderd = incumbent state
  # A mutation appears as a "plus" row (what was built) and/or a "min" row (what
  # disappeared); Onveranderd rows are untouched stock. These flags let later scripts
  # pick the pre- or post-mutation side of a site without re-deriving the type lists.
  # obj_is_woon: residential yes/no, looked up per redev type from a cfg vector.
  x[, is_plus      := redev_type_lbl %in% cfg$redev_plus]
  x[, is_min       := redev_type_lbl %in% cfg$redev_min]
  # Onveranderd_NW (id 10, export from 25-09): unchanged non-residential units, either in the Onv_ site of
  # their mixed building or in the potential sites of the non-residential stock (OnvNW_)
  x[, is_incumbent := is_min | redev_type_lbl %chin% c("Onveranderd", "Onveranderd_NW")]
  x[, obj_is_woon  := cfg$redev_is_woon[redev_type + 1L]]

  # Floor area plausibility (RuimteScanner rules): a dwelling larger than five times the footprint
  # of its building -> NA, above 500 m2 capped; a non-residential unit is capped at what fits in its
  # building (footprint x storeys from the building height, at most 45). Exports from 25-09 carry the
  # cleaned value (obj_floor_area_clean_m2, GeoDMS NietWoonWaardering); for older exports the two
  # dwelling rules are applied here. The raw value is kept for inspection.
  x[, obj_floor_area_raw_m2 := obj_floor_area_res_m2]
  if ("obj_floor_area_clean_m2" %in% names(x)) {
    x[, obj_floor_area_res_m2 := obj_floor_area_clean_m2]
    rd_log("Floor area cleaned in the export; flags:")
    print(x[, .N, by = obj_floor_area_flag][order(-N)])
  } else {
    if ("obj_pand_footprint_m2" %in% names(x))
      x[obj_is_woon == TRUE & !is.na(obj_pand_footprint_m2) &
        obj_floor_area_res_m2 > cfg$floor_area_max_ratio_footprint * obj_pand_footprint_m2, obj_floor_area_res_m2 := NA_integer_]
    x[obj_is_woon == TRUE & obj_floor_area_res_m2 > cfg$floor_area_max_res, obj_floor_area_res_m2 := cfg$floor_area_max_res]
  }
  rd_log("Floor area: %s dwellings set to NA (> %gx footprint), %s capped at %d m2",
         format(x[obj_is_woon == TRUE & is.na(obj_floor_area_res_m2) & !is.na(obj_floor_area_raw_m2), .N], big.mark = ","),
         cfg$floor_area_max_ratio_footprint,
         format(x[obj_is_woon == TRUE & obj_floor_area_raw_m2 > cfg$floor_area_max_res, .N], big.mark = ","), cfg$floor_area_max_res)

  # Missing dwelling type (WP4), mostly demolished dwellings whose type can no longer be derived
  # from their neighbours: without a type there is no price, and the site's acquisition cost used to
  # become 0. RuimteScanner rule (SourceData/Vastgoed/EigendomStaat.dms): more than one dwelling in
  # the building -> appartement, otherwise vrijstaand. The export (from 25-09) counts the dwellings in
  # the building at the object's own reference date over the full BAG history (obj_pand_n_woningen);
  # older exports fall back on counting export rows within the same role (new or existing state).
  # Flagged, so its effect can be checked.
  if ("obj_pand_n_woningen" %in% names(x)) {
    x[, n_woon_in_pand := obj_pand_n_woningen]
  } else {
    x[obj_is_woon == TRUE, n_woon_in_pand := .N, by = .(pand_bag_nr, is_plus)]
  }
  x[, housetype_imputed := obj_is_woon & is.na(obj_housetype_lbl)]
  x[housetype_imputed == TRUE, obj_housetype_lbl := fifelse(!is.na(n_woon_in_pand) & n_woon_in_pand > 1, "appartement", "vrijstaand")]
  rd_log("Dwelling type imputed for %s dwellings (%s of them existing stock)",
         format(x[housetype_imputed == TRUE, .N], big.mark = ","),
         format(x[housetype_imputed == TRUE & is_incumbent == TRUE, .N], big.mark = ","))

  # 2012 double-count flag (#26, option 2): new construction registered in 2012 with an old
  # building year is suspected Woningregister->BAG administrative (CBS corrected -56% N in 2012, not reproducible).
  # (redev_yearmonth %/% 100L is integer division: it turns yyyymm codes into the year)
  x[, flag_2012_dubbel := redev_type_lbl %in% c("Nieuwbouw", "SN_Nieuwbouw") &
                          redev_yearmonth %/% 100L == 2012L &
                          !is.na(obj_building_year) & obj_building_year <= 2010L]

  # x[] with empty brackets returns the table and restores auto-printing after :=
  # assignments (a data.table quirk); see README, data.table primer.
  x[]
}

## ---------------------------------------------------------------------------
## Hedonic incumbent value (phase 1: own WP4)
## ---------------------------------------------------------------------------
# Map a construction year to the name of the matching bouwperiode dummy in the
# coefficient CSV. fcase() tests the conditions top to bottom and returns the first
# hit, so each <= bound closes one period bin.
building_period_term <- function(bouwjaar) {
  fcase(is.na(bouwjaar),   NA_character_,
        bouwjaar <= 1925L, "bouwperiode_tm1925",
        bouwjaar <= 1950L, "bouwperiode_1926_1950",
        bouwjaar <= 1965L, "bouwperiode_1951_1965",
        bouwjaar <= 1973L, "bouwperiode_1966_1973",
        bouwjaar <= 1981L, "bouwperiode_1974_1981",
        bouwjaar <= 1991L, "bouwperiode_1982_1991",
        bouwjaar <= 2001L, "bouwperiode_1992_2001",
        default = "bouwperiode_va2002")
}

add_price_reconstruction <- function(x, co = read_coefficients()) {
  rd_log("Price reconstruction (price level %d)", cfg$price_level_year)
  # wp4: each object's housing type label, used below to pick type-specific coefficients
  wp4 <- x$obj_housetype_lbl

  # region proxy values of the object's OWN type
  # The export holds one reg_<type>_<char> column per WP4 type; each row needs the value
  # for its own type. m[cbind(row, col)] is R matrix indexing that picks exactly one cell
  # per row: row i, the column belonging to object i's type. Regional averages stand in
  # because incumbents have no NVM transaction characteristics of their own.
  # Where a region has no NVM data for a type the regional average is NA, which would leave the
  # object without a price; as in RuimteScanner (#676) a national value is used instead, here the
  # median of that column over all objects.
  reg_column <- function(char) {
    idx <- match(wp4, cfg$wp4_names)
    m <- as.matrix(x[, paste0("reg_", cfg$wp4_names, "_", char), with = FALSE])
    for (j in seq_len(ncol(m))) m[is.na(m[, j]), j] <- median(m[, j], na.rm = TRUE)
    m[cbind(seq_len(nrow(m)), idx)]
  }
  # Green and water shares around the object (fr_natuur_tot2500m, fr_water_500m): part of the
  # estimated hedonic model, so they must be part of the prediction too.
  loc_col <- function(term) {
    col <- cfg$green_cols[[term]]
    if (!col %in% names(x)) stop("Export lacks column ", col, " for coefficient term ", term, "; run a fresh export.")
    x[[col]]
  }

  # Linear predictor of the hedonic model: constant + sum(coef * characteristic), fully
  # vectorized over all rows at once. Object-specific terms come from the BAG (floor
  # area, building year via the dummy below); the rest are regional or grid proxies.
  lp <- coef_for(co, "constant", wp4) +
    coef_for(co, "lnsize", wp4)     * log(pmax(x$obj_floor_area_res_m2, 1L)) +
    coef_for(co, "lnlotsize", wp4)  * log(pmax(reg_column("lotsize"), 1)) +
    coef_for(co, "nrooms", wp4)     * reg_column("nrooms") +
    coef_for(co, "d_maintgood", wp4) * reg_column("d_maintgood") +
    coef_for(co, "d_highrise", wp4)  * reg_column("d_highrise") +
    # d_hoogte_onbekend: no regional average in the export; 0 = 'height known' assumed
    coef_for(co, paste0("trans_year_", cfg$price_level_year), wp4) +
    coef_for(co, "lntt_500k_2024", wp4) * log(x$loc_tt_500k_2024_min) +
    coef_for(co, "lntt_ovknoop", wp4)   * log(pmax(x$loc_tt_ovknoop_2026_min, cfg$ovknoop_floor)) +
    coef_for(co, "uai_2012", wp4)       * x$uai_2012 +
    coef_for(co, "fr_natuur_tot2500m", wp4) * loc_col("fr_natuur_tot2500m") +
    coef_for(co, "fr_water_500m", wp4)      * loc_col("fr_water_500m")

  # bouwperiode dummy: look up the appropriate term per row
  # melt() reshapes the bouwperiode coefficient rows from wide (one column per WP4 type)
  # to long format (coef_name, wp4, coef). The join co_bp[data.table(...), on = ...] then
  # looks up each object's (period term, type) pair and returns the matching coefficient
  # (x.coef means "the coef column of the table being searched"). Objects with an unknown
  # building year get NA here, turned into 0 below. See README, data.table primer.
  bp <- building_period_term(x$obj_building_year)
  co_bp <- melt(co[coef_name %like% "^bouwperiode_"], id.vars = "coef_name",
                variable.name = "wp4", value.name = "coef")
  # The key table MUST be built outside the co_bp[...] call: inside the brackets data.table
  # evaluates the expression with co_bp's own columns in scope, so `wp4` would resolve to
  # co_bp$wp4 (32 rows = 8 periods x 4 types, silently recycled over all objects) instead of
  # each object's own housing type. Fixed 30-07; before that every object got the building
  # period coefficient of a cyclically assigned type.
  co_bp[, wp4 := as.character(wp4)]        # melt makes it a factor; the key below is character
  bp_key <- data.table(coef_name = bp, wp4 = wp4)
  bp_lookup <- co_bp[bp_key, on = c("coef_name", "wp4"), x.coef]
  lp <- lp + fifelse(is.na(bp_lookup), 0, bp_lookup)

  # Final value columns, added by reference with :=. prijs_hat_woon = exp(linear
  # predictor), only for residential objects with a known type and floor area.
  x[, prijs_hat_woon := fifelse(!is.na(wp4) & obj_is_woon & !is.na(obj_floor_area_res_m2), exp(lp), NA_real_)]
  # non-residential incumbent value: Eur/m2 x floor area. No hedonic model exists for the
  # non-residential stock. Exports from 25-09 carry a value per m2 at the 2023 price level per
  # object class (hall or other), set as in RuimteScanner (#674): the local dwelling WOZ per m2
  # times a ratio per class, calibrated so that the national floor-weighted averages match about
  # 600 (halls) and 1,400 (other) Eur/m2. Older exports only have the dwelling WOZ itself.
  nonres_eur_m2 <- if ("obj_nonres_eur_m2_2023" %in% names(x)) x$obj_nonres_eur_m2_2023 else x$loc_woz_nonres_eur_m2
  x[, waarde_nonres := fifelse(!obj_is_woon & !is.na(obj_floor_area_res_m2),
                               nonres_eur_m2 * obj_floor_area_res_m2, NA_real_)]
  # acq_waarde: the incumbent value used later as acquisition cost, hedonic price for
  # residential objects and the non-residential value otherwise
  x[, acq_waarde := fifelse(obj_is_woon, prijs_hat_woon, waarde_nonres)]
  x[]
}

## ---------------------------------------------------------------------------
## Run block: executes only when this file is started as a standalone script
## (sys.nframe() == 0 means "not called from inside a function") or when a caller
## sets run_02 <- TRUE before sourcing. Loads the export, reconstructs the prices
## and caches the enriched table as an RDS file for the next pipeline step.
if (sys.nframe() == 0L || isTRUE(get0("run_02", ifnotfound = FALSE))) {
  x <- load_perobject()
  rd_log("Rows: %s; types:", format(nrow(x), big.mark = ","))
  print(x[, .N, by = redev_type_lbl][order(-N)])
  x <- add_price_reconstruction(x)
  rd_log("prijs_hat_woon: median %.0f (residential incumbents)", x[is_incumbent == TRUE, median(prijs_hat_woon, na.rm = TRUE)])
  saveRDS(x, cfg$file_perobject_rds, compress = FALSE)
  rd_log("Written: %s", cfg$file_perobject_rds)
}
