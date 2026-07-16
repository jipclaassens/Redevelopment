# 03_sites.R — stap 0 (issue #16): object-level export aggregeren naar site-niveau.
#
# Twee aggregaties per site_id:
#   sites_incumbent : de oorspronkelijke staat (min-rijen + Onveranderd) — universum voor stage 2.
#   sites_nieuw     : de gerealiseerde nieuwe staat (plus-rijen) — invoer voor de k-means (stap 1).
# Site-level kenmerken die maar één keer spelen (locatie, regio, fricties) komen van de eerste rij.

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))

maak_sites <- function(x) {
  # -- gedeelde site-attributen (eerste niet-NA per site) ----------------------
  eerste <- function(v) v[which(!is.na(v))[1]]
  site_attrs <- x[, .(
    agglomeratie   = eerste(agglomeratie),
    gemeente_code  = eerste(gemeente_code),
    wijk_code      = eerste(wijk_code),
    buurt_code     = eerste(buurt_code),
    x_coord        = eerste(x_coord),
    y_coord        = eerste(y_coord),
    site_size      = eerste(site_size),
    uai_2012       = eerste(uai_2012),
    loc_tt_500k_2024_min  = eerste(loc_tt_500k_2024_min),
    loc_tt_ovknoop_2026_min = eerste(loc_tt_ovknoop_2026_min),
    p_owner_occupier_buurt  = eerste(p_owner_occupier_buurt),
    p_socialhousing_buurt   = eerste(p_socialhousing_buurt),
    wijk_p_woningcorporatie = eerste(wijk_p_woningcorporatie),
    # kostencomponenten (#16 stap 2): grondproductie Eur/ha (2023) + landsdeel voor bouwkosten-kentallen
    loc_grondprod_eur_ha      = eerste(loc_grondprod_eur_ha),
    loc_grondprod_eur_ha_low  = eerste(loc_grondprod_eur_ha_low),
    loc_grondprod_eur_ha_high = eerste(loc_grondprod_eur_ha_high),
    landsdeel      = eerste(landsdeel),
    oad            = eerste(oad),
    isprotectheritagearea = any(isprotectheritagearea, na.rm = TRUE),
    is_natura2000         = any(is_natura2000, na.rm = TRUE)
  ), by = site_id]

  # -- incumbent-staat ----------------------------------------------------------
  inc <- x[is_incumbent == TRUE]
  sites_inc <- inc[, .(
    n_obj                = .N,
    n_units_res          = sum(obj_is_woon),
    n_units_nonres       = sum(!obj_is_woon),
    floor_area_res_m2    = sum(fifelse(obj_is_woon, as.numeric(obj_floor_area_res_m2), 0), na.rm = TRUE),
    floor_area_nonres_m2 = sum(fifelse(!obj_is_woon, as.numeric(obj_floor_area_res_m2), 0), na.rm = TRUE),
    sum_footprint_m2     = eerste(site_sum_footprint),
    modus_bouwjaar       = { b <- obj_building_year[!is.na(obj_building_year)]
                             if (length(b)) as.integer(names(sort(table(b), decreasing = TRUE))[1]) else NA_integer_ },
    has_single_function  = uniqueN(obj_is_woon) == 1L,
    # verwervingskosten: hedonische woningwaarde + WOZ-waarde niet-woon (rauwe euro's, censoring in estimatiestap)
    acq_cost_res_eur     = sum(fifelse(obj_is_woon, acq_waarde, 0), na.rm = TRUE),
    acq_cost_nonres_eur  = sum(fifelse(!obj_is_woon, acq_waarde, 0), na.rm = TRUE),
    was_redeveloped      = any(redev_type_lbl != "Onveranderd"),
    n_flag_2012_dubbel   = sum(flag_2012_dubbel)
  ), by = site_id]
  sites_inc[, acq_cost_total_eur := acq_cost_res_eur + acq_cost_nonres_eur]

  # -- nieuwe staat (gerealiseerde herontwikkeling) -------------------------------
  pl <- x[is_plus == TRUE]
  sites_nieuw <- pl[, c(list(
    n_units_nieuw     = .N,
    floor_area_m2     = sum(as.numeric(obj_floor_area_res_m2), na.rm = TRUE),
    unit_size_mean    = mean(obj_floor_area_res_m2, na.rm = TRUE),
    redev_yearmonth   = { v <- redev_yearmonth[!is.na(redev_yearmonth)]; if (length(v)) min(v) else NA_integer_ },
    heeft_transformatie = any(redev_type_lbl == "Transformatie_Plus"),
    heeft_sn            = any(redev_type_lbl == "SN_Nieuwbouw")
  ), as.list(prop.table(table(factor(obj_housetype_lbl, levels = cfg$wp4_names))) |> setNames(paste0("aandeel_", cfg$wp4_names)))
  ), by = site_id]

  # dichtheid/FAR op basis van site_size van de incumbent-kant (zelfde site)
  sites_nieuw[site_attrs, on = "site_id", site_size := i.site_size]
  sites_nieuw[, dichtheid_per_ha := n_units_nieuw / (site_size / 1e4)]
  sites_nieuw[, far              := floor_area_m2 / site_size]

  list(attrs = site_attrs, incumbent = sites_inc, nieuw = sites_nieuw)
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_03", ifnotfound = FALSE))) {
  x <- readRDS(cfg$file_perobject_rds)
  s <- maak_sites(x)
  rd_log("Sites: %s attrs, %s incumbent, %s nieuw",
         format(nrow(s$attrs), big.mark = ","), format(nrow(s$incumbent), big.mark = ","),
         format(nrow(s$nieuw), big.mark = ","))
  saveRDS(s, cfg$file_sites_rds, compress = FALSE)
  rd_log("Weggeschreven: %s", cfg$file_sites_rds)
}
