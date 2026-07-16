# 02_load_perobject.R — PerObject_Export (GeoDMS mmd) inlezen, labelen en de
# hedonische incumbentwaarde reconstrueren (issue #16, stap 0-voorbereiding).
#
# Prijsreconstructie (afspraak #13/#20): GeoDMS exporteert ruwe componenten; hier
# bouwen we prijs = exp(constant + som(coef * kenmerk)) per WP4 met de
# coefficienten-CSV (PriceCoefficients_WP4_<datum>.csv, spec 'redev').
# Object-eigen: lnsize (obj_floor_area_res_m2), bouwperiode (obj_building_year).
# Regio-proxies (incumbent heeft geen NVM-kenmerken): reg_<wp4>_{lotsize,nrooms,
# d_maintgood,d_highrise}. d_hoogte_onbekend: geen regiogemiddelde beschikbaar -> 0.
# Prijspeil: trans_year_<cfg$prijspeil_jaar>. Locatie: lntt_500k_2024, lntt_ovknoop, uai_2012.
# Niet-woon incumbent (Transformatie_Min, SN_Sloop_nw): loc_woz_nonres_eur_m2 * m2.

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))
source(file.path(.rd_script_dir, "01_read_mmd.R"))

## ---------------------------------------------------------------------------
## Coefficienten
## ---------------------------------------------------------------------------
lees_coefficienten <- function(pad = cfg$file_coef) {
  co <- fread(pad, sep = ";", na.strings = "")
  stopifnot(all(c("coef_name", cfg$wp4_names) %in% names(co)))
  co
}

coef_van <- function(co, term, wp4) {
  # wp4: character-vector met cfg$wp4_names-waarden; onbekende term of ontbrekende coef -> 0
  rij <- co[coef_name == term]
  if (!nrow(rij)) return(rep(0, length(wp4)))
  out <- as.numeric(rij[1, cfg$wp4_names, with = FALSE])[match(wp4, cfg$wp4_names)]
  fifelse(is.na(out), 0, out)
}

## ---------------------------------------------------------------------------
## Inlezen + labels
## ---------------------------------------------------------------------------
laad_perobject <- function(dir_mmd = cfg$dir_mmd) {
  rd_log("Lees mmd: %s", dir_mmd)
  x <- read_mmd(dir_mmd)
  setnames(x, tolower(names(x)))

  # classificatie-ids -> labels (255 = null)
  x[, redev_type_lbl   := fifelse(redev_type   < length(cfg$redev_types), cfg$redev_types[redev_type + 1L], NA_character_)]
  x[, obj_housetype_lbl := fifelse(obj_housetype < length(cfg$wp4_names),  cfg$wp4_names[obj_housetype + 1L], NA_character_)]

  # null-sentinels -> NA
  if ("obj_building_year" %in% names(x))    x[obj_building_year >= 65535L, obj_building_year := NA_integer_]
  if ("obj_floor_area_res_m2" %in% names(x)) x[obj_floor_area_res_m2 <= -2147483647L, obj_floor_area_res_m2 := NA_integer_]
  if ("redev_yearmonth" %in% names(x))       x[redev_yearmonth <= -2147483647L, redev_yearmonth := NA_integer_]

  # rolindeling: plus-rijen = nieuwe staat, min-rijen + Onveranderd = incumbent-staat
  x[, is_plus      := redev_type_lbl %in% cfg$redev_plus]
  x[, is_min       := redev_type_lbl %in% cfg$redev_min]
  x[, is_incumbent := is_min | redev_type_lbl == "Onveranderd"]
  x[, obj_is_woon  := cfg$redev_is_woon[redev_type + 1L]]

  # 2012-dubbeltellingenflag (#26, optie 2): nieuwbouw geregistreerd in 2012 met oud bouwjaar
  # is verdacht Woningregister->BAG-administratief (CBS corrigeerde -56% N in 2012, niet reproduceerbaar).
  x[, flag_2012_dubbel := redev_type_lbl %in% c("Nieuwbouw", "SN_Nieuwbouw") &
                          redev_yearmonth %/% 100L == 2012L &
                          !is.na(obj_building_year) & obj_building_year <= 2010L]

  x[]
}

