# 05_alternatives.R — steps 2a-2c (issue #16): alternatives table ("long format") with
# revenue, costs and residual value per (site, cluster alternative).
#
# 2a Revenue_sk : n_units_k x sum_t( share_t,k x price_t,sk ), with price via the
#                 hedonic model exp(constant + sum(coef x characteristic)) per WP4.
#                 Since only lnsize depends on the cluster, a base price exp(lp_site) is
#                 computed per (site, type) and scaled per cluster with size_k^coef_lnsize
#                 — a bulk predict without loops over sites.
# 2b Costs_sk   : land production (loc_grondprod_eur_ha x site_ha, 2023 price level)
#                 + construction costs (gross floor area = unit size/vormfactor x CBS rate per landsdeel)
#                 + incumbent demolition costs (from 03_sites; k-invariant).
# 2c RV_sk      : Revenue_sk - Costs_sk; choice indicator ca = 1 for the k-means cluster
#                 of the realized site (= nearest centroid in the standardized space,
#                 by construction of k-means).
#
# DEFAULTS for open decision points (adjustable via 00_config.R; see also issue #16):
#  - characteristics of new unit: size from the cluster centroid (same for all types within
#    the cluster; the clustering has no type-specific size); nrooms/lotsize/d_highrise
#    from the regional means (reg_<wp4>_*, same proxy choice as the incumbent reconstruction);
#    d_maintgood = cfg$alt_d_maintgood (1: new construction is in good condition);
#    d_hoogte_onbekend = 0; bouwperiode = va2002 (reference, coef 0); price level trans_year_2023.
#  - type mix per cluster: centroid shares normalized to sum 1.
#  - n_units continuous (density_k x site_ha), no rounding.
#  - construction costs: CBS 83673NED, column cfg$construction_costs_column ('koop_eur_m2'); vormfactor
#    eengezins (0.76) for the three ground-level types, meergezins (0.78) for appartement
#    (hoogbouw 0.65 unused: clusters have no height information).
#  - demolition costs are k-invariant: they drop out of the conditional logit (stage 1) but
#    carry through into the inclusive value and hence into stage 2. Pure new-construction
#    sites (no incumbent): 0.
#  - land production variants _low/_high only as separate RV columns (sensitivity).
#
# Output: cfg$file_alt_rds = list(long = (site x K) table, sites = site table with
# stage-2 ingredients (acquisition, demolition, frictions), centroids).
# NB: the cluster menu and the ca indicator follow the stage-1 sample (cfg$stage1_sample,
# default 'sn'); the long table itself ALWAYS covers all sites (the inclusive value of
# step 4 is also needed for undeveloped sites).

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))
source(file.path(.rd_script_dir, "02_load_perobject.R"))   # for read_coefficients/coef_for

