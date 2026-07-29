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

# Bootstrap: recover this script's own directory (from Rscript's --file argument, or the
# current working directory when sourced interactively) so 00_config.R is found no matter
# from where R was started.
if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))
suppressPackageStartupMessages(library(survival))

# Inputs: alt = list from 05_alternatives.R with $long (one row per site x cluster
# alternative, incl. rv_eur and choice indicator ca), $sites (one row per site) and
# $centroids (the K cluster definitions). s = list from 03_sites.R; only s$new
# (per-site permit aggregates of the realized redevelopment) is used here.
estimate_stage1 <- function(alt, s) {
  # Short handles; note data.tables are passed by reference, so lg IS alt$long (no copy).
  lg <- alt$long
  st <- alt$sites
  K  <- nrow(alt$centroids)

  # -- estimation sample: realized menu sites with complete RV over all K ------
  # cluster_real is only filled for sites where redevelopment actually happened, so real_ids
  # selects the realized sites. %chin% is data.table's fast %in% for character vectors.
  # The grouped aggregation (by = site_id) flags sites whose K alternatives ALL have a
  # non-missing residual value: the conditional logit needs a complete choice set per site.
  real_ids <- st[!is.na(cluster_real), site_id]
  est <- lg[site_id %chin% real_ids]
  complete <- est[, .(ok = !anyNA(rv_eur)), by = site_id][ok == TRUE, site_id]
  est <- est[site_id %chin% complete]
  # := adds columns in place, by reference (see README, data.table primer): RV rescaled to
  # millions of euros (readable coefficient size) and the alternative id as a factor, so
  # clogit turns it into K-1 dummy variables = the alternative-specific constants (ASCs).
  est[, rv_mln := rv_eur / 1e6]
  est[, alt_f  := factor(cluster_alt)]
  # urban-area delineation via OAD (cfg$oad_min; decision 28-07 — replaces 22 agglomerations)
  # Update join: each site_id of est is looked up in st and := copies the matched OAD
  # (address density) into est itself (i. prefix = column from the joined table). Then only
  # sites in sufficiently urban areas are kept; n_before exists just for the log line.
  est[st, on = "site_id", oad := i.oad]
  n_before <- uniqueN(est$site_id)
  est <- est[!is.na(oad) & oad >= cfg$oad_min]
  rd_log("Stage 1: %s of %s SN sites within OAD >= %d; %s dropped for incomplete RV",
         format(uniqueN(est$site_id), big.mark = ","), format(n_before, big.mark = ","),
         cfg$oad_min, format(length(real_ids) - length(complete), big.mark = ","))

  # The conditional logit itself: strata(site_id) makes every site its own choice set, with
  # exactly one chosen alternative (ca = 1) against the other K-1 rows of that site.
  fit <- clogit(ca ~ rv_mln + alt_f + strata(site_id), data = est)

  # -- robustness: exclude multi-project sites ---------------------------------
  # Update join from s$new: pull per site the number of permit documents (n_doc) and how many
  # months those permits span. Sites exceeding BOTH thresholds are flagged multi-project
  # (likely several unrelated projects merged into one site). The robustness fit drops them;
  # sites without a match in s$new keep NA and are retained via is.na(multiproj).
  est[s$new, on = "site_id", `:=`(n_doc = i.n_doc, months_spread = i.months_spread)]
  est[, multiproj := n_doc > cfg$multiproj_n_doc & months_spread > cfg$multiproj_months]
  est_rob <- est[multiproj == FALSE | is.na(multiproj)]
  fit_rob <- clogit(ca ~ rv_mln + alt_f + strata(site_id), data = est_rob)
  rd_log("Robustness: %s multi-project sites excluded",
         format(uniqueN(est[multiproj == TRUE, site_id]), big.mark = ","))

  # -- step 4: inclusive value for all sites (logsumexp) -----------------------
  # Deterministic utility V per (site, alternative) from the MAIN fit: b_rv * RV + ASC.
  # The reference alternative (cluster 1) gets ASC 0; asc[cluster_alt] is vectorized
  # indexing, so each row picks the ASC belonging to its own alternative.
  b   <- coef(fit)
  asc <- c(0, b[paste0("alt_f", 2:K)])
  lg[, V := b[["rv_mln"]] * rv_eur / 1e6 + asc[cluster_alt]]
  # Logsumexp trick: subtract the per-site maximum (grouped := by site_id) before exp() so
  # the largest term is exp(0) = 1 and nothing overflows; Vmax is added back inside the log
  # below. max() over an all-NA group returns -Inf plus a warning, hence suppressWarnings.
  suppressWarnings(lg[, Vmax := max(V, na.rm = TRUE), by = site_id])   # -Inf if all NA
  lg[, e_ := exp(V - Vmax)]
  # Grouped aggregation to one row per site; n_alt_ok counts alternatives with a usable V,
  # so IV falls back to the sum over available alternatives (NA only if none at all).
  # fifelse = data.table's fast vectorized if-else.
  iv <- lg[, .(Vmax = Vmax[1], som = sum(e_, na.rm = TRUE), n_alt_ok = sum(!is.na(V))), by = site_id]
  iv[, iv := fifelse(n_alt_ok > 0L, Vmax + log(som), NA_real_)]
  # Delete the helper columns again (":= NULL" removes a column by reference). For lg this
  # matters: lg is alt$long itself, so without this cleanup the caller's table would keep
  # the temporary V/Vmax/e_ columns.
  iv[, c("Vmax", "som") := NULL]
  lg[, c("V", "Vmax", "e_") := NULL]

  list(fit = fit, fit_rob = fit_rob, iv = iv,
       n_sites = length(complete), n_sites_rob = uniqueN(est_rob$site_id))
}

