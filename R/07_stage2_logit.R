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
#   iv [+], acq_ha [-], ln_site_ha (control), p_owner_occupier_buurt [- holdout],
#   p_socialhousing_buurt [?], isprotectheritagearea [-], vol_dlnp [- real options],
#   bouwperiode_inc (mode building year of incumbent, ref va2002, i.e. 2002-2011 since stock built from
#   cfg$incumbent_built_before on is dropped in 03) [older -> +, depreciation]
#
# Per hectare (decision 25-09): the inclusive value comes from the per-hectare stage-1 model
# and acquisition costs enter per hectare of site area (acq_ha, M EUR/ha), so both sides of
# the redevelopment condition are values per unit of land; ln(site area) is a control. With
# amounts for the whole site, both terms largely measured site size (see 06). Head-to-head on
# the same sites: McFadden 0.156 (per site) vs 0.252 (per hectare).
#
# Natura 2000 is NOT in the base specification (decision 30-07). Development there is not
# forbidden but requires a nitrogen assessment, so it was included as a permitting friction;
# empirically the indicator is uninformative (urban: +0.69, z 0.8; rural: only 384 of
# 603,727 sites, 26 events). Dropping it leaves every other coefficient unchanged to four
# decimals (iv 10.0212 either way). Spec 'n2000' adds it back as a check.
#
# glm.tol: fixest's default convergence tolerance is tighter than base R's glm() and is
# never formally reached on some subsamples, even though the estimates are bit-identical
# across 50/100/300 iterations (checked 30-07 on excl2012 and rural: iv 9.970848 and
# deviance 64934.1476 in all three). 1e-6 reports convergence with identical coefficients.
#
# Specs (all in the export CSV):
#   base       OAD>=1000, full covariates
#   no_bp      base without the bouwperiode control (isolates what building year does with heritage)
#   urban1500  OAD>=1500 (strongly urban)                  } each with the inclusive value of its
#   nl         no OAD filter                                } own stage-1 scope (iv_urban1500,
#   rural      OAD<1000 (complement of base)                } iv_nl, iv_rural; see 06)
#   no_size    base without ln(site_ha)
#   winsor     base with iv/acq_ha winsorized p1/p99 (tails of very small or very large sites)
#   vol_muni   volatility with gemeente granularity primary (instead of grid5km-first)
#   nonres     separate model: redeveloped sites where only non-residential buildings stood, against
#              potential sites from the unchanged non-residential stock (OnvNW; export from 25-09)
#   (demol_start: out since 25-09, its S sites are formed with a different rule; see below)
#   demol_start S sites (demolition without follow-up = irreversible start) count as y=1;
#              Onttrekking is excluded here too (mostly administrative, and the
#              78k O sites gave a flat likelihood / quasi-separation)
#   excl2012   base without sites suspected of 2012 double counting (#26: new construction
#              registered in 2012 with building year <= 2010 = presumably Woningregister
#              administration, not real redevelopment)
#   n2000      base + the Natura 2000 indicator (see the note above)
#   bbg_imput  base + the BBG-route SN sites (no demolition rows in the window) as y=1,
#              with IMPUTED acquisition (median acq/ha of observed SN sites);
#              without the bouwperiode control (incumbent unknown for those sites)
#   margin7    base with the inclusive value of the stage-1 model whose residual value includes the
#              RuimteScanner developer margin (7%, cfg$developer_margin_sens); main model: no margin
#   stage1_cov base with the inclusive value of the stage-1 model with site characteristics x type
#   total      the previous specification: inclusive value and acquisition costs for the whole
#              site, no ln(site_ha); reproduces the 30-07 base results (comparison)
#
# Output: cfg$file_stage2_rds + R_werk/stage2_specs<suffix>_<area>_<date>.csv
# (term;estimate;se_cluster;z;spec;n;n_y1) + AMEs of the core variables (base).

# Bootstrap: locate the directory this script lives in, so that config and helpers can be
# sourced by absolute path no matter where R was started (Rscript call or interactive use).
if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))
source(file.path(.rd_script_dir, "02_load_perobject.R"))   # for building_period_term()
suppressPackageStartupMessages(library(fixest))

