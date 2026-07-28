# 05_alternatieven.R — stap 2a-2c (issue #16): alternatieventabel ("long format") met
# opbrengst, kosten en residual value per (site, cluster-alternatief).
#
# 2a Opbrengst_sk : n_units_k x som_t( aandeel_t,k x prijs_t,sk ), met prijs via het
#                   hedonisch model exp(constant + som(coef x kenmerk)) per WP4.
#                   Omdat alleen lnsize van het cluster afhangt, wordt per (site, type) een
#                   basisprijs exp(lp_site) berekend en per cluster met size_k^coef_lnsize
#                   geschaald — een bulk-predict zonder loops over sites.
# 2b Kosten_sk    : grondproductie (loc_grondprod_eur_ha x site_ha, 2023-peil)
#                   + bouwkosten (BVO = unitgrootte/vormfactor x CBS-kental per landsdeel)
#                   + sloopkosten incumbent (uit 03_sites; k-invariant).
# 2c RV_sk        : Opbrengst_sk - Kosten_sk; keuze-indicator ca = 1 voor het k-means-cluster
#                   van de gerealiseerde site (= dichtstbijzijnde centroide in de
#                   gestandaardiseerde ruimte, per constructie van k-means).
#
# DEFAULTS bij open beslispunten (aanpasbaar via 00_config.R; zie ook issue #16):
#  - kenmerken nieuwe unit: grootte uit de cluster-centroide (zelfde voor alle typen binnen
#    het cluster; de clustering kent geen type-specifieke grootte); nrooms/lotsize/d_highrise
#    uit de regiogemiddelden (reg_<wp4>_*, dezelfde proxy-keuze als de incumbent-reconstructie);
#    d_maintgood = cfg$alt_d_maintgood (1: nieuwbouw verkeert in goede staat);
#    d_hoogte_onbekend = 0; bouwperiode = va2002 (referentie, coef 0); prijspeil trans_year_2023.
#  - typemix per cluster: centroide-aandelen genormaliseerd naar som 1.
#  - n_units continu (dichtheid_k x site_ha), geen afronding.
#  - bouwkosten: CBS 83673NED, kolom cfg$bouwkosten_kolom ('koop_eur_m2'); vormfactor
#    eengezins (0.76) voor de drie grondgebonden typen, meergezins (0.78) voor appartement
#    (hoogbouw 0.65 ongebruikt: clusters hebben geen hoogte-informatie).
#  - sloopkosten zijn k-invariant: vallen weg in de conditional logit (stage 1) maar tellen
#    door in de inclusive value en dus in stage 2. Puur-nieuwbouwsites (geen incumbent): 0.
#  - grondproductie-varianten _low/_high alleen als aparte RV-kolommen (sensitiviteit).
#
# Output: cfg$file_alt_rds = list(long = (site x K)-tabel, sites = site-tabel met
# stage-2-ingredienten (verwerving, sloop, fricties), centroids).
# NB: het cluster-menu en de ca-indicator volgen het stage-1-sample (cfg$stage1_sample,
# default 'sn'); de long-tabel zelf beslaat ALTIJD alle sites (de inclusive value van
# stap 4 is ook voor niet-ontwikkelde sites nodig).

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))
source(file.path(.rd_script_dir, "02_load_perobject.R"))   # voor lees_coefficienten/coef_van