## ---------------------------------------------------------------------------
## Runner block: executes only when this file is run as a script (sys.nframe() == 0 means
## "not called from inside a function") or when run_all.R sets run_06 <- TRUE before
## sourcing. Plain source() from the console therefore only defines the function above.
if (sys.nframe() == 0L || isTRUE(get0("run_06", ifnotfound = FALSE))) {
  alt <- readRDS(cfg$file_alt_rds)
  s   <- readRDS(cfg$file_sites_rds)
  r   <- estimate_stage1(alt, s)

  rd_log("Stage-1 conditional logit (main model):")
  print(summary(r$fit))
  rd_log("Robustness (without multi-project sites) — rv_mln coefficient:")
  print(cbind(coef = coef(r$fit_rob), se = sqrt(diag(vcov(r$fit_rob))))["rv_mln", , drop = FALSE])
  # Log line comparing the median IV of realized sites with that of the unchanged
  # (undeveloped) universe; the %chin% filter splits iv on membership of the realized set.
  rd_log("Inclusive value: %s sites, median %.3f (realized) vs %.3f (unchanged universe)",
         format(nrow(r$iv), big.mark = ","),
         r$iv[site_id %chin% alt$sites[!is.na(cluster_real), site_id], median(iv, na.rm = TRUE)],
         r$iv[!site_id %chin% alt$sites[!is.na(cluster_real), site_id], median(iv, na.rm = TRUE)])

  # Persist coefficients, covariance matrices, sample sizes and the per-site IV table for
  # the downstream scripts (07_stage2_logit, 08_tables, 09_hazard read cfg$file_stage1_rds).
  saveRDS(list(coef = coef(r$fit), vcov = vcov(r$fit), coef_rob = coef(r$fit_rob),
               vcov_rob = vcov(r$fit_rob), n_sites = r$n_sites, n_sites_rob = r$n_sites_rob,
               iv = r$iv),
          cfg$file_stage1_rds, compress = FALSE)
  rd_log("Written: %s", cfg$file_stage1_rds)
}