build_alternatives <- function(s, cl, co = read_coefficients()) {
  st <- copy(s$attrs)
  st[, site_ha := site_size / 1e4]

  # incumbent side (acquisition/demolition/outcome); sites without incumbent rows = pure new construction
  st[s$incumbent, on = "site_id", `:=`(
    has_incumbent      = TRUE,
    was_redeveloped    = i.was_redeveloped,
    acq_cost_total_eur = i.acq_cost_total_eur,
    demolition_cost_eur = i.demolition_cost_eur,
    n_units_res_inc    = i.n_units_res,
    floor_area_res_inc = i.floor_area_res_m2)]
  st[is.na(has_incumbent), `:=`(has_incumbent = FALSE, was_redeveloped = TRUE,
                                acq_cost_total_eur = 0, demolition_cost_eur = 0)]

  # realized cluster (k-means assignment from 04) = choice indicator later on
  st[cl$sites, on = "site_id", cluster_real := i.cluster]

  # construction cost rate per site via landsdeel
  st[, bouw_kental := cfg$construction_costs_2023[[cfg$construction_costs_column]][match(landsdeel, cfg$construction_costs_2023$landsdeel)]]

  unusable <- st[, !complete.cases(.SD),
                 .SDcols = c("site_size", "loc_tt_500k_2024_min", "loc_tt_ovknoop_2026_min",
                             "uai_2012", "loc_grondprod_eur_ha", "bouw_kental")]
  rd_log("Sites: %s total; %s (%.2f%%) miss a price/cost input -> RV becomes NA",
         format(nrow(st), big.mark = ","), format(sum(unusable), big.mark = ","), 100 * mean(unusable))

  # -- 2a: base price per (site, type): everything except the lnsize term --------
  ct <- function(term, t) coef_for(co, term, t)  # scalar
  P_base <- sapply(cfg$wp4_names, function(t)
    exp(ct("constant", t) +
        ct("lnlotsize", t)   * log(pmax(st[[paste0("reg_", t, "_lotsize")]], 1)) +
        ct("nrooms", t)      * st[[paste0("reg_", t, "_nrooms")]] +
        ct("d_maintgood", t) * cfg$alt_d_maintgood +
        ct("d_highrise", t)  * st[[paste0("reg_", t, "_d_highrise")]] +
        ct(paste0("trans_year_", cfg$price_level_year), t) +
        ct("lntt_500k_2024", t) * log(st$loc_tt_500k_2024_min) +
        ct("lntt_ovknoop", t)   * log(pmax(st$loc_tt_ovknoop_2026_min, cfg$ovknoop_floor)) +
        ct("uai_2012", t)       * st$uai_2012))
  ls_coef <- vapply(cfg$wp4_names, function(t) ct("lnsize", t), numeric(1))
  vf      <- unname(cfg$vormfactor[cfg$vormfactor_wp4[cfg$wp4_names]])

  # -- one block of the long table per cluster alternative -----------------------
  K <- nrow(cl$centroids)
  share_cols <- paste0("share_", cfg$wp4_names)
  blocks <- lapply(seq_len(K), function(k) {
    ctr    <- cl$centroids[cluster == k]
    shares <- as.numeric(ctr[, ..share_cols]); shares <- shares / sum(shares)
    size_k <- ctr$unit_size_mean
    n_units <- ctr$density_per_ha * st$site_ha
    price_units <- P_base %*% (shares * size_k^ls_coef)          # sum_t share_t x price_t,sk
    bvo_factor  <- sum(shares / vf)                              # m2 gross floor area per m2 living area, weighted
    block <- data.table(
      site_id        = st$site_id,
      cluster_alt    = k,
      n_units_alt    = n_units,
      revenue_eur    = n_units * as.numeric(price_units),
      cost_construction_eur = n_units * size_k * bvo_factor * st$bouw_kental,
      cost_land_eur  = st$loc_grondprod_eur_ha * st$site_ha,
      cost_demolition_eur = st$demolition_cost_eur)
    block[, rv_eur := revenue_eur - cost_construction_eur - cost_land_eur - cost_demolition_eur]
    # land production sensitivity (RV variants only, no separate cost columns)
    block[, rv_eur_grond_low  := rv_eur + cost_land_eur - st$loc_grondprod_eur_ha_low  * st$site_ha]
    block[, rv_eur_grond_high := rv_eur + cost_land_eur - st$loc_grondprod_eur_ha_high * st$site_ha]
    block[, ca := as.integer(!is.na(st$cluster_real) & st$cluster_real == k)]
    block
  })
  long <- rbindlist(blocks)
  setkey(long, site_id, cluster_alt)

  list(long = long, sites = st, centroids = cl$centroids)
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_05", ifnotfound = FALSE))) {
  s  <- readRDS(cfg$file_sites_rds)
  cl <- readRDS(cfg$file_clusters_rds)
  alt <- build_alternatives(s, cl)

  rd_log("Long table: %s rows (%s sites x %d alternatives)",
         format(nrow(alt$long), big.mark = ","), format(nrow(alt$sites), big.mark = ","), nrow(alt$centroids))
  rd_log("RV (mln Eur, median per alternative, all sites):")
  print(alt$long[, .(rv_mln_med = median(rv_eur, na.rm = TRUE) / 1e6,
                     rv_pos_pct = 100 * mean(rv_eur > 0, na.rm = TRUE)), by = cluster_alt])
  # sanity: does the realized site pick the highest-RV alternative more often than chance (1/K)?
  real <- alt$sites[!is.na(cluster_real), .(site_id, cluster_real)]
  chosen <- alt$long[real, on = "site_id"][!is.na(rv_eur),
                     .(best = cluster_alt[which.max(rv_eur)], cluster_real = cluster_real[1]), by = site_id]
  rd_log("Realized sites where chosen cluster = highest-RV alternative: %.1f%% (chance: %.1f%%)",
         100 * chosen[, mean(best == cluster_real)], 100 / nrow(alt$centroids))

  saveRDS(alt, cfg$file_alt_rds, compress = FALSE)
  rd_log("Written: %s", cfg$file_alt_rds)
}
