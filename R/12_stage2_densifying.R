# 12_stage2_densifying.R — stage 2 with densifying redevelopment as the only event (ObjectVision/RSopen#869).
#
# RuimteScanner (RSopen) uses the stage-2 logit of 07 as the probability that a cadastral parcel with
# dwellings is redeveloped: spec base for buurten with OAD >= cfg$oad_min, rural below. It models the
# one-for-one replacement of dwellings separately (ObjectVision/RSopen#859), so it needs the probability
# of redevelopment WITH a net gain in dwellings; until now it scaled the base probability by a fixed
# share. This step estimates that probability directly, with the terms of base and rural, so that RSopen
# reads the CSV without conversion.
#
# Event: an SN site where more dwellings were built than stood there before (n_units_new >
# n_units_res_inc). The plus side of the export holds dwellings only (checked 29-10: no SN site in the
# stage-2 samples has a new non-residential object), so this is a net gain in dwellings. SN sites
# without rows in the new-construction table count as no gain; the log reports how many.
#
# Specs per zone (base = OAD >= cfg$oad_min, rural = below, each with the inclusive value of 07):
#   base, rural              07 re-estimated, y = every SN site (check: equal to the 07 CSV)
#   <zone>_verdichtend       y = SN site with net gain; SN sites without gain stay in the risk set as y = 0
#   <zone>_verdichtend_excl  as above, with the SN sites without gain left out (does y = 0 for them matter?)
#   <zone>_verdichtend_w     as <zone>_verdichtend, weighted by the dwellings on the site before
#                            (n_units_res_inc). RSopen releases all dwellings of a parcel at once; with these
#                            weights the fitted probabilities reproduce the number of dwellings on densified
#                            sites (sum of n * p = sum of n * y, the score equation of the constant) instead
#                            of the number of densified sites.
#   <zone>_verdichtend_zondervol  as <zone>_verdichtend without the price volatility (vol_dlnp), which
#                            RSopen cannot fill in; the constant then absorbs the volatility term.
#
# Output: R_werk/stage2_specs_verdichtend<suffix>_<area>_<date>.csv (columns as the 07 CSV) and
# R_werk/stage2_verdichtend<suffix>_<area>_<date>.md (coefficients side by side, implied probabilities).

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "07_stage2_logit.R"))   # build_stage2_input, stage2_samples, fit_stage2

# Length of the observation window in years, for the annual probabilities: the stock at risk is the stock
# that stood at the start of the window (cfg$incumbent_built_before), the window ends at the BAG file date.
window_years <- function() as.numeric(as.IDate(cfg$bag_date, format = "%Y%m%d") -
                                      as.IDate(sprintf("%d-01-01", cfg$incumbent_built_before))) / 365.25

# The two zone samples of 07 (base and rural, same rows and inclusive values) with the net-gain flag.
densifying_samples <- function(uni, s) {
  core <- stage2_samples(uni)$core
  core[s$new, on = "site_id", n_units_new := i.n_units_new]
  rd_log("SN sites without rows in the new-construction table (count as no gain): %s",
         format(core[y == TRUE & is.na(n_units_new), .N], big.mark = ","))
  core[is.na(n_units_new), n_units_new := 0L]
  core[, `:=`(sn = y, gain = y & n_units_new > n_units_res_inc)]
  # rural as in 07: the inclusive value of the rural stage-1 scope, sites without one drop out
  rural <- copy(core[oad < cfg$oad_min])
  if ("iv_rural" %in% names(rural)) rural[, iv := iv_rural]
  list(base = core[oad >= cfg$oad_min], rural = rural[!is.na(iv)])
}

# Fitted probabilities of one spec, summarised against the dwellings on the sites: mean probability over
# the window and per year (constant hazard), and the dwellings released per year by the model (all
# dwellings of a site at once) next to those observed on densified sites.
implied <- function(f, d, years) {
  p <- predict(f$m, type = "response")
  stopifnot(length(p) == nrow(d), !anyNA(p))
  n <- d$n_units_res_inc
  data.table(spec = f$ct$spec[1], sites = nrow(d), events = sum(d$y), dw_events = sum(n[d$y]),
             p_window = mean(p), p_year = mean(1 - (1 - p)^(1 / years)),
             dw_year_model = sum(n * p) / years, dw_year_events = sum(n[d$y]) / years,
             dw_year_gain = sum(n[d$gain]) / years)
}

