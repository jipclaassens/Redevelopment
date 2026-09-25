# 10_descriptives.R - descriptive paper tables (D1-D4) and figures.
#
# D1a object counts per mutation type; D1b sample-construction funnel (stage 1 + stage 2,
#     mirroring the filters of 06/07 step by step);
# D2  summary statistics of the stage-2 covariates, split by outcome (base sample);
# D3  densification before/after on realized SN sites (incumbent vs new state);
# D4  the cluster menu: centroid characteristics + chosen shares per alternative.
# Figures: SN starts per year vs national rolling volatility, building-period coefplot
# (stage-2 base), elbow curve (K choice), map of SN sites vs the unchanged stock.
#
# Output: R_werk/descriptives<suffix>_<area>_<date>.md (+ .docx via pandoc) and fig_*.png.
# Everything is read from the rds files of steps 03-09; nothing upstream is recomputed
# except build_stage2_input (07), which is cheap and keeps the funnel exactly in sync.

# Bootstrap: locate this script's directory so the source() calls below work from any cwd.
if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
# Borrow build_stage2_input() from 07 and the formatting helpers (fmt_cell, labels) from 08
# without triggering their runner blocks: the run_XX flags are forced FALSE while sourcing.
run_07_saved <- get0("run_07", ifnotfound = FALSE); run_07 <- FALSE
source(file.path(.rd_script_dir, "07_stage2_logit.R"))
run_07 <- run_07_saved
run_08_saved <- get0("run_08", ifnotfound = FALSE); run_08 <- FALSE
source(file.path(.rd_script_dir, "08_tables.R"))
run_08 <- run_08_saved

# Number formatting: 3 significant digits, thousands separator for the big counts.
fmt_num <- function(v) prettyNum(signif(v, 3), big.mark = ",", scientific = FALSE)
fmt_n   <- function(v) format(v, big.mark = ",", trim = TRUE)

# Cluster names, consistent with the ASC labels in 08 (reference = cluster 1).
cluster_names <- c("Detached teardown", "Apartment high-density", "Semi-detached",
                   "Apartment mid-density", "Terraced", "Detached large")

## ---------------------------------------------------------------------------
## D1a: object counts per mutation type (from the per-object export)
## ---------------------------------------------------------------------------
d1a_object_counts <- function(x) {
  d <- x[, .N, by = redev_type_lbl][order(-N)]
  d[, share := 100 * N / sum(N)]
  c("| Mutation type | Objects (VBO) | Share (%) |", "|---|---|---|",
    d[, sprintf("| %s | %s | %.2f |", redev_type_lbl, fmt_n(N), share)],
    sprintf("| Total | %s | 100.00 |", fmt_n(d[, sum(N)])))
}

