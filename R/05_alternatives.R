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

# Locate the folder this script lives in, so the helper scripts below can be sourced with
# absolute paths regardless of the current working directory (works both when run via
# Rscript and when sourced from another script).
if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))
source(file.path(.rd_script_dir, "02_load_perobject.R"))   # for read_coefficients/coef_for

build_alternatives <- function(s, cl, co = read_coefficients()) {
  # Work on a copy: data.tables are modified "by reference" (:= writes new columns into the
  # table in place, without copying), so copy() protects the input s$attrs from being
  # changed. site_ha converts the site area from m2 to hectares for the land cost formulas.
  st <- copy(s$attrs)
  st[, site_ha := site_size / 1e4]
  # Area of the buildings that stood there before (25-09): for redeveloped sites the demolished
  # buildings only, formed with the rule of the unchanged stock; equal to site_ha for other sites.
  # Used for the per-hectare costs that are the same for every option (demolition), and in stage 2.
  # Falls back on site_ha where the export has no such area (older export, or no demolition).
  st[, site_ha_oorspr := fifelse(!is.na(site_size_oorspr) & site_size_oorspr > 0, site_size_oorspr / 1e4, site_ha)]

  # incumbent side (acquisition/demolition/outcome); sites without incumbent rows = pure new construction
  # Attach the incumbent-side aggregates to the site table via a data.table "update join":
  # each site_id of st is looked up in s$incumbent and := writes the matched values into st
  # itself (the i. prefix = "column from the joined table"; see README, data.table primer).
  # Sites WITHOUT incumbent rows are pure new construction (nothing stood there); the join
  # leaves them NA, and the second statement makes that explicit: nothing to acquire or
  # demolish (costs 0), and was_redeveloped = TRUE because the site exists precisely
  # because something was built.
  st[s$incumbent, on = "site_id", `:=`(
    has_incumbent      = TRUE,
    was_redeveloped    = i.was_redeveloped,
    acq_cost_total_eur = i.acq_cost_total_eur,
    demolition_cost_eur = i.demolition_cost_eur,
    n_units_res_inc    = i.n_units_res,
    n_units_nonres_inc = i.n_units_nonres,
    floor_area_res_inc = i.floor_area_res_m2)]
  st[is.na(has_incumbent), `:=`(has_incumbent = FALSE, was_redeveloped = TRUE,
                                acq_cost_total_eur = 0, demolition_cost_eur = 0)]

  # realized cluster (k-means assignment from 04) = choice indicator later on
  # Same update-join idiom: copy the observed cluster of each site from cl$sites into st.
  # Sites outside the stage-1 clustering sample get no match and stay NA; cluster_real
  # later becomes the chosen-alternative dummy ca (step 2c).
  st[cl$sites, on = "site_id", cluster_real := i.cluster]

  # construction cost rate per site via landsdeel
  # Plain base-R table lookup: match() finds each site's landsdeel in the CBS cost table
  # and picks the euro-per-m2 construction rate for that region (2023 price level).
  st[, bouw_kental := cfg$construction_costs_2023[[cfg$construction_costs_column]][match(landsdeel, cfg$construction_costs_2023$landsdeel)]]

  # Diagnostic only: flag sites that miss any price/cost input. .SDcols restricts .SD (the
  # "subset of data", i.e. the listed columns only) and complete.cases() marks rows without
  # NA; the log line reports how many sites will end up with an NA residual value.
  unusable <- st[, !complete.cases(.SD),
                 .SDcols = c("site_size", "loc_tt_500k_2024_min", "loc_tt_ovknoop_2026_min",
                             "uai_2012", "loc_grondprod_eur_ha", "bouw_kental")]
  rd_log("Sites: %s total; %s (%.2f%%) miss a price/cost input -> RV becomes NA",
         format(nrow(st), big.mark = ","), format(sum(unusable), big.mark = ","), 100 * mean(unusable))

  # -- 2a: base price per (site, type): everything except the lnsize term --------
  # sapply loops over the four WP4 dwelling types and returns a matrix P_base with one row
  # per site and one column per type: the hedonic price of a unit of that type at that
  # location (regional-mean characteristics, chosen price level), WITHOUT the size term.
  # The size term is applied per cluster below (price scales with size_k to the power of
  # the lnsize coefficient), so the expensive part runs once per site, not per (site, k).
  ct <- function(term, t) coef_for(co, term, t)  # scalar: one coefficient for (term, type)
  # Regional averages missing for a type (no NVM data in that region) would make the price of that
  # type, and so the residual value of every option on the site, NA; as in RuimteScanner (#676) a
  # national value is used instead: the median of the column over all sites.
  for (cn in as.vector(outer(cfg$wp4_names, c("lotsize", "nrooms", "d_highrise"), function(w, c) paste0("reg_", w, "_", c)))) {
    n_na <- st[is.na(get(cn)), .N]
    if (n_na) { st[is.na(get(cn)), (cn) := median(st[[cn]], na.rm = TRUE)]; rd_log("  %s: national fallback for %s sites", cn, format(n_na, big.mark = ",")) }
  }
  stopifnot("green/water shares missing: run a fresh export" = !anyNA(st$loc_fr_natuur_tot2500m[!is.na(st$uai_2012)]))
  P_base <- sapply(cfg$wp4_names, function(t)
    exp(ct("constant", t) +
        ct("lnlotsize", t)   * log(pmax(st[[paste0("reg_", t, "_lotsize")]], 1)) +
        ct("nrooms", t)      * st[[paste0("reg_", t, "_nrooms")]] +
        ct("d_maintgood", t) * cfg$alt_d_maintgood +
        ct("d_highrise", t)  * st[[paste0("reg_", t, "_d_highrise")]] +
        ct(paste0("trans_year_", cfg$price_level_year), t) +
        ct("lntt_500k_2024", t) * log(st$loc_tt_500k_2024_min) +
        ct("lntt_ovknoop", t)   * log(pmax(st$loc_tt_ovknoop_2026_min, cfg$ovknoop_floor)) +
        ct("uai_2012", t)       * st$uai_2012 +
        ct("fr_natuur_tot2500m", t) * st$loc_fr_natuur_tot2500m +
        ct("fr_water_500m", t)      * st$loc_fr_water_500m))
  # Per-type ingredients for the cluster loop: the lnsize coefficient (size scaling of the
  # price), the vormfactor (living area per m2 gross floor area, so bvo = size / vf) and the
  # construction cost index per type (cfg; apartments cost more per m2 than terraced houses).
  ls_coef <- vapply(cfg$wp4_names, function(t) ct("lnsize", t), numeric(1))
  vf      <- unname(cfg$vormfactor[cfg$vormfactor_wp4[cfg$wp4_names]])
  cti     <- unname(cfg$construction_type_index[cfg$wp4_names])

  # -- one block of the long table per cluster alternative -----------------------
  # Row expansion: lapply builds one data.table ("block") holding ALL sites for each of the
  # K cluster alternatives; rbindlist() below stacks the K blocks into the long table
  # (sites x K rows). Per block: shares = centroid type mix normalized to sum 1; the matrix
  # product P_base %*% (shares * size^coef) collapses the four type prices into one price
  # per site in a single step; revenue and the three cost parts then follow the header
  # formulas (2a/2b), and rv_eur = revenue minus costs (2c).
  K <- nrow(cl$centroids)
  share_cols <- paste0("share_", cfg$wp4_names)
  blocks <- lapply(seq_len(K), function(k) {
    ctr    <- cl$centroids[cluster == k]
    shares <- as.numeric(ctr[, ..share_cols]); shares <- shares / sum(shares)
    size_k <- ctr$unit_size_mean
    n_units <- ctr$density_per_ha * st$site_ha
    price_units <- P_base %*% (shares * size_k^ls_coef)          # sum_t share_t x price_t,sk
    cost_factor <- sum(shares * cti / vf)                        # type-indexed m2 gross floor area per m2 living area
    # Revenue excludes VAT (new dwellings are sold incl. 21%, the hedonic price of existing homes
    # has none); on top of the construction sum come the additional costs (fees, levies, interest)
    # and, in the sensitivity run only, the developer's margin (all from cfg, after RuimteScanner).
    block <- data.table(
      site_id        = st$site_id,
      cluster_alt    = k,
      n_units_alt    = n_units,
      revenue_eur    = n_units * as.numeric(price_units) / (1 + cfg$vat_rate),
      cost_construction_eur = n_units * size_k * cost_factor * st$bouw_kental,
      cost_land_eur  = st$loc_grondprod_eur_ha * st$site_ha,
      cost_demolition_eur = st$demolition_cost_eur)
    block[, cost_additional_eur := cfg$additional_costs_share * cost_construction_eur]
    block[, cost_margin_eur     := cfg$developer_margin * (cost_construction_eur + cost_additional_eur)]
    block[, rv_eur := revenue_eur - cost_construction_eur - cost_additional_eur - cost_margin_eur -
                      cost_land_eur - cost_demolition_eur]
    # Residual value per hectare (the regressor of stage 1 and the basis of the inclusive value).
    # Revenue and construction scale with the project area, so per hectare of that area they no
    # longer depend on site size; land costs are a per-hectare grid value; demolition is the same
    # for every option and is spread over the area of the original buildings, the rule that the
    # unchanged sites follow too.
    block[, rv_ha_eur := (revenue_eur - cost_construction_eur - cost_additional_eur - cost_margin_eur) / st$site_ha -
                         st$loc_grondprod_eur_ha - cost_demolition_eur / st$site_ha_oorspr]
    # sensitivity: the same with the RuimteScanner margin (cfg$developer_margin_sens) over
    # construction plus additional costs (06 variant 'margin7')
    block[, rv_ha_eur_margin := rv_ha_eur - (cfg$developer_margin_sens - cfg$developer_margin) *
                                (cost_construction_eur + cost_additional_eur) / st$site_ha]
    # land production sensitivity (RV variants only, no separate cost columns)
    block[, rv_eur_grond_low  := rv_eur + cost_land_eur - st$loc_grondprod_eur_ha_low  * st$site_ha]
    block[, rv_eur_grond_high := rv_eur + cost_land_eur - st$loc_grondprod_eur_ha_high * st$site_ha]
    # choice indicator: 1 if this alternative k equals the cluster actually built on the site
    block[, ca := as.integer(!is.na(st$cluster_real) & st$cluster_real == k)]
    block
  })
  # Stack the K blocks into one long table; setkey sorts it by (site_id, cluster_alt) and
  # marks those columns as the key, so later scripts can join on it fast.
  long <- rbindlist(blocks)
  setkey(long, site_id, cluster_alt)

  list(long = long, sites = st, centroids = cl$centroids)
}