## ---------------------------------------------------------------------------
## Hedonische incumbentwaarde (fase 1: eigen WP4)
## ---------------------------------------------------------------------------
bouwperiode_term <- function(bouwjaar) {
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

voeg_prijsreconstructie_toe <- function(x, co = lees_coefficienten()) {
  rd_log("Prijsreconstructie (prijspeil %d)", cfg$prijspeil_jaar)
  wp4 <- x$obj_housetype_lbl

  # regio-proxywaarden van het EIGEN type per object
  reg_kolom <- function(char) {
    idx <- match(wp4, cfg$wp4_names)
    m <- as.matrix(x[, paste0("reg_", cfg$wp4_names, "_", char), with = FALSE])
    m[cbind(seq_len(nrow(m)), idx)]
  }

  lp <- coef_van(co, "constant", wp4) +
    coef_van(co, "lnsize", wp4)     * log(pmax(x$obj_floor_area_res_m2, 1L)) +
    coef_van(co, "lnlotsize", wp4)  * log(pmax(reg_kolom("lotsize"), 1)) +
    coef_van(co, "nrooms", wp4)     * reg_kolom("nrooms") +
    coef_van(co, "d_maintgood", wp4) * reg_kolom("d_maintgood") +
    coef_van(co, "d_highrise", wp4)  * reg_kolom("d_highrise") +
    # d_hoogte_onbekend: geen regiogemiddelde in de export; 0 = 'hoogte bekend' aangehouden
    coef_van(co, paste0("trans_year_", cfg$prijspeil_jaar), wp4) +
    coef_van(co, "lntt_500k_2024", wp4) * log(x$loc_tt_500k_2024_min) +
    coef_van(co, "lntt_ovknoop", wp4)   * log(pmax(x$loc_tt_ovknoop_2026_min, cfg$ovknoop_floor)) +
    coef_van(co, "uai_2012", wp4)       * x$uai_2012

  # bouwperiode-dummy: per rij de juiste term opzoeken
  bp <- bouwperiode_term(x$obj_building_year)
  co_bp <- melt(co[coef_name %like% "^bouwperiode_"], id.vars = "coef_name",
                variable.name = "wp4", value.name = "coef")
  bp_lookup <- co_bp[data.table(coef_name = bp, wp4 = wp4), on = c("coef_name", "wp4"), x.coef]
  lp <- lp + fifelse(is.na(bp_lookup), 0, bp_lookup)

  x[, prijs_hat_woon := fifelse(!is.na(wp4) & obj_is_woon & !is.na(obj_floor_area_res_m2), exp(lp), NA_real_)]
  # niet-woon incumbentwaarde: WOZ Eur/m2 x oppervlakte
  x[, waarde_nonres := fifelse(!obj_is_woon & !is.na(obj_floor_area_res_m2),
                               loc_woz_nonres_eur_m2 * obj_floor_area_res_m2, NA_real_)]
  x[, acq_waarde := fifelse(obj_is_woon, prijs_hat_woon, waarde_nonres)]
  x[]
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_02", ifnotfound = FALSE))) {
  x <- laad_perobject()
  rd_log("Rijen: %s; types:", format(nrow(x), big.mark = ","))
  print(x[, .N, by = redev_type_lbl][order(-N)])
  x <- voeg_prijsreconstructie_toe(x)
  rd_log("prijs_hat_woon: mediaan %.0f (incumbent woon)", x[is_incumbent == TRUE, median(prijs_hat_woon, na.rm = TRUE)])
  saveRDS(x, cfg$file_perobject_rds, compress = FALSE)
  rd_log("Weggeschreven: %s", cfg$file_perobject_rds)
}