## ---------------------------------------------------------------------------
## D1b: sample-construction funnel (mirrors the filters in 06 and 07)
## ---------------------------------------------------------------------------
d1b_funnel <- function(alt, uni) {
  step <- function(label, n, n_y1 = NA_integer_)
    sprintf("| %s | %s | %s |", label, fmt_n(n), if (is.na(n_y1)) "" else fmt_n(n_y1))

  # stage-1 funnel: realized menu sites -> complete RV -> urban scope (as in 06)
  st <- copy(alt$sites)
  real_ids <- st[!is.na(cluster_real), site_id]
  complete <- alt$long[site_id %chin% real_ids][, .(ok = !anyNA(rv_eur)), by = site_id][ok == TRUE, site_id]
  n_urban  <- st[site_id %chin% complete & !is.na(oad) & oad >= cfg$oad_min, .N]

  # stage-2 funnel: replicate the estimate_stage2 filters step by step on uni (from
  # build_stage2_input): pipeline out, BBG-SN out, unknown building period out,
  # complete covariates + OAD observed, then the OAD scope filter.
  vars <- c("iv", "acq_ha", "ln_site_ha", "p_owner_occupier_buurt", "p_socialhousing_buurt",
            "isprotectheritagearea", "vol_dlnp")
  u1 <- uni
  u2 <- u1[pipeline == FALSE]
  u3 <- u2[bbg_sn == FALSE]
  u4 <- u3[bouwperiode_inc != "bp_onbekend"]
  u4b <- if (isTRUE(cfg$stage2_requires_dwellings)) u4[inc_has_dwellings == TRUE] else u4
  u5 <- u4b[complete.cases(u4b[, ..vars]) & is.finite(ln_site_ha) & !is.na(oad)]
  u6 <- u5[oad >= cfg$oad_min]

  c("**Stage 1 (conditional logit over development types)**", "",
    "| Step | N sites | of which redeveloped |", "|---|---|---|",
    step("Realized sites in the stage-1 sample (SN)", length(real_ids)),
    step("Complete residual value over all K alternatives", length(complete)),
    step(sprintf("Urban scope (OAD >= %d) = estimation sample", cfg$oad_min), n_urban),
    "", "**Stage 2 (binomial logit redevelopment)**", "",
    "| Step | N sites | of which redeveloped |", "|---|---|---|",
    step("Universe: potential (unchanged stock) + realized SN + pipeline", nrow(u1), u1[, sum(y)]),
    step("Pipeline sites excluded (demolition/withdrawal without follow-up)", nrow(u2), u2[, sum(y)]),
    step("BBG-route SN excluded (acquisition not reconstructable)", nrow(u3), u3[, sum(y)]),
    step("Unknown incumbent building period excluded", nrow(u4), u4[, sum(y)]),
    step("Only non-residential buildings before excluded (separate model)", nrow(u4b), u4b[, sum(y)]),
    step("Complete covariates and OAD observed", nrow(u5), u5[, sum(y)]),
    step(sprintf("Base estimation sample: OAD >= %d", cfg$oad_min), nrow(u6), u6[, sum(y)]),
    "", sprintf("Redevelopment share in the base sample: %.2f%%.", 100 * u6[, mean(y)]))
}

## ---------------------------------------------------------------------------
## D2: summary statistics of the stage-2 covariates by outcome (base sample)
## ---------------------------------------------------------------------------
d2_summary_stats <- function(base_dt) {
  cont <- c(iv = "Inclusive value", acq_ha = "Acquisition costs (EUR M per ha)",
            acq_mln = "Acquisition costs (EUR M per site)",
            site_ha = "Site area (ha)",
            n_units_res_inc = "Dwellings on the site (incumbent)",
            p_owner_occupier_buurt = "Share owner-occupiers neighbourhood (pp)",
            p_socialhousing_buurt  = "Share social housing neighbourhood (pp)",
            vol_dlnp = "Price volatility (sd dln p)", oad = "Address density (OAD)")
  bool <- c(isprotectheritagearea = "Protected townscape (share)",
            is_natura2000 = "Natura 2000 (share)")

  row3 <- function(v, g) sprintf("%s | %s | %s", fmt_num(mean(v[g], na.rm = TRUE)),
                                 fmt_num(sd(v[g], na.rm = TRUE)), fmt_num(median(v[g], na.rm = TRUE)))
  rows <- c(
    vapply(names(cont), function(cn) {
      v <- base_dt[[cn]]
      sprintf("| %s | %s | %s |", cont[cn], row3(v, !base_dt$y), row3(v, base_dt$y))
    }, character(1)),
    vapply(names(bool), function(cn) {
      v <- as.numeric(base_dt[[cn]])
      sprintf("| %s | %s | | | %s | | |", bool[cn],
              fmt_num(mean(v[!base_dt$y])), fmt_num(mean(v[base_dt$y])))
    }, character(1)))

  # building-period distribution of the incumbents (share per level, per outcome group)
  bp <- base_dt[, .N, by = .(bouwperiode_inc, y)]
  bp[, share := N / sum(N), by = y]
  bp_wide <- dcast(bp, bouwperiode_inc ~ y, value.var = "share", fill = 0)
  setnames(bp_wide, c("bp", "s0", "s1"))
  bp_ord <- paste0("bouwperiode_", c("tm1925", "1926_1950", "1951_1965", "1966_1973",
                                     "1974_1981", "1982_1991", "1992_2001", "va2002"))
  bp_wide <- bp_wide[match(intersect(bp_ord, as.character(bp)), as.character(bp))]
  bp_rows <- bp_wide[, sprintf("| Construction period %s (share) | %.3f | | | %.3f | | |",
                               sub("^bouwperiode_", "", bp), s0, s1)]

  c(sprintf("Base sample (OAD >= %d), N = %s, of which redeveloped %s.", cfg$oad_min,
            fmt_n(nrow(base_dt)), fmt_n(base_dt[, sum(y)])), "",
    "| | Unchanged: mean | sd | median | Redeveloped: mean | sd | median |",
    "|---|---|---|---|---|---|---|",
    rows, bp_rows)
}

