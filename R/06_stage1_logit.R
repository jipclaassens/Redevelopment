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
# RV enters PER HECTARE of site area (rv_ha, M EUR/ha; decision 25-09). The residual value
# for the whole site grows with site size, and large sites get apartments because more
# dwellings fit: with site size x type controls the per-site RV coefficient turned negative
# (-0.010, z -3.0), whereas the per-hectare coefficient stays positive with or without them
# (z 23 to 26). Per hectare is also how the paper defines it (gross profit per unit of land).
#
# Comparisons, saved next to the main model:
#   rob   : without the multi-project sites (n_doc > cfg$multiproj_n_doc and months_spread >
#           cfg$multiproj_months: spatially clumped permits, 28-07 probe ~7%)
#   total : the previous specification, RV for the whole site (rv_mln)
#   cov   : + site characteristics x type (ln site area, social-housing share, protected
#           townscape, building period of the incumbent); better stage-1 fit, but kept out of the
#           main line: the same variables are stage-2 frictions, and in both stages their stage-2
#           coefficients depend on the arbitrary reference type (test 25-09)
#   margin: sensitivity with the RuimteScanner developer margin (cfg$developer_margin_sens, 7%)
#           in the residual value; the main model has no margin (decision 25-09)
#
# Step 4: inclusive value per site, for ALL sites (including undeveloped):
#   IV_s = log( sum_k exp( b_rv * RV_ha_sk + ASC_k ) )   [logsumexp, numerically stable]
# plus iv_total, iv_cov and iv_margin from the comparison models (stage-2 robustness specs).
# Sites where some alternatives have RV=NA (0.11%) get the logsum over the
# available alternatives; sites with no alternative at all -> NA.
#
# Output: cfg$file_stage1_rds = list(coef, vcov, coef_rob, coef_total, coef_cov, coef_margin,
# loglik, n_sites, n_sites_rob, n_cov, iv, scope).

# Bootstrap: recover this script's own directory (from Rscript's --file argument, or the
# current working directory when sourced interactively) so 00_config.R is found no matter
# from where R was started.
if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))
suppressPackageStartupMessages(library(survival))

# Site characteristics for the 'cov' comparison model, one row per site (all sites, so its
# inclusive value can be computed everywhere). Building period in five broad groups, so each
# type gets four instead of eight period coefficients; unknown (BBG-route sites without an
# incumbent) is its own group. cov_ok marks sites where every characteristic is observed.
stage1_covariates <- function(st, s) {
  X <- st[, .(site_id, ln_site_ha = log(site_ha), p_social = p_socialhousing_buurt,
              protected = as.numeric(isprotectheritagearea))]
  X[s$incumbent, on = "site_id", myear := i.mode_building_year]
  X[, bp := fcase(is.na(myear), "unknown", myear <= 1950L, "pre1951", myear <= 1973L, "1951_1973",
                  myear <= 2001L, "1974_2001", default = "2002plus")]
  X[, `:=`(bp_1951_1973 = as.numeric(bp == "1951_1973"), bp_1974_2001 = as.numeric(bp == "1974_2001"),
           bp_2002plus  = as.numeric(bp == "2002plus"),  bp_unknown   = as.numeric(bp == "unknown"))]
  X[, c("myear", "bp") := NULL]
  ok <- complete.cases(X[, setdiff(names(X), "site_id"), with = FALSE])
  X[, cov_ok := ok & is.finite(ln_site_ha)]
  X[]
}
stage1_cov_names <- c("ln_site_ha", "p_social", "protected", "bp_1951_1973", "bp_1974_2001",
                      "bp_2002plus", "bp_unknown")

# Inclusive value of the main (per-hectare) specification from a coefficient vector; used for
# the scope-matched inclusive values (nl, urban1500, rural), so that each stage-2 scope spec
# values the options with the stage-1 parameters of its own scope.
iv_from_coef <- function(b, lg, st, K) {
  rvha_row <- lg$rv_ha_eur / 1e6   # per-hectare residual value from 05 (M EUR/ha)
  rvha_row[!is.finite(rvha_row)] <- NA_real_
  logsum_by_site(lg$site_id, b[["rv_ha"]] * rvha_row + c(0, b[paste0("alt_f", 2:K)])[lg$cluster_alt])
}

