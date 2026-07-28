# 06_stage1_logit.R — stap 3+4 (issue #16): stage-1 conditional logit + inclusive value.
#
# Stap 3: conditional logit over de K cluster-alternatieven, op de gerealiseerde sites van
# het stage-1-sample (cfg$stage1_sample, default SN). Keuze-indicator ca verklaard uit de
# residual value per alternatief; alternative-specific constants (ASC's, referentie =
# cluster 1) vangen gemiddelde onbeobachtete aantrekkelijkheid (bestemmingsplanruimte,
# marktsegment) — zonder ASC's wint hoogdicht vrijwel altijd op RV-niveau (zie STATUS 28-07).
# Schatting via survival::clogit (system library): met precies 1 gekozen alternatief per
# stratum is de Cox-partial-likelihood exact de conditional-logit-likelihood (McFadden).
# Theorie (Brueckner-Wheaton): coefficient op RV positief.
#
# Robuustheid: zelfde model zonder de multi-projectsites (n_doc > cfg$multiproj_n_doc en
# mnd_spread > cfg$multiproj_mnd: ruimtelijk samengeklonterde vergunningen, 28-07-probe ~7%).
#
# Stap 4: inclusive value per site, voor ALLE sites (ook niet-ontwikkeld):
#   IV_s = log( som_k exp( b_rv * RV_sk + ASC_k ) )   [logsumexp, numeriek stabiel]
# Sites waar een deel van de alternatieven RV=NA heeft (0,11%) krijgen de logsum over de
# beschikbare alternatieven; sites zonder enkel alternatief -> NA.
#
# Output: cfg$file_stage1_rds = list(coef, vcov, coef_rob, n_sites, n_sites_rob, iv).

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))
suppressPackageStartupMessages(library(survival))

schat_stage1 <- function(alt, s) {
  lg <- alt$long
  st <- alt$sites
  K  <- nrow(alt$centroids)

  # -- estimatiesample: gerealiseerde menu-sites met complete RV over alle K ----
  real_ids <- st[!is.na(cluster_real), site_id]
  est <- lg[site_id %chin% real_ids]
  compleet <- est[, .(ok = !anyNA(rv_eur)), by = site_id][ok == TRUE, site_id]
  est <- est[site_id %chin% compleet]
  est[, rv_mln := rv_eur / 1e6]
  est[, alt_f  := factor(cluster_alt)]
  rd_log("Stage 1: %s sites x %d alternatieven (%s rijen); %s gerealiseerde sites vielen af (incomplete RV)",
         format(length(compleet), big.mark = ","), K, format(nrow(est), big.mark = ","),
         format(length(real_ids) - length(compleet), big.mark = ","))

  fit <- clogit(ca ~ rv_mln + alt_f + strata(site_id), data = est)

  # -- robuustheid: multi-projectsites eruit -----------------------------------
  est[s$nieuw, on = "site_id", `:=`(n_doc = i.n_doc, mnd_spread = i.mnd_spread)]
  est[, multiproj := n_doc > cfg$multiproj_n_doc & mnd_spread > cfg$multiproj_mnd]
  est_rob <- est[multiproj == FALSE | is.na(multiproj)]
  fit_rob <- clogit(ca ~ rv_mln + alt_f + strata(site_id), data = est_rob)
  rd_log("Robuustheid: %s multi-projectsites uitgesloten",
         format(uniqueN(est[multiproj == TRUE, site_id]), big.mark = ","))

  # -- stap 4: inclusive value voor alle sites (logsumexp) ---------------------
  b   <- coef(fit)
  asc <- c(0, b[paste0("alt_f", 2:K)])
  lg[, V := b[["rv_mln"]] * rv_eur / 1e6 + asc[cluster_alt]]
  suppressWarnings(lg[, Vmax := max(V, na.rm = TRUE), by = site_id])   # -Inf als alles NA
  lg[, e_ := exp(V - Vmax)]
  iv <- lg[, .(Vmax = Vmax[1], som = sum(e_, na.rm = TRUE), n_alt_ok = sum(!is.na(V))), by = site_id]
  iv[, iv := fifelse(n_alt_ok > 0L, Vmax + log(som), NA_real_)]
  iv[, c("Vmax", "som") := NULL]
  lg[, c("V", "Vmax", "e_") := NULL]

  list(fit = fit, fit_rob = fit_rob, iv = iv,
       n_sites = length(compleet), n_sites_rob = uniqueN(est_rob$site_id))
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_06", ifnotfound = FALSE))) {
  alt <- readRDS(cfg$file_alt_rds)
  s   <- readRDS(cfg$file_sites_rds)
  r   <- schat_stage1(alt, s)

  rd_log("Stage-1 conditional logit (hoofdmodel):")
  print(summary(r$fit))
  rd_log("Robuustheid (zonder multi-projectsites) — rv_mln-coefficient:")
  print(cbind(coef = coef(r$fit_rob), se = sqrt(diag(vcov(r$fit_rob))))["rv_mln", , drop = FALSE])
  rd_log("Inclusive value: %s sites, mediaan %.3f (gerealiseerd) vs %.3f (onveranderd universum)",
         format(nrow(r$iv), big.mark = ","),
         r$iv[site_id %chin% alt$sites[!is.na(cluster_real), site_id], median(iv, na.rm = TRUE)],
         r$iv[!site_id %chin% alt$sites[!is.na(cluster_real), site_id], median(iv, na.rm = TRUE)])

  saveRDS(list(coef = coef(r$fit), vcov = vcov(r$fit), coef_rob = coef(r$fit_rob),
               vcov_rob = vcov(r$fit_rob), n_sites = r$n_sites, n_sites_rob = r$n_sites_rob,
               iv = r$iv),
          cfg$file_stage1_rds, compress = FALSE)
  rd_log("Weggeschreven: %s", cfg$file_stage1_rds)
}