## ---------------------------------------------------------------------------
## D3: densification before/after on realized SN sites
## ---------------------------------------------------------------------------
d3_before_after <- function(s, alt) {
  ba <- merge(s$incumbent, s$new, by = "site_id", suffixes = c("_inc", "_new"))
  ba <- ba[has_sn == TRUE]
  # site size and OAD from the site attribute table (update join, see README primer)
  ba[alt$sites, on = "site_id", `:=`(oad = i.oad, site_ha = i.site_ha)]
  ba[, `:=`(floor_inc = floor_area_res_m2 + floor_area_nonres_m2,
            far_inc   = (floor_area_res_m2 + floor_area_nonres_m2) / site_size,
            far_new   = far,
            dens_inc  = n_units_res / (site_size / 1e4),
            dens_new  = n_units_new / (site_size / 1e4))]

  panel <- function(d, label) {
    r <- function(metric, inc, new) sprintf("| %s | %s | %s | %.2f |", metric,
                                            fmt_num(inc), fmt_num(new), new / inc)
    c(sprintf("**%s** (N = %s sites)", label, fmt_n(nrow(d))), "",
      "| | Incumbent | New | Ratio |", "|---|---|---|---|",
      r("Dwellings per site (mean)",   d[, mean(n_units_res)],  d[, mean(n_units_new)]),
      r("Dwellings per site (median)", d[, median(as.numeric(n_units_res))], d[, median(as.numeric(n_units_new))]),
      r("Dwellings per ha (mean)",     d[, mean(dens_inc, na.rm = TRUE)], d[, mean(dens_new, na.rm = TRUE)]),
      r("Floor area per site (m2, mean)", d[, mean(floor_inc, na.rm = TRUE)], d[, mean(floor_area_m2, na.rm = TRUE)]),
      r("FAR (mean)",                  d[, mean(far_inc, na.rm = TRUE)], d[, mean(far_new, na.rm = TRUE)]),
      sprintf("| Sites with net dwelling gain | | | %.1f%% |", 100 * d[, mean(n_units_new > n_units_res)]),
      "")
  }
  c(panel(ba, "All SN sites with incumbent"),
    panel(ba[!is.na(oad) & oad >= cfg$oad_min], sprintf("Urban scope (OAD >= %d)", cfg$oad_min)))
}

## ---------------------------------------------------------------------------
## D4: the cluster menu (stage-1 alternatives)
## ---------------------------------------------------------------------------
d4_cluster_menu <- function(alt) {
  ctr <- copy(alt$centroids)
  chosen <- alt$sites[!is.na(cluster_real), .N, by = .(cluster = cluster_real)]
  ctr[chosen, on = "cluster", n_chosen := i.N]
  ctr[, share_chosen := 100 * n_chosen / sum(n_chosen)]
  # dominant WP4 type of each centroid: the share_ column with the largest value
  shr <- as.matrix(ctr[, paste0("share_", cfg$wp4_names), with = FALSE])
  dom_i <- max.col(shr)
  ctr[, dominant := sprintf("%s (%.0f%%)", cfg$wp4_english[dom_i], 100 * shr[cbind(.I, dom_i)])]

  c("| Cluster | Chosen (%) | FAR | Dwellings/ha | Unit size (m2) | Dominant type |",
    "|---|---|---|---|---|---|",
    ctr[, sprintf("| %d. %s | %.1f | %.2f | %.0f | %.0f | %s |",
                  cluster, cluster_names[cluster], share_chosen, far, density_per_ha,
                  unit_size_mean, dominant)],
    "", sprintf("Menu clustered on the %s realized SN sites (K = %d).",
                fmt_n(alt$sites[!is.na(cluster_real), .N]), nrow(ctr)))
}

