# 07_stage2_logit.R — step 5 (issue #16): stage-2 binomial logit ("does
# redevelopment happen at all"), one row per site in the stock.
#
# Universe & outcome (decisions 28-07):
#   y = 1 : SN sites (sloop-nieuwbouw realized 2012-2026) WITH incumbent rows;
#           BBG-route SN sites (demolition before the window) have no reconstructable
#           acquisition and fall outside the estimation (they are in stage 1).
#   y = 0 : potential sites from the unchanged housing stock (#17, prefix Onv;
#           mmd's from before the naming round 27-07 use OnvS — both recognized).
#   out   : Sloop/Onttrekking without follow-up (pipeline; robustness: as y=1),
#           Transformatie (out of scope), pure new construction (no incumbent).
#   scope : urban area via OAD >= cfg$oad_min (decision 28-07 evening, replaces the
#           22 agglomerations); sensitivities OAD >= 1500 and all of NL.
#
# Estimation: fixest::feglm (logit) with standard errors CLUSTERED on gemeente —
# redevelopment decisions within a gemeente share policy/market shocks, so
# i.i.d. SEs are too small. Clustering does not change the coefficients.
#
# Explanatory variables (theory + frictions):
#   iv [+], acq_mln [-], p_owner_occupier_buurt [- holdout], p_socialhousing_buurt [?],
#   isprotectheritagearea [-], is_natura2000 [-], vol_dlnp [- real options],
#   bouwperiode_inc (mode building year of incumbent, ref va2002) [older -> +, depreciation]
#
# Specs (all in the export CSV):
#   base       OAD>=1000, full covariates
#   no_bp      base without the bouwperiode control (isolates what building year does with heritage)
#   urban1500  OAD>=1500 (strongly urban)
#   nl         no OAD filter
#   size       base + ln(site_ha) (comparability control for site formation 10m/20m)
#   winsor     base with iv/acq winsorized p1/p99 (mega-site tails; separation warning)
#   vol_muni   volatility with gemeente granularity primary (instead of grid5km-first)
#   demol_start S sites (demolition without follow-up = irreversible start) count as y=1;
#              Onttrekking is excluded here too (mostly administrative, and the
#              78k O sites gave a flat likelihood / quasi-separation)
#   excl2012   base without sites suspected of 2012 double counting (#26: new construction
#              registered in 2012 with building year <= 2010 = presumably Woningregister
#              administration, not real redevelopment)
#   bbg_imput  base + the BBG-route SN sites (no demolition rows in the window) as y=1,
#              with IMPUTED acquisition (median acq/ha of observed SN sites x
#              site_ha); without the bouwperiode control (incumbent unknown for those sites)
#
# Output: cfg$file_stage2_rds + R_werk/stage2_specs<suffix>_<area>_<date>.csv
# (term;estimate;se_cluster;z;spec;n;n_y1) + AMEs of the core variables (base).

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))
source(file.path(.rd_script_dir, "02_load_perobject.R"))   # for building_period_term()
suppressPackageStartupMessages(library(fixest))

