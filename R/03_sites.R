# 03_sites.R — step 0 (issue #16): aggregate the object-level export to site level.
#
# Two aggregations per site_id:
#   sites_incumbent : the original state (min rows + Onveranderd) — universe for stage 2.
#   sites_new       : the realized new state (plus rows) — input for the k-means (step 1).
# Site-level attributes that occur only once (location, region, frictions) come from the first row.

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))

build_sites <- function(x) {
  # -- shared site attributes (first non-NA per site) --------------------------
  first_non_na <- function(v) v[which(!is.na(v))[1]]
  site_attrs <- x[, .(
    agglomeratie   = first_non_na(agglomeratie),
    gemeente_code  = first_non_na(gemeente_code),
    wijk_code      = first_non_na(wijk_code),
    buurt_code     = first_non_na(buurt_code),
    x_coord        = first_non_na(x_coord),
    y_coord        = first_non_na(y_coord),
    site_size      = first_non_na(site_size),
    uai_2012       = first_non_na(uai_2012),
    loc_tt_500k_2024_min  = first_non_na(loc_tt_500k_2024_min),
    loc_tt_ovknoop_2026_min = first_non_na(loc_tt_ovknoop_2026_min),
    p_owner_occupier_buurt  = first_non_na(p_owner_occupier_buurt),
    p_socialhousing_buurt   = first_non_na(p_socialhousing_buurt),
    wijk_p_woningcorporatie = first_non_na(wijk_p_woningcorporatie),
    # cost components (#16 step 2): land production Eur/ha (2023) + landsdeel for construction-cost figures
    loc_grondprod_eur_ha      = first_non_na(loc_grondprod_eur_ha),
    loc_grondprod_eur_ha_low  = first_non_na(loc_grondprod_eur_ha_low),
    loc_grondprod_eur_ha_high = first_non_na(loc_grondprod_eur_ha_high),
    landsdeel      = first_non_na(landsdeel),
    oad            = first_non_na(oad),
    isprotectheritagearea = any(isprotectheritagearea, na.rm = TRUE),
    is_natura2000         = any(is_natura2000, na.rm = TRUE)
  ), by = site_id]

  # regional-average NVM characteristics (grid values: ~identical within a site -> first row suffices);
  # needed in 05_alternatieven for the price prediction of all 4 types on each site
  reg_cols <- as.vector(outer(cfg$wp4_names, c("lotsize", "nrooms", "d_maintgood", "d_highrise", "size"),
                              function(w, c) paste0("reg_", w, "_", c)))
  site_attrs <- unique(x[, c("site_id", reg_cols), with = FALSE], by = "site_id")[site_attrs, on = "site_id"]

  # -- incumbent state ----------------------------------------------------------
  inc <- x[is_incumbent == TRUE]
  # demolition rate per object (Eur/m2, 2023 price level): residential mapped to WP4 (unknown type ->
  # mean of the four), non-residential to 'kantoor'; applied to the floor area (BVO approximation)
  rate_res <- unname(cfg$demolition_costs_2023[match(inc$obj_housetype_lbl, names(cfg$demolition_costs_2023))])
  rate_res[is.na(rate_res)] <- mean(cfg$demolition_costs_2023[cfg$wp4_names])
  inc[, demolition_rate := fifelse(obj_is_woon, rate_res, cfg$demolition_costs_2023[["kantoor"]])]
  sites_inc <- inc[, .(
    n_obj                = .N,
    n_units_res          = sum(obj_is_woon),
    n_units_nonres       = sum(!obj_is_woon),
    floor_area_res_m2    = sum(fifelse(obj_is_woon, as.numeric(obj_floor_area_res_m2), 0), na.rm = TRUE),
    floor_area_nonres_m2 = sum(fifelse(!obj_is_woon, as.numeric(obj_floor_area_res_m2), 0), na.rm = TRUE),
    sum_footprint_m2     = first_non_na(site_sum_footprint),
    mode_building_year   = { b <- obj_building_year[!is.na(obj_building_year)]
                             if (length(b)) as.integer(names(sort(table(b), decreasing = TRUE))[1]) else NA_integer_ },
    has_single_function  = uniqueN(obj_is_woon) == 1L,
    # acquisition costs: hedonic house value + WOZ value for non-residential (raw euros, censoring in estimation step)
    acq_cost_res_eur     = sum(fifelse(obj_is_woon, acq_waarde, 0), na.rm = TRUE),
    acq_cost_nonres_eur  = sum(fifelse(!obj_is_woon, acq_waarde, 0), na.rm = TRUE),
    demolition_cost_eur  = sum(demolition_rate * as.numeric(obj_floor_area_res_m2), na.rm = TRUE),
    was_redeveloped      = any(redev_type_lbl != "Onveranderd"),
    # redevelopment start moment (09_hazard): first min mutation on the site (Sloop/Onttrekking);
    # Onveranderd sites have no mutation month -> NA
    event_yearmonth      = { v <- redev_yearmonth[!is.na(redev_yearmonth)]; if (length(v)) min(v) else NA_integer_ }
  ), by = site_id]
  sites_inc[, acq_cost_total_eur := acq_cost_res_eur + acq_cost_nonres_eur]

  # -- new state (realized redevelopment) -----------------------------------------
  pl <- x[is_plus == TRUE]
  sites_new <- pl[, c(list(
    n_units_new       = .N,
    floor_area_m2     = sum(as.numeric(obj_floor_area_res_m2), na.rm = TRUE),
    unit_size_mean    = mean(obj_floor_area_res_m2, na.rm = TRUE),
    redev_yearmonth   = { v <- redev_yearmonth[!is.na(redev_yearmonth)]; if (length(v)) min(v) else NA_integer_ },
    has_transformation = any(redev_type_lbl == "Transformatie_Plus"),
    has_sn             = any(redev_type_lbl == "SN_Nieuwbouw"),
    # 2012 double-counting flag (#26): belongs to the PLUS side (Nieuwbouw/SN_Nieuwbouw rows;
    # previously sat erroneously in the incumbent aggregation where it always counted 0)
    n_flag_2012 = sum(flag_2012_dubbel),
    # multi-project diagnostic (28-07): >1 permit or a long construction period indicates spatially
    # clustered projects (7.1% has n_doc>2 and >24 months; flag for stage 1 robustness)
    n_doc      = uniqueN(pand_docnum),
    months_spread = { v <- redev_yearmonth[!is.na(redev_yearmonth)]
                   if (length(v)) (max(v) %/% 100L - min(v) %/% 100L) * 12L + (max(v) %% 100L - min(v) %% 100L) else NA_integer_ }
  ), as.list(prop.table(table(factor(obj_housetype_lbl, levels = cfg$wp4_names))) |> setNames(paste0("share_", cfg$wp4_names)))
  ), by = site_id]

  # density/FAR based on the site_size of the incumbent side (same site)
  sites_new[site_attrs, on = "site_id", site_size := i.site_size]
  sites_new[, density_per_ha := n_units_new / (site_size / 1e4)]
  sites_new[, far            := floor_area_m2 / site_size]

  list(attrs = site_attrs, incumbent = sites_inc, new = sites_new)
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_03", ifnotfound = FALSE))) {
  x <- readRDS(cfg$file_perobject_rds)
  s <- build_sites(x)
  rd_log("Sites: %s attrs, %s incumbent, %s new",
         format(nrow(s$attrs), big.mark = ","), format(nrow(s$incumbent), big.mark = ","),
         format(nrow(s$new), big.mark = ","))
  saveRDS(s, cfg$file_sites_rds, compress = FALSE)
  rd_log("Written: %s", cfg$file_sites_rds)
}
