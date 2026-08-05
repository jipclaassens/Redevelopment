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
# Non-residential incumbent (Transformatie_Min, SN_Sloop_nw): loc_woz_nonres_eur_m2 * m2.

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

  # role assignment: plus rows = new state, min rows + Onveranderd = incumbent state
  # A mutation appears as a "plus" row (what was built) and/or a "min" row (what
  # disappeared); Onveranderd rows are untouched stock. These flags let later scripts
  # pick the pre- or post-mutation side of a site without re-deriving the type lists.
  # obj_is_woon: residential yes/no, looked up per redev type from a cfg vector.
  x[, is_plus      := redev_type_lbl %in% cfg$redev_plus]
  x[, is_min       := redev_type_lbl %in% cfg$redev_min]
  x[, is_incumbent := is_min | redev_type_lbl == "Onveranderd"]
  x[, obj_is_woon  := cfg$redev_is_woon[redev_type + 1L]]

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
  reg_column <- function(char) {
    idx <- match(wp4, cfg$wp4_names)
    m <- as.matrix(x[, paste0("reg_", cfg$wp4_names, "_", char), with = FALSE])
    m[cbind(seq_len(nrow(m)), idx)]
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
    coef_for(co, "uai_2012", wp4)       * x$uai_2012

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
  # non-residential incumbent value: WOZ Eur/m2 x floor area
  # (no hedonic model exists for non-residential stock; the local WOZ value per m2
  # times the floor area is the best available proxy)
  x[, waarde_nonres := fifelse(!obj_is_woon & !is.na(obj_floor_area_res_m2),
                               loc_woz_nonres_eur_m2 * obj_floor_area_res_m2, NA_real_)]
  # acq_waarde: the incumbent value used later as acquisition cost, hedonic price for
  # residential objects and the WOZ-based value otherwise
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