build_stage2_input <- function(alt, s, s1) {
  st <- alt$sites
  # BBG-route SN sites (has_incumbent == FALSE): only for the imputation spec
  uni <- st[has_incumbent == TRUE | site_id %like% "^SN_"]
  uni[, prefix := sub("_.*$", "", site_id)]
  uni[prefix == "OnvS", prefix := "Onv"]                       # old naming (mmd < 28-07)
  uni <- uni[prefix %chin% c("SN", "Onv", "S", "O")]           # TMmin out of scope
  uni[, y := prefix == "SN"]
  uni[, pipeline := prefix %chin% c("S", "O")]
  uni[, bbg_sn := has_incumbent == FALSE]
  uni[bbg_sn == TRUE, `:=`(acq_cost_total_eur = NA_real_, demolition_cost_eur = NA_real_)]  # 05 set 0; here truly unknown
  rd_log("BBG-route SN sites (acquisition unknown, imputation spec only): %s",
         format(uni[bbg_sn == TRUE, .N], big.mark = ","))

  uni[s1$iv, on = "site_id", iv := i.iv]
  uni[, acq_mln := acq_cost_total_eur / 1e6]
  uni[, ln_site_ha := log(site_ha)]

  # bouwperiode of incumbent (mode building year per site; unknown as its own level — discard nothing)
  uni[s$incumbent, on = "site_id", mode_building_year := i.mode_building_year]
  uni[, bouwperiode_inc := factor(fifelse(is.na(mode_building_year), "bp_onbekend", building_period_term(mode_building_year)))]
  uni[, bouwperiode_inc := relevel(bouwperiode_inc, "bouwperiode_va2002")]

  # volatility: grid5km cell from RD coordinates + gemeente variant (2024 codes: matches
  # only where the GM code has been unchanged since our 2012 classification)
  vol_g  <- fread(cfg$file_vol("grid5km"))
  vol_gm <- fread(cfg$file_vol("gemeente_code"))
  uni[, cel := paste0(x_coord %/% cfg$vol_cel_m, "_", y_coord %/% cfg$vol_cel_m)]
  uni[vol_g,  on = .(cel = regio),           vol_grid_ := i.vol_dlnp]
  uni[vol_gm, on = .(gemeente_code = regio), vol_gem_  := i.vol_dlnp]
  uni[, vol_dlnp     := fcoalesce(vol_grid_, vol_gem_)]   # base: finest granularity first
  uni[, vol_dlnp_gem := fcoalesce(vol_gem_, vol_grid_)]   # variant: gemeente primary
  rd_log("Volatility: grid5km %.1f%%, with gemeente fallback %.1f%%",
         100 * uni[, mean(!is.na(vol_grid_))], 100 * uni[, mean(!is.na(vol_dlnp))])

  # 2012 double-counting flag (#26) sits on the plus side (sites_new)
  uni[s$new, on = "site_id", n_flag_2012 := i.n_flag_2012]
  uni[is.na(n_flag_2012), n_flag_2012 := 0L]
  uni[]
}