# Build the estimation table: one row per site with the outcome y and all regressors
# (stage-1 investment value, acquisition cost, neighbourhood shares, volatility, bouwperiode).
build_stage2_input <- function(alt, s, s1) {
  st <- alt$sites
  # Universe: sites that had a standing building (incumbent), plus SN sites without one
  # (the BBG route). st[...] is data.table row filtering; %like% is a regex match on site_id.
  # BBG-route SN sites (has_incumbent == FALSE): only for the imputation spec
  uni <- st[has_incumbent == TRUE | site_id %like% "^SN_"]
  # The site_id prefix encodes the mutation type (SN = sloop-nieuwbouw, Onv = unchanged
  # stock, S = sloop only, O = onttrekking). := creates columns "by reference", i.e. it
  # writes into uni itself without copying; see README, data.table primer. y is the
  # outcome; pipeline marks demolition/onttrekking without follow-up construction.
  uni[, prefix := sub("_.*$", "", site_id)]
  uni[prefix == "OnvS", prefix := "Onv"]                       # old naming (mmd < 28-07)
  # OnvNW = potential sites from the unchanged NON-residential stock (export from 25-09), the
  # comparison group of the separate non-residential model
  uni <- uni[prefix %chin% c("SN", "Onv", "S", "O", "OnvNW")]  # TMmin out of scope
  uni[, y := prefix == "SN"]
  # Main analysis = replacement of housing: sites that had at least one dwelling (decision 25-09).
  # Redeveloped sites with only non-residential buildings before have no counterpart in the
  # unchanged residential stock; they form the separate non-residential model with OnvNW.
  uni[, inc_has_dwellings := has_incumbent & !is.na(n_units_res_inc) & n_units_res_inc > 0]
  uni[, pipeline := prefix %chin% c("S", "O")]
  uni[, bbg_sn := has_incumbent == FALSE]
  # For BBG-route sites the demolition predates the window, so these costs cannot be
  # reconstructed: the filtered := overwrites the upstream zeros with an honest NA.
  uni[bbg_sn == TRUE, `:=`(acq_cost_total_eur = NA_real_, demolition_cost_eur = NA_real_)]  # 05 set 0; here truly unknown
  rd_log("BBG-route SN sites (acquisition unknown, imputation spec only): %s",
         format(uni[bbg_sn == TRUE, .N], big.mark = ","))

  # Update join: each site_id of uni is looked up in the stage-1 table s1$iv, and := writes
  # the matched investment value into uni itself (the i. prefix = "column from the joined
  # table"); see README, data.table primer. Then two derived regressors: acquisition cost
  # in mln euro and log site size (the latter only used in the size spec).
  uni[s1$iv, on = "site_id", iv := i.iv]
  # Inclusive values of the comparison models and the scope-matched ones (06); older stage-1
  # files do not have them, hence the check per column.
  for (v in intersect(c("iv_total", "iv_cov", "iv_margin", "iv_nl", "iv_urban1500", "iv_rural"), names(s1$iv)))
    uni[, (v) := s1$iv[[v]][match(site_id, s1$iv$site_id)]]
  uni[, acq_mln := acq_cost_total_eur / 1e6]
  # Per hectare of the area of the ORIGINAL buildings (site_ha_oorspr, from 05): for redeveloped
  # sites the outline of the project also covers the new buildings, so the project area is partly
  # an outcome (review 25-09). Same for the size control.
  uni[, acq_ha := acq_mln / site_ha_oorspr]     # M EUR per hectare
  uni[, ln_site_ha := log(site_ha_oorspr)]

  # bouwperiode of incumbent (mode building year per site; unknown as its own level — discard nothing)
  # Update join pulls the modal building year from the incumbent aggregates; fifelse maps
  # missing years to their own factor level "bp_onbekend" instead of dropping those sites,
  # and relevel() makes the newest period (va2002) the reference category of the dummy set.
  uni[s$incumbent, on = "site_id", mode_building_year := i.mode_building_year]
  uni[, bouwperiode_inc := factor(fifelse(is.na(mode_building_year), "bp_onbekend", building_period_term(mode_building_year)))]
  uni[, bouwperiode_inc := relevel(bouwperiode_inc, "bouwperiode_va2002")]

  # volatility: grid5km cell from RD coordinates + gemeente variant (2024 codes: matches
  # only where the GM code has been unchanged since our 2012 classification)
  vol_g  <- fread(cfg$file_vol("grid5km"))
  vol_gm <- fread(cfg$file_vol("gemeente_code"))
  # Assign each site to a 5km grid cell: %/% is integer division of the RD coordinates,
  # so sites in the same 5km block get the same cell key. Two update joins then attach the
  # price volatility per grid cell and per gemeente; fcoalesce takes the first non-missing
  # value, giving a grid-first series (base) and a gemeente-first variant (robustness).
  uni[, cel := paste0(x_coord %/% cfg$vol_cel_m, "_", y_coord %/% cfg$vol_cel_m)]
  uni[vol_g,  on = .(cel = regio),           vol_grid_ := i.vol_dlnp]
  uni[vol_gm, on = .(gemeente_code = regio), vol_gem_  := i.vol_dlnp]
  uni[, vol_dlnp     := fcoalesce(vol_grid_, vol_gem_)]   # base: finest granularity first
  uni[, vol_dlnp_gem := fcoalesce(vol_gem_, vol_grid_)]   # variant: gemeente primary
  rd_log("Volatility: grid5km %.1f%%, with gemeente fallback %.1f%%",
         100 * uni[, mean(!is.na(vol_grid_))], 100 * uni[, mean(!is.na(vol_dlnp))])

  # 2012 double-counting flag (#26) sits on the plus side (sites_new)
  # Update join attaches the flag; sites without new-construction rows are left NA by the
  # join and set to 0 (= not flagged). The bare uni[] at the end returns the finished table
  # (the empty brackets make a data.table that was modified by := return/print correctly).
  uni[s$new, on = "site_id", n_flag_2012 := i.n_flag_2012]
  uni[is.na(n_flag_2012), n_flag_2012 := 0L]
  uni[]
}