# Inclusive value per site from a deterministic utility V per (site, alternative) row:
# logsumexp by site, subtracting the per-site maximum first so nothing overflows. Sites
# where some alternatives have V = NA get the sum over the available ones; none -> NA.
logsum_by_site <- function(site_id, V) {
  dt <- data.table(site_id = site_id, V = V)
  suppressWarnings(dt[, Vmax := max(V, na.rm = TRUE), by = site_id])   # -Inf if all NA
  dt[, e_ := exp(V - Vmax)]
  iv <- dt[, .(Vmax = Vmax[1], som = sum(e_, na.rm = TRUE), n_alt_ok = sum(!is.na(V))), by = site_id]
  iv[, iv := fifelse(n_alt_ok > 0L, Vmax + log(som), NA_real_)]
  iv[, .(site_id, iv, n_alt_ok)]
}

# Inputs: alt = list from 05_alternatives.R with $long (one row per site x cluster
# alternative, incl. rv_eur and choice indicator ca), $sites (one row per site) and
# $centroids (the K cluster definitions). s = list from 03_sites.R; only s$new
# (per-site permit aggregates of the realized redevelopment) is used here.
# oad_min/oad_max override the scope (default: the base urban scope); compute_iv = FALSE
# skips the inclusive-value step (used for the scope variants in the runner below).
estimate_stage1 <- function(alt, s, oad_min = cfg$oad_min, oad_max = Inf, compute_iv = TRUE) {
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
  # (address density) and site area into est itself (i. prefix = column from the joined
  # table). Then only sites in sufficiently urban areas are kept; n_before exists just for the
  # log line. rv_ha is the residual value per hectare (M EUR/ha), the regressor of the main model.
  est[st, on = "site_id", `:=`(oad = i.oad, site_ha = i.site_ha, gemeente_code = i.gemeente_code)]
  n_before <- uniqueN(est$site_id)
  est <- est[!is.na(oad) & oad >= oad_min & oad < oad_max & site_ha > 0]
  est[, rv_ha := rv_ha_eur / 1e6]   # per-hectare residual value from 05 (M EUR/ha)
  n_est <- uniqueN(est$site_id)
  rd_log("Stage 1: %s of %s SN sites within OAD [%s, %s); %s dropped for incomplete RV",
         format(n_est, big.mark = ","), format(n_before, big.mark = ","),
         format(oad_min, big.mark = ","),
         if (is.finite(oad_max)) format(oad_max, big.mark = ",") else "Inf",
         format(length(real_ids) - length(complete), big.mark = ","))

  # The conditional logit itself: strata(site_id) makes every site its own choice set, with
  # exactly one chosen alternative (ca = 1) against the other K-1 rows of that site.
  # cluster(gemeente_code): robust standard errors clustered on gemeente, as in stage 2
  # (zoning is set per municipality, so choices within a gemeente are not independent). The
  # coefficients are unaffected; vcov() then returns the clustered covariance matrix.
  fit <- clogit(ca ~ rv_ha + alt_f + strata(site_id) + cluster(gemeente_code), data = est, method = "efron")
  n_est <- fit$nevent   # sites actually used (a site without gemeente code would drop out)
  # Comparison on the same sites: the previous specification, RV for the whole site.
  fit_total <- clogit(ca ~ rv_mln + alt_f + strata(site_id) + cluster(gemeente_code), data = est, method = "efron")
  # Sensitivity on the same sites: the residual value with the developer margin (base run only).
  fit_margin <- NULL
  if (compute_iv && "rv_ha_eur_margin" %in% names(est)) {
    est[, rv_ha_margin := rv_ha_eur_margin / 1e6]
    fit_margin <- clogit(ca ~ rv_ha_margin + alt_f + strata(site_id) + cluster(gemeente_code), data = est, method = "efron")
  }

  # -- robustness: exclude multi-project sites ---------------------------------
  # Update join from s$new: pull per site the number of permit documents (n_doc) and how many
  # months those permits span. Sites exceeding BOTH thresholds are flagged multi-project
  # (likely several unrelated projects merged into one site). The robustness fit drops them;
  # sites without a match in s$new keep NA and are retained via is.na(multiproj).
  est[s$new, on = "site_id", `:=`(n_doc = i.n_doc, months_spread = i.months_spread)]
  est[, multiproj := n_doc > cfg$multiproj_n_doc & months_spread > cfg$multiproj_months]
  est_rob <- est[multiproj == FALSE | is.na(multiproj)]
  fit_rob <- clogit(ca ~ rv_ha + alt_f + strata(site_id) + cluster(gemeente_code), data = est_rob, method = "efron")
  rd_log("Robustness: %s multi-project sites excluded",
         format(uniqueN(est[multiproj == TRUE, site_id]), big.mark = ","))

  # -- comparison: + site characteristics x type (base run only) ---------------
  # A site characteristic is constant across a site's alternatives, so in a conditional logit
  # it only enters through an interaction with the alternative: one coefficient per
  # non-reference type (x_k columns, k = 2..K). Only for the base run (compute_iv = TRUE).
  fit_cov <- NULL; X <- NULL; n_cov <- NA_integer_
  if (compute_iv) {
    X <- stage1_covariates(st, s)
    est_cov <- merge(est, X, by = "site_id")[cov_ok == TRUE]
    int_cols <- character(0)
    for (k in 2:K) for (cv in stage1_cov_names) {
      nm <- sprintf("%s_x%d", cv, k)
      est_cov[, (nm) := (cluster_alt == k) * get(cv)]
      int_cols <- c(int_cols, nm)
    }
    fit_cov <- clogit(as.formula(paste("ca ~ rv_ha + alt_f +", paste(int_cols, collapse = " + "),
                                       "+ strata(site_id) + cluster(gemeente_code)")), data = est_cov,
                      method = "efron")
    n_cov <- uniqueN(est_cov$site_id)
    rd_log("Comparison + site characteristics x type: %s sites, rv_ha %+.4f (z %.1f)",
           format(n_cov, big.mark = ","), coef(fit_cov)[["rv_ha"]],
           summary(fit_cov)$coefficients["rv_ha", "z"])
  }

  # -- step 4: inclusive value for all sites (logsumexp) -----------------------
  # Deterministic utility V per (site, alternative) from the MAIN fit: b_rv * RV_ha + ASC.
  # The reference alternative (cluster 1) gets ASC 0; asc_of(b)[cluster_alt] is vectorized
  # indexing, so each row picks the ASC belonging to its own alternative. lg is alt$long
  # itself (~9M rows), so the per-row vectors are built with match() instead of new columns.
  # The two comparison models get their own inclusive value (iv_total, iv_cov) for the
  # stage-2 robustness specs.
  iv <- NULL
  if (compute_iv) {
    asc_of <- function(b) c(0, b[paste0("alt_f", 2:K)])
    rvha_row <- lg$rv_ha_eur / 1e6   # per-hectare residual value from 05 (M EUR/ha)
    rvha_row[!is.finite(rvha_row)] <- NA_real_
    b  <- coef(fit)
    iv <- logsum_by_site(lg$site_id, b[["rv_ha"]] * rvha_row + asc_of(b)[lg$cluster_alt])
    bt <- coef(fit_total)
    iv_t <- logsum_by_site(lg$site_id, bt[["rv_mln"]] * lg$rv_eur / 1e6 + asc_of(bt)[lg$cluster_alt])
    # Site-characteristic part of V per site and type: X (sites x covariates) times the
    # coefficients of type k; Cm[cbind(row, type)] then picks the right cell for every lg row.
    bc <- coef(fit_cov)
    Xm <- as.matrix(X[, ..stage1_cov_names])
    Cm <- matrix(0, nrow(X), K)
    for (k in 2:K) Cm[, k] <- as.vector(Xm %*% bc[sprintf("%s_x%d", stage1_cov_names, k)])
    xi <- match(lg$site_id, X$site_id)
    iv_c <- logsum_by_site(lg$site_id, bc[["rv_ha"]] * rvha_row + asc_of(bc)[lg$cluster_alt] +
                                         Cm[cbind(xi, lg$cluster_alt)])
    iv_c[X, on = "site_id", ok_ := i.cov_ok]
    iv_c[ok_ == FALSE | is.na(ok_), iv := NA_real_]
    iv[iv_t, on = "site_id", iv_total := i.iv]
    iv[iv_c, on = "site_id", iv_cov := i.iv]
    if (!is.null(fit_margin)) {
      bm <- coef(fit_margin)
      rvm_row <- lg$rv_ha_eur_margin / 1e6
      rvm_row[!is.finite(rvm_row)] <- NA_real_
      iv_m <- logsum_by_site(lg$site_id, bm[["rv_ha_margin"]] * rvm_row + asc_of(bm)[lg$cluster_alt])
      iv[iv_m, on = "site_id", iv_margin := i.iv]
    }
  }

  list(fit = fit, fit_rob = fit_rob, fit_total = fit_total, fit_cov = fit_cov, fit_margin = fit_margin, iv = iv,
       n_sites = length(complete), n_est = n_est, n_sites_rob = uniqueN(est_rob$site_id), n_cov = n_cov)
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
  rd_log("Robustness (without multi-project sites), rv_ha coefficient:")
  print(cbind(coef = coef(r$fit_rob), se = sqrt(diag(vcov(r$fit_rob))))["rv_ha", , drop = FALSE])
  rd_log("Comparison, RV for the whole site (previous specification), rv_mln coefficient:")
  print(cbind(coef = coef(r$fit_total), se = sqrt(diag(vcov(r$fit_total))))["rv_mln", , drop = FALSE])
  if (!is.null(r$fit_margin)) {
    rd_log("Sensitivity, residual value with a %.0f%% developer margin, rv_ha_margin coefficient:", 100 * cfg$developer_margin_sens)
    print(cbind(coef = coef(r$fit_margin), se = sqrt(diag(vcov(r$fit_margin))))["rv_ha_margin", , drop = FALSE])
  }
  # Log line comparing the median IV of realized sites with that of the unchanged
  # (undeveloped) universe; the %chin% filter splits iv on membership of the realized set.
  rd_log("Inclusive value: %s sites, median %.3f (realized) vs %.3f (unchanged universe)",
         format(nrow(r$iv), big.mark = ","),
         r$iv[site_id %chin% alt$sites[!is.na(cluster_real), site_id], median(iv, na.rm = TRUE)],
         r$iv[!site_id %chin% alt$sites[!is.na(cluster_real), site_id], median(iv, na.rm = TRUE)])

  # Scope variants for the urban/rural table in 08 (coefficients only, no IV): all of NL,
  # strongly urban (OAD >= 1500) and rural (OAD < cfg$oad_min). The main fit above is the
  # base scope (OAD >= cfg$oad_min) and is added to the same list for the table.
  scope_def <- list(nl = c(0, Inf), urban1500 = c(1500, Inf), rural = c(0, cfg$oad_min))
  scope <- lapply(scope_def, function(b) {
    v <- estimate_stage1(alt, s, oad_min = b[1], oad_max = b[2], compute_iv = FALSE)
    list(coef = coef(v$fit), vcov = vcov(v$fit), n = v$n_est)
  })
  # Scope-matched inclusive values (iv_nl, iv_urban1500, iv_rural) for the stage-2 scope specs:
  # a rural site's options are valued with the rural stage-1 parameters, and so on. The
  # dynamic column name in (paste0(...)) := writes one new column per scope into r$iv.
  for (nm in names(scope)) {
    ivs <- iv_from_coef(scope[[nm]]$coef, alt$long, alt$sites, nrow(alt$centroids))
    r$iv[ivs, on = "site_id", (paste0("iv_", nm)) := i.iv]
  }
  scope$base <- list(coef = coef(r$fit), vcov = vcov(r$fit), n = r$n_est)

  # Persist coefficients, covariance matrices, sample sizes and the per-site IV table for
  # the downstream scripts (07_stage2_logit, 08_tables, 09_hazard read cfg$file_stage1_rds).
  saveRDS(list(coef = coef(r$fit), vcov = vcov(r$fit), coef_rob = coef(r$fit_rob),
               vcov_rob = vcov(r$fit_rob), coef_total = coef(r$fit_total), vcov_total = vcov(r$fit_total),
               coef_cov = coef(r$fit_cov), vcov_cov = vcov(r$fit_cov),
               coef_margin = if (!is.null(r$fit_margin)) coef(r$fit_margin),
               vcov_margin = if (!is.null(r$fit_margin)) vcov(r$fit_margin),
               loglik = c(main = r$fit$loglik[2], total = r$fit_total$loglik[2], cov = r$fit_cov$loglik[2],
                          margin = r$fit_margin$loglik[2]),
               n_sites = r$n_sites, n_est = r$n_est, n_sites_rob = r$n_sites_rob, n_cov = r$n_cov,
               iv = r$iv, scope = scope),
          cfg$file_stage1_rds, compress = FALSE)
  rd_log("Written: %s", cfg$file_stage1_rds)
}