estimate_stage2 <- function(uni) {
  f_base <- y ~ iv + acq_mln + p_owner_occupier_buurt + p_socialhousing_buurt +
                isprotectheritagearea + is_natura2000 + vol_dlnp + bouwperiode_inc
  vars <- setdiff(all.vars(f_base), "bouwperiode_inc")
  w    <- function(v) { q <- quantile(v, c(.01, .99), na.rm = TRUE); pmin(pmax(v, q[1]), q[2]) }

  # sites without building year: quasi-separation (nearly no events on the bp_onbekend dummy
  # keeps the likelihood spinning flat) -> out of the estimation; in the urban sample this is ~5 sites.
  # BBG-SN sites (by definition without an incumbent building year) stay in for the imputation spec.
  n_unknown <- uni[bbg_sn == FALSE & bouwperiode_inc == "bp_onbekend", .N]
  uni       <- uni[bbg_sn == TRUE | bouwperiode_inc != "bp_onbekend"]
  rd_log("Sites with unknown building year removed from the estimation: %s", format(n_unknown, big.mark = ","))

  core <- uni[pipeline == FALSE & bbg_sn == FALSE]
  core <- core[complete.cases(core[, ..vars]) & !is.na(oad)]
  urban_subset <- function(d, oad_min) d[oad >= oad_min]

  fit1 <- function(fml, d, label) {
    d <- copy(d)[, bouwperiode_inc := droplevels(bouwperiode_inc)]
    m <- feglm(fml, data = d, family = binomial(), cluster = ~gemeente_code, glm.iter = 100)
    if (!isTRUE(m$convStatus)) rd_log("    NB: '%s' did not converge — check separation", label)
    ct <- as.data.table(summary(m)$coeftable, keep.rownames = "term")
    setnames(ct, c("term", "estimate", "se_cluster", "z", "p"))
    ct[, `:=`(spec = label, n = m$nobs, n_y1 = d[, sum(y)])]
    rd_log("  %-9s n = %s (y=1 %s): iv %+.2f (z %.1f), acq %+.3f (z %.1f), vol %+.2f (z %.1f)",
           label, format(m$nobs, big.mark = ","), format(d[, sum(y)], big.mark = ","),
           ct[term == "iv", estimate], ct[term == "iv", z],
           ct[term == "acq_mln", estimate], ct[term == "acq_mln", z],
           ct[term %like% "^vol", estimate], ct[term %like% "^vol", z])
    list(m = m, ct = ct)
  }

  rd_log("Specs (SE clustered on gemeente):")
  base    <- urban_subset(core, cfg$oad_min)
  f_no_bp <- update(f_base, . ~ . - bouwperiode_inc)

  # BBG imputation sample: acquisition = median acq/ha of the observed SN sites x site_ha
  acq_rate <- base[y == TRUE, median(acq_mln / site_ha)]
  bbg <- uni[bbg_sn == TRUE & !is.na(oad) & oad >= cfg$oad_min]
  bbg[, acq_mln := acq_rate * site_ha]
  bbg <- bbg[complete.cases(bbg[, ..vars])]
  rd_log("BBG imputation: %s sites added as y=1 (acq = %.2f M/ha x site_ha)", format(nrow(bbg), big.mark = ","), acq_rate)

  fits <- list(
    base      = fit1(f_base, base, "base"),
    no_bp     = fit1(f_no_bp, base, "no_bp"),
    urban1500 = fit1(f_base, urban_subset(core, 1500L), "urban1500"),
    nl        = fit1(f_base, core, "nl"),
    size      = fit1(update(f_base, . ~ . + ln_site_ha), base, "size"),
    winsor    = fit1(f_base, copy(base)[, `:=`(iv = w(iv), acq_mln = w(acq_mln))], "winsor"),
    vol_muni  = fit1(update(f_base, . ~ . - vol_dlnp + vol_dlnp_gem), base, "vol_muni"),
    demol_start = fit1(f_base, { d <- uni[prefix != "O" & bbg_sn == FALSE]
                                 d <- d[complete.cases(d[, ..vars]) & !is.na(oad) & oad >= cfg$oad_min]
                                 d[, y := prefix != "Onv"]; d }, "demol_start"),
    excl2012  = fit1(f_base, base[n_flag_2012 == 0L], "excl2012"),
    bbg_imput = fit1(f_no_bp, rbind(base, bbg), "bbg_imput"))

  # AMEs (base): average marginal effect on P(redevelopment), logit: mean(p(1-p)) x beta
  p <- predict(fits$base$m, type = "response")
  scale_factor <- mean(p * (1 - p))
  ame <- fits$base$ct[term %chin% c("iv", "acq_mln", "vol_dlnp", "p_owner_occupier_buurt"),
                      .(term, ame = scale_factor * estimate)]
  list(fits = fits, ame = ame, basis_n = nrow(base))
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_07", ifnotfound = FALSE))) {
  alt <- readRDS(cfg$file_alt_rds)
  s   <- readRDS(cfg$file_sites_rds)
  s1  <- readRDS(cfg$file_stage1_rds)
  uni <- build_stage2_input(alt, s, s1)
  r   <- estimate_stage2(uni)

  rd_log("Main model (base, OAD >= %d) — full table:", cfg$oad_min)
  print(r$fits$base$ct[, .(term, estimate = round(estimate, 4), se_cluster = round(se_cluster, 4), z = round(z, 1))])
  rd_log("McFadden R2 (base): %.3f", r2(r$fits$base$m, "pr2"))
  rd_log("AMEs (percentage points on P(redevelopment), base):")
  print(r$ame[, .(term, ame_pp = round(100 * ame, 4))])

  specs <- rbindlist(lapply(r$fits, `[[`, "ct"))
  out_file <- file.path(cfg$dir_work, sprintf("stage2_specs%s_%s_%s.csv", cfg$sample_suffix, cfg$area, cfg$bag_date))
  fwrite(specs, out_file, sep = ";")
  saveRDS(list(specs = specs, ame = r$ame, coef = coef(r$fits$base$m), vcov = vcov(r$fits$base$m)),
          cfg$file_stage2_rds, compress = FALSE)
  rd_log("Written: %s + %s", cfg$file_stage2_rds, out_file)
}