# Estimate the stage-2 logit in every specification from the header and collect the
# coefficient tables plus average marginal effects (AMEs) of the base model.
estimate_stage2 <- function(uni) {
  # f_base is the base regression formula: outcome y explained by the covariates listed in
  # the header. w() is a winsorizer: it clips a variable at its 1st and 99th percentile
  # (used only in the winsor spec, to tame mega-site tails).
  f_base <- y ~ iv + acq_ha + ln_site_ha + p_owner_occupier_buurt + p_socialhousing_buurt +
                isprotectheritagearea + vol_dlnp + bouwperiode_inc
  # is_natura2000 stays in the completeness filter (it is never NA, so the sample is
  # identical) so that the n2000 robustness spec runs on exactly the same rows as base.
  vars <- c(setdiff(all.vars(f_base), "bouwperiode_inc"), "is_natura2000")
  w    <- function(v) { q <- quantile(v, c(.01, .99), na.rm = TRUE); pmin(pmax(v, q[1]), q[2]) }
  # ln(site_ha) must be finite (a zero area would give -Inf); complete.cases() lets -Inf through.
  uni <- uni[is.finite(ln_site_ha) | bbg_sn == TRUE]

  # sites without building year: quasi-separation (nearly no events on the bp_onbekend dummy
  # keeps the likelihood spinning flat) -> out of the estimation; in the urban sample this is ~5 sites.
  # BBG-SN sites (by definition without an incumbent building year) stay in for the imputation spec.
  n_unknown <- uni[bbg_sn == FALSE & bouwperiode_inc == "bp_onbekend", .N]
  uni       <- uni[bbg_sn == TRUE | bouwperiode_inc != "bp_onbekend"]
  rd_log("Sites with unknown building year removed from the estimation: %s", format(n_unknown, big.mark = ","))

  # Core sample: genuine yes/no choices only (no pipeline sites, no BBG-SN) with all
  # covariates observed. The .. prefix in core[, ..vars] means "vars is a character vector
  # in the calling scope, not a column name"; see README, data.table primer.
  core_all <- uni[pipeline == FALSE & bbg_sn == FALSE]
  core_all <- core_all[complete.cases(core_all[, ..vars]) & !is.na(oad)]
  # Main analysis: replacement of housing, i.e. sites that had dwellings before (cfg, decision
  # 25-09). Redeveloped sites where only non-residential buildings were demolished form a separate
  # model against the potential sites from the unchanged non-residential stock (OnvNW).
  core <- if (isTRUE(cfg$stage2_requires_dwellings)) core_all[inc_has_dwellings == TRUE] else core_all
  core_nonres <- core_all[inc_has_dwellings == FALSE & (prefix == "OnvNW" | y == TRUE)]
  rd_log("Stage-2 universe: %s sites with dwellings before (%s redeveloped); non-residential model: %s sites (%s redeveloped)",
         format(nrow(core), big.mark = ","), format(core[, sum(y)], big.mark = ","),
         format(nrow(core_nonres), big.mark = ","), format(core_nonres[, sum(y)], big.mark = ","))
  urban_subset <- function(d, oad_min) d[oad >= oad_min]

  # fit1 estimates one specification: copy() prevents the := below from touching the
  # caller's table, droplevels() removes unused bouwperiode levels (no empty dummies),
  # feglm runs the logit with SEs clustered on gemeente, and the coefficient table is
  # converted to a data.table tagged with spec label and sample sizes for the export CSV.
  fit1 <- function(fml, d, label) {
    d <- copy(d)[, bouwperiode_inc := droplevels(bouwperiode_inc)]
    m <- feglm(fml, data = d, family = binomial(), cluster = ~gemeente_code,
               glm.iter = 100, glm.tol = 1e-6)
    # On some subsamples the IRLS lands on a numerical plateau: the deviance and every
    # coefficient stop moving, but fixest's convergence criterion is never formally
    # satisfied. Rather than trusting that, refit with a ten times larger iteration cap
    # and compare: identical estimates prove the flag is a stopping-criterion artefact,
    # a real difference means the model genuinely has not settled and must be examined.
    if (!isTRUE(m$convStatus)) {
      m_long <- feglm(fml, data = d, family = binomial(), cluster = ~gemeente_code,
                      glm.iter = 1000, glm.tol = 1e-6)
      drift <- max(abs(coef(m) - coef(m_long)))
      if (drift < 1e-8) {
        rd_log("    NB: '%s' does not trip fixest's convergence flag, but the estimates are", label)
        rd_log("        identical at 100 and 1000 iterations (max drift %.1e): flag artefact.", drift)
      } else {
        rd_log("    WARNING: '%s' has NOT settled: coefficients move %.2e between 100 and", label, drift)
        rd_log("        1000 iterations. Check separation before using this spec.")
      }
    }
    ct <- as.data.table(summary(m)$coeftable, keep.rownames = "term")
    setnames(ct, c("term", "estimate", "se_cluster", "z", "p"))
    ct[, `:=`(spec = label, n = m$nobs, n_y1 = d[, sum(y)])]
    acq_term <- intersect(c("acq_ha", "acq_mln"), ct$term)[1]   # the total spec uses acq_mln
    rd_log("  %-10s n = %s (y=1 %s): iv %+.2f (z %.1f), %s %+.3f (z %.1f), vol %+.2f (z %.1f)",
           label, format(m$nobs, big.mark = ","), format(d[, sum(y)], big.mark = ","),
           ct[term == "iv", estimate], ct[term == "iv", z], acq_term,
           ct[term == acq_term, estimate], ct[term == acq_term, z],
           ct[term %like% "^vol", estimate], ct[term %like% "^vol", z])
    list(m = m, ct = ct)
  }

  rd_log("Specs (SE clustered on gemeente):")
  base    <- urban_subset(core, cfg$oad_min)
  # update() edits a formula: ". ~ . - x" means "same model, but without x" ("+ x" adds one).
  f_no_bp <- update(f_base, . ~ . - bouwperiode_inc)

  # BBG imputation sample: acquisition per hectare = median acq/ha of the observed SN sites
  # (taken from the y=1 sites of the base sample), so these sites can enter the bbg_imput
  # spec despite unknown acquisition costs
  acq_rate <- base[y == TRUE, median(acq_ha)]
  bbg <- uni[bbg_sn == TRUE & !is.na(oad) & oad >= cfg$oad_min & is.finite(ln_site_ha)]
  bbg[, `:=`(acq_ha = acq_rate, acq_mln = acq_rate * site_ha)]
  bbg <- bbg[complete.cases(bbg[, ..vars])]
  rd_log("BBG imputation: %s sites added as y=1 (acq = %.2f M/ha)", format(nrow(bbg), big.mark = ","), acq_rate)

  # Scope specs use the inclusive value of their own stage-1 scope when 06 provided it.
  with_iv <- function(d, col) { d <- copy(d); if (col %in% names(d)) d[, iv := get(col)]; d[!is.na(iv)] }
  # The previous specification, for comparison: amounts for the whole site, no size control.
  f_total <- update(f_base, . ~ . - acq_ha - ln_site_ha + acq_mln)

  # One estimation per specification (the header lists what each one tests). The demol_start
  # spec is out since 25-09: its S sites are formed with a third rule (permit clusters, other
  # buffer), so their area is not comparable; back in once S sites are formed like the others.
  # The non-residential model only runs when the export has the OnvNW comparison sites.
  fits <- list(
    base      = fit1(f_base, base, "base"),
    no_bp     = fit1(f_no_bp, base, "no_bp"),
    urban1500 = fit1(f_base, with_iv(urban_subset(core, 1500L), "iv_urban1500"), "urban1500"),
    nl        = fit1(f_base, with_iv(core, "iv_nl"), "nl"),
    rural     = fit1(f_base, with_iv(core[oad < cfg$oad_min], "iv_rural"), "rural"),
    no_size   = fit1(update(f_base, . ~ . - ln_site_ha), base, "no_size"),
    winsor    = fit1(f_base, copy(base)[, `:=`(iv = w(iv), acq_ha = w(acq_ha))], "winsor"),
    vol_muni  = fit1(update(f_base, . ~ . - vol_dlnp + vol_dlnp_gem), base, "vol_muni"),
    excl2012  = fit1(f_base, base[n_flag_2012 == 0L], "excl2012"),
    n2000     = fit1(update(f_base, . ~ . + is_natura2000), base, "n2000"),
    bbg_imput = fit1(f_no_bp, rbind(base, bbg), "bbg_imput"),
    stage1_cov = fit1(f_base, with_iv(base, "iv_cov"), "stage1_cov"),
    margin7   = if ("iv_margin" %in% names(base)) fit1(f_base, with_iv(base, "iv_margin"), "margin7"),
    total     = fit1(f_total, with_iv(base, "iv_total"), "total"))
  fits <- Filter(Negate(is.null), fits)   # margin7 is absent for an older stage-1 rds
  if (core_nonres[prefix == "OnvNW", .N] > 0L)
    fits$nonres <- fit1(f_base, urban_subset(core_nonres, cfg$oad_min), "nonres")

  # AMEs (base): average marginal effect on P(redevelopment), logit: mean(p(1-p)) x beta
  # Logit coefficients are not probability effects by themselves; multiplying by mean(p(1-p))
  # converts each beta into the average change in redevelopment probability per unit of x.
  p <- predict(fits$base$m, type = "response")
  scale_factor <- mean(p * (1 - p))
  ame <- fits$base$ct[term %chin% c("iv", "acq_ha", "ln_site_ha", "vol_dlnp", "p_owner_occupier_buurt"),
                      .(term, ame = scale_factor * estimate)]

  # Probability of redevelopment per construction period (base): the observed share, and the mean
  # predicted probability when every site is given that period with all other variables as observed.
  # Easier to read than dummies against the reference period.
  bd <- copy(base)[, bouwperiode_inc := droplevels(bouwperiode_inc)]
  lv <- levels(bd$bouwperiode_inc)
  bp_prob <- bd[, .(n = .N, redev = sum(y), observed = mean(y)), keyby = .(bouwperiode = bouwperiode_inc)]
  bp_prob[, predicted := vapply(as.character(bouwperiode), function(L)
    mean(predict(fits$base$m, newdata = copy(bd)[, bouwperiode_inc := factor(L, levels = lv)])), numeric(1))]
  list(fits = fits, ame = ame, bp_prob = bp_prob, basis_n = nrow(base))
}