fit_zone <- function(d, zone) {
  dg <- copy(d)[, y := gain]
  list(fit_stage2(stage2_f_base, d, zone),
       fit_stage2(stage2_f_base, dg, paste0(zone, "_verdichtend")),
       fit_stage2(stage2_f_base, dg[!(sn & !gain)], paste0(zone, "_verdichtend_excl")),
       fit_stage2(stage2_f_base, dg, paste0(zone, "_verdichtend_w"), weights = ~n_units_res_inc),
       # RSopen cannot fill in the price volatility; without the term the constant absorbs its mean
       fit_stage2(update(stage2_f_base, . ~ . - vol_dlnp), dg, paste0(zone, "_verdichtend_zondervol")))
}

# Distribution of the terms over all sites of a zone sample, with the fitted probabilities of the given
# specs; RSopen sets these against the same statistics over its parcels. Numeric terms: mean, p10,
# median, p90; categorical terms: share of the sites per level.
term_distribution <- function(d, fits, zone, years) {
  num <- list(iv = d$iv, acq_ha = d$acq_ha, ln_site_ha = d$ln_site_ha, site_ha = d$site_ha_oorspr,
              p_owner_occupier_buurt = d$p_owner_occupier_buurt, p_socialhousing_buurt = d$p_socialhousing_buurt,
              vol_dlnp = d$vol_dlnp, dwellings_on_site = d$n_units_res_inc)
  for (f in fits) {
    p <- predict(f$m, type = "response")
    num[[paste0("p_window_", f$ct$spec[1])]] <- p
    num[[paste0("p_year_", f$ct$spec[1])]]   <- 1 - (1 - p)^(1 / years)
  }
  stats <- rbindlist(lapply(names(num), function(v) {
    x <- as.numeric(num[[v]]); q <- quantile(x, c(.1, .5, .9), names = FALSE)
    data.table(zone = zone, variable = v, level = "", mean = mean(x), p10 = q[1], median = q[2], p90 = q[3])
  }))
  shares <- rbind(data.table(zone = zone, variable = "isprotectheritagearea", level = "TRUE", share = mean(d$isprotectheritagearea)),
                  d[, .(share = .N / nrow(d)), keyby = .(level = as.character(bouwperiode_inc))][
                    , .(zone = zone, variable = "bouwperiode_inc", level, share)])
  rbind(stats, shares, fill = TRUE)
}

# Site area against the footprint of the buildings that form the site, by class of dwellings on the site, so
# that RSopen can approximate our site from the building footprints per cell. Footprint: the sum of the BAG
# building outlines of the site (site_sum_footprint_oorspr; for SN sites the demolished buildings, matching
# site_size_oorspr). Ratio = site area / footprint; footprint per dwelling in m2.
footprint_table <- function(d, zone) {
  d <- d[, .(site_m2 = site_ha_oorspr * 1e4, fp_m2 = site_sum_footprint_oorspr, n = n_units_res_inc)]
  n_missing <- d[!(is.finite(fp_m2) & fp_m2 > 0), .N]
  rd_log("Zone %s: %s sites without a footprint left out of the footprint table", zone, format(n_missing, big.mark = ","))
  d <- d[is.finite(fp_m2) & fp_m2 > 0]
  d[, class := as.character(cut(n, unname(cfg$footprint_dwelling_classes), labels = names(cfg$footprint_dwelling_classes)[-1]))]
  q <- function(v, p) quantile(v, p, names = FALSE)
  stat <- function(g, lbl) g[, .(zone = zone, dwellings_on_site = lbl, sites = .N, share_sites = .N / nrow(d), share_dwellings = sum(n) / d[, sum(n)],
                                 ratio_mean = mean(site_m2 / fp_m2), ratio_p10 = q(site_m2 / fp_m2, .1), ratio_median = q(site_m2 / fp_m2, .5),
                                 ratio_p90 = q(site_m2 / fp_m2, .9), ratio_of_sums = sum(site_m2) / sum(fp_m2),
                                 fp_per_dw_mean = mean(fp_m2 / n), fp_per_dw_p10 = q(fp_m2 / n, .1), fp_per_dw_median = q(fp_m2 / n, .5),
                                 fp_per_dw_p90 = q(fp_m2 / n, .9), site_m2_median = q(site_m2, .5), fp_m2_median = q(fp_m2, .5))]
  rbind(stat(d, "all"), rbindlist(lapply(names(cfg$footprint_dwelling_classes)[-1], function(k) stat(d[class == k], k))))
}

