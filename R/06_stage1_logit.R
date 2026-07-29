# 06_stage1_logit.R — steps 3+4 (issue #16): stage-1 conditional logit + inclusive value.
#
# Step 3: conditional logit over the K cluster alternatives, on the realized sites of
# the stage-1 sample (cfg$stage1_sample, default SN). Choice indicator ca explained by the
# residual value per alternative; alternative-specific constants (ASCs, reference =
# cluster 1) capture average unobserved attractiveness (zoning-plan capacity,
# market segment) — without ASCs, high-density nearly always wins on RV level (see STATUS 28-07).
# Estimation via survival::clogit (system library): with exactly 1 chosen alternative per
# stratum the Cox partial likelihood is exactly the conditional-logit likelihood (McFadden).
# Theory (Brueckner-Wheaton): coefficient on RV positive.
#
# Robustness: same model without the multi-project sites (n_doc > cfg$multiproj_n_doc and
# months_spread > cfg$multiproj_months: spatially clumped permits, 28-07 probe ~7%).
#
# Step 4: inclusive value per site, for ALL sites (including undeveloped):
#   IV_s = log( sum_k exp( b_rv * RV_sk + ASC_k ) )   [logsumexp, numerically stable]
# Sites where some alternatives have RV=NA (0.11%) get the logsum over the
# available alternatives; sites with no alternative at all -> NA.
#
# Output: cfg$file_stage1_rds = list(coef, vcov, coef_rob, n_sites, n_sites_rob, iv).

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))
suppressPackageStartupMessages(library(survival))

estimate_stage1 <- function(alt, s) {
  lg <- alt$long
  st <- alt$sites
  K  <- nrow(alt$centroids)

  # -- estimation sample: realized menu sites with complete RV over all K ------
  real_ids <- st[!is.na(cluster_real), site_id]
  est <- lg[site_id %chin% real_ids]
  complete <- est[, .(ok = !anyNA(rv_eur)), by = site_id][ok == TRUE, site_id]
  est <- est[site_id %chin% complete]
  est[, rv_mln := rv_eur / 1e6]
  est[, alt_f  := factor(cluster_alt)]
  # urban-area delineation via OAD (cfg$oad_min; decision 28-07 — replaces 22 agglomerations)
  est[st, on = "site_id", oad := i.oad]
  n_before <- uniqueN(est$site_id)
  est <- est[!is.na(oad) & oad >= cfg$oad_min]
  rd_log("Stage 1: %s of %s SN sites within OAD >= %d; %s dropped for incomplete RV",
         format(uniqueN(est$site_id), big.mark = ","), format(n_before, big.mark = ","),
         cfg$oad_min, format(length(real_ids) - length(complete), big.mark = ","))

  fit <- clogit(ca ~ rv_mln + alt_f + strata(site_id), data = est)

  # -- robustness: exclude multi-project sites ---------------------------------
  est[s$new, on = "site_id", `:=`(n_doc = i.n_doc, months_spread = i.months_spread)]
  est[, multiproj := n_doc > cfg$multiproj_n_doc & months_spread > cfg$multiproj_months]
  est_rob <- est[multiproj == FALSE | is.na(multiproj)]
  fit_rob <- clogit(ca ~ rv_mln + alt_f + strata(site_id), data = est_rob)
  rd_log("Robustness: %s multi-project sites excluded",
         format(uniqueN(est[multiproj == TRUE, site_id]), big.mark = ","))

  # -- step 4: inclusive value for all sites (logsumexp) -----------------------
  b   <- coef(fit)
  asc <- c(0, b[paste0("alt_f", 2:K)])
  lg[, V := b[["rv_mln"]] * rv_eur / 1e6 + asc[cluster_alt]]
  suppressWarnings(lg[, Vmax := max(V, na.rm = TRUE), by = site_id])   # -Inf if all NA
  lg[, e_ := exp(V - Vmax)]
  iv <- lg[, .(Vmax = Vmax[1], som = sum(e_, na.rm = TRUE), n_alt_ok = sum(!is.na(V))), by = site_id]
  iv[, iv := fifelse(n_alt_ok > 0L, Vmax + log(som), NA_real_)]
  iv[, c("Vmax", "som") := NULL]
  lg[, c("V", "Vmax", "e_") := NULL]

  list(fit = fit, fit_rob = fit_rob, iv = iv,
       n_sites = length(complete), n_sites_rob = uniqueN(est_rob$site_id))
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_06", ifnotfound = FALSE))) {
  alt <- readRDS(cfg$file_alt_rds)
  s   <- readRDS(cfg$file_sites_rds)
  r   <- estimate_stage1(alt, s)

  rd_log("Stage-1 conditional logit (main model):")
  print(summary(r$fit))
  rd_log("Robustness (without multi-project sites) — rv_mln coefficient:")
  print(cbind(coef = coef(r$fit_rob), se = sqrt(diag(vcov(r$fit_rob))))["rv_mln", , drop = FALSE])
  rd_log("Inclusive value: %s sites, median %.3f (realized) vs %.3f (unchanged universe)",
         format(nrow(r$iv), big.mark = ","),
         r$iv[site_id %chin% alt$sites[!is.na(cluster_real), site_id], median(iv, na.rm = TRUE)],
         r$iv[!site_id %chin% alt$sites[!is.na(cluster_real), site_id], median(iv, na.rm = TRUE)])

  saveRDS(list(coef = coef(r$fit), vcov = vcov(r$fit), coef_rob = coef(r$fit_rob),
               vcov_rob = vcov(r$fit_rob), n_sites = r$n_sites, n_sites_rob = r$n_sites_rob,
               iv = r$iv),
          cfg$file_stage1_rds, compress = FALSE)
  rd_log("Written: %s", cfg$file_stage1_rds)
}