## ---------------------------------------------------------------------------
## Figures (base R graphics; written as png next to the markdown)
## ---------------------------------------------------------------------------
fig_starts_vs_vol <- function(s, file) {
  ev <- s$incumbent[site_id %like% "^SN_" & !is.na(event_yearmonth),
                    .(year = event_yearmonth %/% 100L)][year >= 2012L & year <= 2026L,
                    .N, by = year][order(year)]
  vnl <- fread(cfg$file_vol_rolling("nationaal"))
  # The last two years are incomplete: the BAG snapshot runs to July 2026 and demolition
  # registrations lag, so 2025-2026 counts are censored rather than a genuine collapse.
  # They are drawn hatched so the figure cannot be misread; the caption repeats it.
  incomplete <- ev$year >= 2025L
  png(file, width = 2400, height = 1500, res = 300)
  par(mar = c(4, 4, 1.5, 4))
  bp <- barplot(ev$N, names.arg = ev$year, border = NA, las = 2,
                col = fifelse(incomplete, "grey92", "grey80"),
                ylab = "SN redevelopment starts (sites)")
  barplot(fifelse(incomplete, ev$N, 0), border = NA, col = "grey60", density = 12, angle = 45,
          axes = FALSE, names.arg = rep("", nrow(ev)), add = TRUE)
  par(new = TRUE)
  v <- vnl[match(ev$year, besluitjaar), vol_roll5]
  plot(as.vector(bp), v, type = "b", pch = 16, col = "firebrick", axes = FALSE,
       xlab = "", ylab = "", ylim = range(v, na.rm = TRUE))
  axis(4, col.axis = "firebrick", col = "firebrick")
  mtext("National rolling volatility (5y sd of index growth)", side = 4, line = 2.5,
        col = "firebrick", cex = 0.9)
  legend("bottomleft", legend = c("complete years", "incomplete (BAG to July 2026)"),
         fill = c("grey80", "grey92"), density = c(NA, 20), border = NA, bty = "n", cex = 0.75)
  dev.off()
}

fig_bp_coefplot <- function(s2, file) {
  d <- s2$specs[spec == "base" & term %like% "^bouwperiode_inc"]
  d[, period := sub("^bouwperiode_incbouwperiode_", "", term)]
  ord <- c("tm1925", "1926_1950", "1951_1965", "1966_1973", "1974_1981", "1982_1991", "1992_2001")
  d <- d[match(ord, period)]
  lab <- c("<1926", "1926-50", "1951-65", "1966-73", "1974-81", "1982-91", "1992-2001", "2002+ (ref)")
  est <- c(d$estimate, 0); lo <- c(d$estimate - 1.96 * d$se_cluster, NA); hi <- c(d$estimate + 1.96 * d$se_cluster, NA)
  png(file, width = 2400, height = 1500, res = 300)
  par(mar = c(6, 4, 1.5, 1))
  plot(seq_along(est), est, pch = 16, xaxt = "n", xlab = "", xlim = c(0.5, length(est) + 0.5),
       ylim = range(c(lo, hi, 0), na.rm = TRUE),
       ylab = "Log-odds of redevelopment (ref: built 2002+)")
  segments(seq_along(est), lo, seq_along(est), hi)
  abline(h = 0, lty = 3, col = "grey50")
  axis(1, at = seq_along(est), labels = lab, las = 2)
  dev.off()
}

fig_elbow <- function(file) {
  eb <- fread(file.path(cfg$dir_work, paste0("elbow", cfg$sample_suffix, ".csv")))
  png(file, width = 2400, height = 1500, res = 300)
  par(mar = c(4, 4, 1.5, 1))
  plot(eb$k, eb$pre, type = "b", pch = 16, xlab = "Number of clusters K",
       ylab = "Proportional reduction of error (PRE)")
  abline(v = cfg$kmeans_k_final, lty = 2, col = "firebrick")
  text(cfg$kmeans_k_final, max(eb$pre, na.rm = TRUE), sprintf(" K = %d", cfg$kmeans_k_final),
       adj = 0, col = "firebrick")
  dev.off()
}

fig_map_sn <- function(alt, file) {
  st <- alt$sites
  png(file, width = 1800, height = 2100, res = 300)
  par(mar = c(0.5, 0.5, 1.5, 0.5))
  plot(st[site_id %like% "^Onv", .(x_coord, y_coord)], pch = ".", col = "grey85",
       asp = 1, axes = FALSE, xlab = "", ylab = "")
  points(st[site_id %like% "^SN_", .(x_coord, y_coord)], pch = 16, cex = 0.15,
         col = rgb(0.7, 0.1, 0.1, 0.5))
  legend("topleft", legend = c("Unchanged stock (potential sites)", "SN redevelopment"),
         pch = c(15, 16), col = c("grey85", "firebrick"), bty = "n", cex = 0.8)
  dev.off()
}

