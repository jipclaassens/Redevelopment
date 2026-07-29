# 08_tables.R — paper tables (v1) from the stage-1/2 results, as markdown.
# Output: R_werk/paper_tabellen<suffix>_<area>_<date>.md — main stage-2 table (5 specs),
# robustness table, stage-1 table and AMEs. Stars: *** p<0.01, ** p<0.05, * p<0.1.
# Stage-2 SEs are clustered on gemeente; stage 1 conventional (clogit).

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))

stars    <- function(p) fifelse(p < .01, "***", fifelse(p < .05, "**", fifelse(p < .1, "*", "")))
fmt_cell <- function(est, se, p) sprintf("%.3f%s (%.3f)", est, stars(p), se)

labels <- c(
  iv = "Inclusive value", acq_mln = "Acquisition costs (EUR M)",
  p_owner_occupier_buurt = "Share owner-occupiers neighbourhood (pp)",
  p_socialhousing_buurt  = "Share social housing neighbourhood (pp)",
  isprotectheritageareaTRUE = "Protected townscape",
  is_natura2000TRUE = "Natura 2000", vol_dlnp = "Price volatility (sd Δln p)",
  ln_site_ha = "ln(site area, ha)",
  bouwperiode_incbouwperiode_tm1925    = "Construction period incumbent: pre-1926",
  bouwperiode_incbouwperiode_1926_1950 = "Construction period: 1926–1950",
  bouwperiode_incbouwperiode_1951_1965 = "Construction period: 1951–1965",
  bouwperiode_incbouwperiode_1966_1973 = "Construction period: 1966–1973",
  bouwperiode_incbouwperiode_1974_1981 = "Construction period: 1974–1981",
  bouwperiode_incbouwperiode_1982_1991 = "Construction period: 1982–1991",
  bouwperiode_incbouwperiode_1992_2001 = "Construction period: 1992–2001",
  `(Intercept)` = "Constant")

asc_labels <- c(rv_mln = "Residual value (M€)",
  alt_f2 = "ASC apartment high-density", alt_f3 = "ASC semi-detached",
  alt_f4 = "ASC apartment mid-density", alt_f5 = "ASC terraced",
  alt_f6 = "ASC detached large")   # reference: detached-teardown (cluster 1)

md_table <- function(dt, spec_order) {
  dt <- dt[spec %chin% spec_order]
  dt[term == "vol_dlnp_gem", term := "vol_dlnp"]
  dt[, cell_ := fmt_cell(estimate, se_cluster, p)]
  wide <- dcast(dt, term ~ factor(spec, levels = spec_order), value.var = "cell_", fill = "")
  wide <- wide[match(names(labels)[names(labels) %chin% wide$term], term)]
  wide[, term := labels[term]]
  ns <- dt[, .(n = format(n[1], big.mark = "."), n_y1 = format(n_y1[1], big.mark = ".")), by = spec]
  header <- paste0("| ", paste(c("", spec_order), collapse = " | "), " |")
  divider <- paste0("|", paste(rep("---", length(spec_order) + 1), collapse = "|"), "|")
  rows <- wide[, paste0("| ", term, " | ", do.call(paste, c(.SD, sep = " | ")), " |"), .SDcols = spec_order]
  footer <- c(paste0("| N | ", paste(ns[match(spec_order, spec), n], collapse = " | "), " |"),
            paste0("| N redeveloped | ", paste(ns[match(spec_order, spec), n_y1], collapse = " | "), " |"))
  c(header, divider, rows, footer)
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_08", ifnotfound = FALSE))) {
  s1 <- readRDS(cfg$file_stage1_rds)
  s2 <- readRDS(cfg$file_stage2_rds)

  co1 <- data.table(term = names(s1$coef), est = unname(s1$coef), se = sqrt(diag(s1$vcov)))
  co1[, p := 2 * pnorm(-abs(est / se))]
  co1[, lbl := asc_labels[term]]

  out <- c(
    sprintf("# Paper tables (v1) — %s, BAG %s, sample %s, price level %d", cfg$area, cfg$bag_date, cfg$stage1_sample, cfg$price_level_year),
    "", sprintf("Scope: OAD ≥ %d (base). Stage-2 SEs clustered on gemeente; *** p<0.01 ** p<0.05 * p<0.1.", cfg$oad_min),
    "", "## Stage 1 — conditional logit development type (SN sites)", "",
    "| | coef (se) |", "|---|---|",
    co1[, sprintf("| %s | %s |", lbl, fmt_cell(est, se, p))],
    "", "## Stage 2 — binomial logit redevelopment: main specifications", "",
    md_table(copy(s2$specs), c("base", "size", "urban1500", "nl", "demol_start")),
    "", "## Stage 2 — robustness", "",
    md_table(copy(s2$specs), c("no_bp", "winsor", "vol_muni", "excl2012", "bbg_imput")),
    "", "## Average marginal effects (base, percentage points)", "",
    "| | AME (pp) |", "|---|---|",
    s2$ame[, sprintf("| %s | %.3f |", labels[term], 100 * ame)])

  outfile <- file.path(cfg$dir_work, sprintf("paper_tabellen%s_%s_%s.md", cfg$sample_suffix, cfg$area, cfg$bag_date))
  writeLines(out, outfile, useBytes = FALSE)
  rd_log("Written: %s", outfile)
}