## ---------------------------------------------------------------------------
# Runner: executes only when the script is run as a standalone program (sys.nframe() == 0
# means "not called from inside a function or source()") or when a caller explicitly sets
# run_05 <- TRUE. Sourcing this file just for build_alternatives() does not trigger it.
# It reads the sites (03) and clusters (04), builds the table, logs checks, and saves.
if (sys.nframe() == 0L || isTRUE(get0("run_05", ifnotfound = FALSE))) {
  s  <- readRDS(cfg$file_sites_rds)
  cl <- readRDS(cfg$file_clusters_rds)
  alt <- build_alternatives(s, cl)

  rd_log("Long table: %s rows (%s sites x %d alternatives)",
         format(nrow(alt$long), big.mark = ","), format(nrow(alt$sites), big.mark = ","), nrow(alt$centroids))
  rd_log("RV (mln Eur, median per alternative, all sites):")
  # Grouped aggregation (by = cluster_alt): median RV and the share of sites with positive
  # RV, computed per cluster alternative. Console check only, nothing is stored.
  print(alt$long[, .(rv_mln_med = median(rv_eur, na.rm = TRUE) / 1e6,
                     rv_pos_pct = 100 * mean(rv_eur > 0, na.rm = TRUE)), by = cluster_alt])
  # sanity: does the realized site pick the highest-RV alternative more often than chance (1/K)?
  # Join the long table to the realized sites, then per site (by = site_id) find which
  # alternative has the highest RV and compare it with the cluster actually built there.
  real <- alt$sites[!is.na(cluster_real), .(site_id, cluster_real)]
  chosen <- alt$long[real, on = "site_id"][!is.na(rv_eur),
                     .(best = cluster_alt[which.max(rv_eur)], cluster_real = cluster_real[1]), by = site_id]
  rd_log("Realized sites where chosen cluster = highest-RV alternative: %.1f%% (chance: %.1f%%)",
         100 * chosen[, mean(best == cluster_real)], 100 / nrow(alt$centroids))

  saveRDS(alt, cfg$file_alt_rds, compress = FALSE)
  rd_log("Written: %s", cfg$file_alt_rds)
}