## ---------------------------------------------------------------------------
# Runner: executes when called directly (sys.nframe() == 0) or via run_10 from run_all.R.
if (sys.nframe() == 0L || isTRUE(get0("run_10", ifnotfound = FALSE))) {
  # Object counts need the big per-object table; free it again right away (5 GB).
  x <- readRDS(cfg$file_perobject_rds)
  d1a <- d1a_object_counts(x)
  n_obj <- nrow(x)
  rm(x); invisible(gc())

  alt <- readRDS(cfg$file_alt_rds)
  s   <- readRDS(cfg$file_sites_rds)
  s1  <- readRDS(cfg$file_stage1_rds)
  s2  <- readRDS(cfg$file_stage2_rds)
  uni <- build_stage2_input(alt, s, s1)

  # base estimation sample for D2 (same filters as the funnel/estimation)
  vars <- c("iv", "acq_ha", "ln_site_ha", "p_owner_occupier_buurt", "p_socialhousing_buurt",
            "isprotectheritagearea", "vol_dlnp")
  base_dt <- uni[pipeline == FALSE & bbg_sn == FALSE & bouwperiode_inc != "bp_onbekend" & (inc_has_dwellings == TRUE | !isTRUE(cfg$stage2_requires_dwellings))]
  base_dt <- base_dt[complete.cases(base_dt[, ..vars]) & is.finite(ln_site_ha) & !is.na(oad) & oad >= cfg$oad_min]

  # figures first (so the markdown can reference them)
  f1 <- file.path(cfg$dir_work, "fig1_sn_starts_vol.png");  fig_starts_vs_vol(s, f1)
  f2 <- file.path(cfg$dir_work, "fig2_bp_coefplot.png");    fig_bp_coefplot(s2, f2)
  f3 <- file.path(cfg$dir_work, "fig3_elbow.png");          fig_elbow(f3)
  f4 <- file.path(cfg$dir_work, "fig4_map_sn.png");         fig_map_sn(alt, f4)
  rd_log("Figures written: %s", paste(basename(c(f1, f2, f3, f4)), collapse = ", "))

  out <- c(
    sprintf("# Descriptives - %s, BAG %s, sample %s", cfg$area, cfg$bag_date, cfg$stage1_sample), "",
    sprintf("Per-object export: %s VBO rows.", fmt_n(n_obj)), "",
    "## D1a. Objects per mutation type", "", d1a, "",
    "## D1b. Sample construction", "", d1b_funnel(alt, uni), "",
    "## D2. Stage-2 covariates by outcome (base sample)", "", d2_summary_stats(base_dt), "",
    "## D3. Densification on redeveloped (SN) sites: incumbent vs new state", "",
    d3_before_after(s, alt), "",
    "## D4. The development-type menu (stage-1 alternatives)", "", d4_cluster_menu(alt), "",
    "## Figures", "",
    paste("Figure 1. SN redevelopment starts per year vs the national rolling volatility of house",
          "prices. The 2025 and 2026 bars are hatched because they are incomplete: the BAG snapshot",
          "runs to July 2026 and demolition registrations lag, so those counts are censored rather",
          "than a genuine decline. The volatility series ends in 2024."), "",
    sprintf("![](%s)", basename(f1)), "",
    "Figure 2. Stage-2 building-period gradient (base spec, 95% CI, clustered SEs).", "",
    sprintf("![](%s)", basename(f2)), "",
    "Figure 3. Elbow curve for the cluster menu (appendix).", "",
    sprintf("![](%s)", basename(f3)), "",
    "Figure 4. SN redevelopment sites vs the unchanged stock (appendix or data section).", "",
    sprintf("![](%s)", basename(f4)))

  outfile <- file.path(cfg$dir_work, sprintf("descriptives%s_%s_%s.md", cfg$sample_suffix, cfg$area, cfg$bag_date))
  writeLines(out, outfile, useBytes = FALSE)
  rd_log("Written: %s", outfile)
  rd_md_to_docx(outfile)
}