## ---------------------------------------------------------------------------
# Run block: executes only when the file is run as a script (sys.nframe() == 0 means the
# code is not being sourced from inside a function) or when run_07 was set to TRUE.
if (sys.nframe() == 0L || isTRUE(get0("run_07", ifnotfound = FALSE))) {
  # Load the upstream pipeline results from RDS: the site/alternatives object (alt),
  # the per-site aggregate tables (s) and the stage-1 estimates (s1).
  alt <- readRDS(cfg$file_alt_rds)
  s   <- readRDS(cfg$file_sites_rds)
  s1  <- readRDS(cfg$file_stage1_rds)
  uni <- build_stage2_input(alt, s, s1)
  r   <- estimate_stage2(uni)

  rd_log("Main model (base, OAD >= %d), full table:", cfg$oad_min)
  print(r$fits$base$ct[, .(term, estimate = round(estimate, 4), se_cluster = round(se_cluster, 4), z = round(z, 1))])
  rd_log("McFadden R2 (base): %.3f", r2(r$fits$base$m, "pr2"))
  rd_log("AMEs (percentage points on P(redevelopment), base):")
  print(r$ame[, .(term, ame_pp = round(100 * ame, 4))])
  rd_log("Probability of redevelopment per construction period (%%, base):")
  print(r$bp_prob[, .(bouwperiode, n, redev, observed = round(100 * observed, 2), predicted = round(100 * predicted, 2))])

  # rbindlist stacks the per-spec coefficient tables into one long table for the CSV export;
  # the RDS additionally stores base coefficients and covariance matrix for downstream use.
  specs <- rbindlist(lapply(r$fits, `[[`, "ct"))
  out_file <- file.path(cfg$dir_work, sprintf("stage2_specs%s_%s_%s.csv", cfg$sample_suffix, cfg$area, cfg$bag_date))
  fwrite(specs, out_file, sep = ";")
  saveRDS(list(specs = specs, ame = r$ame, bp_prob = r$bp_prob, coef = coef(r$fits$base$m), vcov = vcov(r$fits$base$m)),
          cfg$file_stage2_rds, compress = FALSE)
  rd_log("Written: %s + %s", cfg$file_stage2_rds, out_file)
}