maak_alternatieven <- function(s, cl, co = lees_coefficienten()) {
  st <- copy(s$attrs)
  st[, site_ha := site_size / 1e4]

  # incumbent-kant (verwerving/sloop/uitkomst); sites zonder incumbent-rijen = pure nieuwbouw
  st[s$incumbent, on = "site_id", `:=`(
    heeft_incumbent    = TRUE,
    was_redeveloped    = i.was_redeveloped,
    acq_cost_total_eur = i.acq_cost_total_eur,
    sloop_cost_eur     = i.sloop_cost_eur,
    n_units_res_inc    = i.n_units_res,
    floor_area_res_inc = i.floor_area_res_m2)]
  st[is.na(heeft_incumbent), `:=`(heeft_incumbent = FALSE, was_redeveloped = TRUE,
                                  acq_cost_total_eur = 0, sloop_cost_eur = 0)]

  # gerealiseerd cluster (k-means-assignment uit 04) = keuze-indicator straks
  st[cl$sites, on = "site_id", cluster_real := i.cluster]

  # bouwkosten-kental per site via landsdeel
  st[, bouw_kental := cfg$bouwkosten_2023[[cfg$bouwkosten_kolom]][match(landsdeel, cfg$bouwkosten_2023$landsdeel)]]

  onbruikbaar <- st[, !complete.cases(.SD),
                    .SDcols = c("site_size", "loc_tt_500k_2024_min", "loc_tt_ovknoop_2026_min",
                                "uai_2012", "loc_grondprod_eur_ha", "bouw_kental")]
  rd_log("Sites: %s totaal; %s (%.2f%%) missen een prijs-/kosteninput -> RV wordt NA",
         format(nrow(st), big.mark = ","), format(sum(onbruikbaar), big.mark = ","), 100 * mean(onbruikbaar))

  # -- 2a: basisprijs per (site, type): alles behalve de lnsize-term -------------
  ct <- function(term, t) coef_van(co, term, t)  # scalar
  P_base <- sapply(cfg$wp4_names, function(t)
    exp(ct("constant", t) +
        ct("lnlotsize", t)   * log(pmax(st[[paste0("reg_", t, "_lotsize")]], 1)) +
        ct("nrooms", t)      * st[[paste0("reg_", t, "_nrooms")]] +
        ct("d_maintgood", t) * cfg$alt_d_maintgood +
        ct("d_highrise", t)  * st[[paste0("reg_", t, "_d_highrise")]] +
        ct(paste0("trans_year_", cfg$prijspeil_jaar), t) +
        ct("lntt_500k_2024", t) * log(st$loc_tt_500k_2024_min) +
        ct("lntt_ovknoop", t)   * log(pmax(st$loc_tt_ovknoop_2026_min, cfg$ovknoop_floor)) +
        ct("uai_2012", t)       * st$uai_2012))
  ls_coef <- vapply(cfg$wp4_names, function(t) ct("lnsize", t), numeric(1))
  vf      <- unname(cfg$vormfactor[cfg$vormfactor_wp4[cfg$wp4_names]])

  # -- per cluster-alternatief een blok van de long-tabel ------------------------
  K <- nrow(cl$centroids)
  aandeel_cols <- paste0("aandeel_", cfg$wp4_names)
  blokken <- lapply(seq_len(K), function(k) {
    ctr    <- cl$centroids[cluster == k]
    shares <- as.numeric(ctr[, ..aandeel_cols]); shares <- shares / sum(shares)
    size_k <- ctr$unit_size_mean
    n_units <- ctr$dichtheid_per_ha * st$site_ha
    prijs_units <- P_base %*% (shares * size_k^ls_coef)          # som_t aandeel_t x prijs_t,sk
    bvo_factor  <- sum(shares / vf)                              # m2 BVO per m2 woonoppervlak, gewogen
    blok <- data.table(
      site_id        = st$site_id,
      cluster_alt    = k,
      n_units_alt    = n_units,
      revenue_eur    = n_units * as.numeric(prijs_units),
      cost_bouw_eur  = n_units * size_k * bvo_factor * st$bouw_kental,
      cost_grond_eur = st$loc_grondprod_eur_ha * st$site_ha,
      cost_sloop_eur = st$sloop_cost_eur)
    blok[, rv_eur := revenue_eur - cost_bouw_eur - cost_grond_eur - cost_sloop_eur]
    # sensitiviteit grondproductie (alleen RV-varianten, geen aparte kostenkolommen)
    blok[, rv_eur_grond_low  := rv_eur + cost_grond_eur - st$loc_grondprod_eur_ha_low  * st$site_ha]
    blok[, rv_eur_grond_high := rv_eur + cost_grond_eur - st$loc_grondprod_eur_ha_high * st$site_ha]
    blok[, ca := as.integer(!is.na(st$cluster_real) & st$cluster_real == k)]
    blok
  })
  long <- rbindlist(blokken)
  setkey(long, site_id, cluster_alt)

  list(long = long, sites = st, centroids = cl$centroids)
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_05", ifnotfound = FALSE))) {
  s  <- readRDS(cfg$file_sites_rds)
  cl <- readRDS(cfg$file_clusters_rds)
  alt <- maak_alternatieven(s, cl)

  rd_log("Long-tabel: %s rijen (%s sites x %d alternatieven)",
         format(nrow(alt$long), big.mark = ","), format(nrow(alt$sites), big.mark = ","), nrow(alt$centroids))
  rd_log("RV (mln Eur, mediaan per alternatief, alle sites):")
  print(alt$long[, .(rv_mln_med = median(rv_eur, na.rm = TRUE) / 1e6,
                     rv_pos_pct = 100 * mean(rv_eur > 0, na.rm = TRUE)), by = cluster_alt])
  # sanity: kiest de gerealiseerde site vaker het alternatief met de hoogste RV dan kans (1/K)?
  real <- alt$sites[!is.na(cluster_real), .(site_id, cluster_real)]
  gekozen <- alt$long[real, on = "site_id"][!is.na(rv_eur),
                      .(beste = cluster_alt[which.max(rv_eur)], cluster_real = cluster_real[1]), by = site_id]
  rd_log("Gerealiseerde sites waar gekozen cluster = hoogste-RV-alternatief: %.1f%% (kans: %.1f%%)",
         100 * gekozen[, mean(beste == cluster_real)], 100 / nrow(alt$centroids))

  saveRDS(alt, cfg$file_alt_rds, compress = FALSE)
  rd_log("Weggeschreven: %s", cfg$file_alt_rds)
}