# Markdown: coefficients (estimate and z) of the specs of one zone side by side, plus sample sizes.
coef_table <- function(fits) {
  long <- rbindlist(lapply(fits, `[[`, "ct"))
  long[, cell := sprintf("%.4f (%.1f)", estimate, z)]
  specs <- unique(long$spec)
  w <- dcast(long, term ~ spec, value.var = "cell")[match(unique(long$term), term)]
  for (sp in specs) set(w, which(is.na(w[[sp]])), sp, "")   # term not in that spec
  row <- function(lbl, v) sprintf("| %s | %s |", lbl, paste(v, collapse = " | "))
  c(row("term", specs), row("---", rep("---", length(specs))),
    vapply(seq_len(nrow(w)), function(i) row(w$term[i], unlist(w[i, ..specs])), character(1)),
    row("sites", format(vapply(fits, function(f) as.numeric(f$m$nobs), numeric(1)), big.mark = ",")),
    row("event sites", format(vapply(fits, function(f) as.numeric(f$ct$n_y1[1]), numeric(1)), big.mark = ",")),
    row("McFadden R2", sprintf("%.3f", vapply(fits, function(f) r2(f$m, "pr2"), numeric(1)))))
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_12", ifnotfound = FALSE))) {
  alt <- readRDS(cfg$file_alt_rds)
  s   <- readRDS(cfg$file_sites_rds)
  s1  <- readRDS(cfg$file_stage1_rds)
  zones <- densifying_samples(build_stage2_input(alt, s, s1), s)
  years <- window_years()

  fits <- list(); imp <- list(); share <- list(); vol <- list(); dist <- list(); fp <- list()
  for (zone in names(zones)) {
    d <- zones[[zone]]
    rd_log("Zone %s: %s sites, %s SN sites of which %s with net gain; dwellings on SN sites %s, on gain sites %s",
           zone, format(nrow(d), big.mark = ","), format(d[, sum(sn)], big.mark = ","), format(d[, sum(gain)], big.mark = ","),
           format(d[sn == TRUE, sum(n_units_res_inc)], big.mark = ","), format(d[gain == TRUE, sum(n_units_res_inc)], big.mark = ","))
    fits[[zone]] <- fit_zone(d, zone)
    dg <- copy(d)[, y := gain]
    samples <- list(d, dg, dg[!(sn & !gain)], dg, dg)
    imp[[zone]] <- rbindlist(Map(implied, fits[[zone]], samples, years))
    share[[zone]] <- d[sn == TRUE, sum(n_units_res_inc[gain]) / sum(n_units_res_inc)]
    # sample mean of the volatility and what the term adds to the log-odds at that mean, next to the
    # shift of the constant when the term is dropped
    ct_v <- fits[[zone]][[2]]$ct; ct_0 <- fits[[zone]][[5]]$ct
    vol[[zone]] <- data.table(zone = zone, mean_vol = d[, mean(vol_dlnp)],
                              coef_vol = ct_v[term == "vol_dlnp", estimate],
                              term_at_mean = ct_v[term == "vol_dlnp", estimate] * d[, mean(vol_dlnp)],
                              const_shift = ct_0[term == "(Intercept)", estimate] - ct_v[term == "(Intercept)", estimate])
    dist[[zone]] <- term_distribution(d, fits[[zone]][c(1, 5)], zone, years)   # old spec and _zondervol
    fp[[zone]] <- footprint_table(d, zone)
  }
  dist_all <- rbindlist(dist)
  fp_all <- rbindlist(fp)
  out_fp <- file.path(cfg$dir_work, sprintf("stage2_verdichtend_voetafdruk%s_%s_%s.csv", cfg$sample_suffix, cfg$area, cfg$bag_date))
  fwrite(fp_all, out_fp, sep = ";")
  out_dist <- file.path(cfg$dir_work, sprintf("stage2_verdichtend_termverdeling%s_%s_%s.csv", cfg$sample_suffix, cfg$area, cfg$bag_date))
  fwrite(dist_all, out_dist, sep = ";")
  # Contribution of each term to the log-odds of _zondervol at the sample mean (coefficient x mean, for the
  # dummies x share); the sum is the mean linear predictor. RSopen can compute the same over its parcels.
  contrib <- rbindlist(lapply(names(zones), function(zn) {   # not 'z': that is a column of ct
    ct <- fits[[zn]][[5]]$ct; dz <- dist_all[zone == zn]
    m <- c(setNames(dz[is.na(share), mean], dz[is.na(share), variable]),
           setNames(dz[variable == "isprotectheritagearea", share], "isprotectheritageareaTRUE"),
           setNames(dz[variable == "bouwperiode_inc", share], paste0("bouwperiode_inc", dz[variable == "bouwperiode_inc", level])),
           "(Intercept)" = 1)
    ct[, .(zone = zn, spec, term, estimate, mean_x = unname(m[term]), contribution = estimate * unname(m[term]))]
  }))
  # stage-1 coefficients behind the inclusive value of each zone (06: own stage-1 scope per zone)
  b1 <- rbindlist(lapply(names(zones), function(z) {
    b <- if (!is.null(s1$scope[[z]]$coef)) s1$scope[[z]]$coef else s1$coef
    data.table(zone = z, term = names(b), estimate = unname(b))
  }))
  vol_all <- rbindlist(vol)
  print(vol_all)

  specs <- rbindlist(lapply(unlist(fits, recursive = FALSE), `[[`, "ct"))
  # check: base and rural must reproduce the 07 CSV
  f07 <- file.path(cfg$dir_work, sprintf("stage2_specs%s_%s_%s.csv", cfg$sample_suffix, cfg$area, cfg$bag_date))
  if (file.exists(f07)) {
    old <- fread(f07)[spec %chin% names(zones)]
    chk <- merge(old, specs, by = c("spec", "term"), suffixes = c("_07", "_12"))
    rd_log("Check against 07 (base, rural): %d of %d terms matched, max |diff| estimate %.1e, se %.1e, n equal: %s",
           nrow(chk), nrow(old), chk[, max(abs(estimate_07 - estimate_12))], chk[, max(abs(se_cluster_07 - se_cluster_12))],
           chk[, all(n_07 == n_12 & n_y1_07 == n_y1_12)])
  }
  out_csv <- file.path(cfg$dir_work, sprintf("stage2_specs_verdichtend%s_%s_%s.csv", cfg$sample_suffix, cfg$area, cfg$bag_date))
  fwrite(specs, out_csv, sep = ";")

  imp_all <- rbindlist(imp)
  print(imp_all[, .(spec, sites, events, dw_events, p_window = round(100 * p_window, 3), p_year = round(100 * p_year, 4),
                    dw_year_model = round(dw_year_model), dw_year_events = round(dw_year_events), dw_year_gain = round(dw_year_gain))])
  fmt <- function(v) format(round(v), big.mark = ",", trim = TRUE)
  imp_rows <- imp_all[, sprintf("| %s | %s | %s | %s | %.3f | %.4f | %s | %s | %s |", spec, format(sites, big.mark = ","),
                                format(events, big.mark = ","), format(dw_events, big.mark = ","), 100 * p_window, 100 * p_year,
                                fmt(dw_year_model), fmt(dw_year_events), fmt(dw_year_gain))]
  # Both zones together: the previous approach (base or rural probability times the share of the dwellings on
  # SN sites that stood on densified sites) and the densifying specs, against the observed dwellings per year.
  tot <- function(sp) imp_all[spec %chin% sp, sum(dw_year_model)]
  prev <- sum(vapply(names(zones), function(z) imp_all[spec == z, dw_year_model] * share[[z]], numeric(1)))
  obs  <- sum(vapply(names(zones), function(z) imp_all[spec == z, dw_year_gain], numeric(1)))
  tot_lines <- c(sprintf("- previous approach (base/rural probability x share above): %s", fmt(prev)),
                 sprintf("- %s: %s", paste(paste0(names(zones), "_verdichtend"), collapse = " + "), fmt(tot(paste0(names(zones), "_verdichtend")))),
                 sprintf("- %s: %s", paste(paste0(names(zones), "_verdichtend_w"), collapse = " + "), fmt(tot(paste0(names(zones), "_verdichtend_w")))),
                 sprintf("- observed, dwellings before on densified sites: %s", fmt(obs)))
  rd_log("Dwellings per year, both zones: previous approach %s, _verdichtend %s, _verdichtend_w %s, observed %s",
         fmt(prev), fmt(tot(paste0(names(zones), "_verdichtend"))), fmt(tot(paste0(names(zones), "_verdichtend_w"))), fmt(obs))
  md <- c(sprintf("# Stage 2, densifying redevelopment only (RSopen #869): %s, BAG %s, sample %s", cfg$area, cfg$bag_date, cfg$stage1_sample), "",
          "Event in the *_verdichtend specs: an SN site with more new dwellings than dwellings before. In _verdichtend the SN sites",
          "without gain stay in the sample as y = 0, in _excl they are left out, _w is _verdichtend weighted by the dwellings on the site.",
          "Cells: estimate (z), SEs clustered on gemeente.", "",
          unlist(lapply(names(fits), function(z) c(sprintf("## Coefficients, %s", z), "", coef_table(fits[[z]]), ""))),
          "## Implied probabilities and dwellings", "",
          sprintf(paste("Window %.2f years (January %d to the BAG date). Annual probability per site 1 - (1 - p)^(1/window), averaged",
                        "over the sites. Dwellings released by the model: sum over sites of dwellings before x p, per year. Observed:",
                        "dwellings before on the event sites of the spec, and on the densified sites, per year."), years, cfg$incumbent_built_before), "",
          "| spec | sites | event sites | dwellings on event sites | mean P window (%) | mean P per year (%) | dwellings/yr, model | dwellings/yr on event sites | dwellings/yr on densified sites |",
          "|---|---|---|---|---|---|---|---|---|", imp_rows, "",
          sprintf("Share of the dwellings on SN sites that stood on densified sites: %s.",
                  paste(sprintf("%s %.1f%%", names(share), 100 * unlist(share)), collapse = ", ")), "",
          "Dwellings released per year, both zones:", "", tot_lines, "",
          "## Price volatility (vol_dlnp) in the densifying specs", "",
          "Sample mean, coefficient in _verdichtend, the term at the mean (coefficient x mean), and the change of the constant in _zondervol.", "",
          "| zone | mean vol_dlnp | coefficient | term at the mean | constant _zondervol minus _verdichtend |", "|---|---|---|---|---|",
          vol_all[, sprintf("| %s | %.5f | %.4f | %.4f | %.4f |", zone, mean_vol, coef_vol, term_at_mean, const_shift)], "",
          "## Distribution of the terms over all sites of the sample", "",
          "iv: inclusive value (logsum over the development alternatives of stage 1, utility units); acq_ha: acquisition cost of the",
          "buildings on the site in M EUR (price level 2023) per hectare of the site of the original buildings; site_ha: that area in ha;",
          "p_window/p_year: fitted probability over the window and per year.", "",
          "| zone | variable | mean | p10 | median | p90 |", "|---|---|---|---|---|---|",
          dist_all[is.na(share), sprintf("| %s | %s | %s | %s | %s | %s |", zone, variable,
                                         signif(mean, 4), signif(p10, 4), signif(median, 4), signif(p90, 4))], "",
          "| zone | variable | level | share of sites |", "|---|---|---|---|",
          dist_all[!is.na(share), sprintf("| %s | %s | %s | %.4f |", zone, variable, level, share)], "",
          "## Contribution of each term to the log-odds of _zondervol at the sample mean", "",
          "Coefficient x sample mean (dummies: x share of the sites); the sum is the mean linear predictor.", "",
          "| zone | term | estimate | mean | contribution |", "|---|---|---|---|---|",
          contrib[, sprintf("| %s | %s | %.4f | %s | %.4f |", zone, term, estimate, signif(mean_x, 4), contribution)],
          contrib[, .(s = sum(contribution)), by = zone][, sprintf("| %s | sum | | | %.4f |", zone, s)], "",
          "## Site area against building footprint", "",
          "Ratio = site area / sum of the building outlines on the site; footprint per dwelling in m2; by dwellings on the site.", "",
          "| zone | dwellings on site | sites | share of sites | share of dwellings | ratio mean | p10 | median | p90 | ratio of sums | footprint/dwelling mean | p10 | median | p90 | site m2 median | footprint m2 median |",
          "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|",
          fp_all[, sprintf("| %s | %s | %s | %.3f | %.3f | %.2f | %.2f | %.2f | %.2f | %.2f | %.0f | %.0f | %.0f | %.0f | %.0f | %.0f |", zone, dwellings_on_site,
                           format(sites, big.mark = ","), share_sites, share_dwellings, ratio_mean, ratio_p10, ratio_median, ratio_p90, ratio_of_sums,
                           fp_per_dw_mean, fp_per_dw_p10, fp_per_dw_median, fp_per_dw_p90, site_m2_median, fp_m2_median)], "",
          "## Stage-1 coefficients behind iv", "",
          "iv = log(sum over the alternatives k of exp(rv_ha x RV per ha of alternative k + ASC_k)), ASC of alternative 1 = 0.", "",
          "| zone | term | estimate |", "|---|---|---|", b1[, sprintf("| %s | %s | %.4f |", zone, term, estimate)])
  out_md <- file.path(cfg$dir_work, sprintf("stage2_verdichtend%s_%s_%s.md", cfg$sample_suffix, cfg$area, cfg$bag_date))
  writeLines(md, out_md, useBytes = TRUE)
  rd_log("Written: %s + %s + %s + %s", out_csv, out_md, out_dist, out_fp)
}
