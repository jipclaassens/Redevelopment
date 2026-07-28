# 08_tabellen.R — papertabellen (v1) uit de stage-1/2-resultaten, als markdown.
# Output: R_werk/paper_tabellen<suffix>_<area>_<date>.md — hoofdtabel stage 2 (5 specs),
# robuustheidstabel, stage-1-tabel en AME's. Sterren: *** p<0,01, ** p<0,05, * p<0,1.
# Stage-2-SE's zijn op gemeente geclusterd; stage 1 conventioneel (clogit).

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))

ster     <- function(p) fifelse(p < .01, "***", fifelse(p < .05, "**", fifelse(p < .1, "*", "")))
weergave <- function(est, se, p) sprintf("%.3f%s (%.3f)", est, ster(p), se)

labels <- c(
  iv = "Inclusive value", acq_mln = "Verwervingskosten (M€)",
  p_owner_occupier_buurt = "Aandeel eigenaar-bewoners buurt (pp)",
  p_socialhousing_buurt  = "Aandeel sociale huur buurt (pp)",
  isprotectheritageareaTRUE = "Beschermd stads-/dorpsgezicht",
  is_natura2000TRUE = "Natura 2000", vol_dlnp = "Prijsvolatiliteit (sd Δln p)",
  ln_site_ha = "ln(site-oppervlak, ha)",
  bouwperiode_incbouwperiode_tm1925    = "Bouwperiode incumbent: t/m 1925",
  bouwperiode_incbouwperiode_1926_1950 = "Bouwperiode: 1926–1950",
  bouwperiode_incbouwperiode_1951_1965 = "Bouwperiode: 1951–1965",
  bouwperiode_incbouwperiode_1966_1973 = "Bouwperiode: 1966–1973",
  bouwperiode_incbouwperiode_1974_1981 = "Bouwperiode: 1974–1981",
  bouwperiode_incbouwperiode_1982_1991 = "Bouwperiode: 1982–1991",
  bouwperiode_incbouwperiode_1992_2001 = "Bouwperiode: 1992–2001",
  `(Intercept)` = "Constante")

asc_labels <- c(rv_mln = "Residual value (M€)",
  alt_f2 = "ASC appartement-hoogdicht", alt_f3 = "ASC twee-onder-1-kap",
  alt_f4 = "ASC appartement-middeldicht", alt_f5 = "ASC rijtjeswoning",
  alt_f6 = "ASC vrijstaand-groot")   # referentie: vrijstaand-teardown (cluster 1)

md_tabel <- function(dt, specvolgorde) {
  dt <- dt[spec %chin% specvolgorde]
  dt[term == "vol_dlnp_gem", term := "vol_dlnp"]
  dt[, cel_ := weergave(estimate, se_cluster, p)]
  wijd <- dcast(dt, term ~ factor(spec, levels = specvolgorde), value.var = "cel_", fill = "")
  wijd <- wijd[match(names(labels)[names(labels) %chin% wijd$term], term)]
  wijd[, term := labels[term]]
  ns <- dt[, .(n = format(n[1], big.mark = "."), n_y1 = format(n_y1[1], big.mark = ".")), by = spec]
  kop  <- paste0("| ", paste(c("", specvolgorde), collapse = " | "), " |")
  lijn <- paste0("|", paste(rep("---", length(specvolgorde) + 1), collapse = "|"), "|")
  rijen <- wijd[, paste0("| ", term, " | ", do.call(paste, c(.SD, sep = " | ")), " |"), .SDcols = specvolgorde]
  voet <- c(paste0("| N | ", paste(ns[match(specvolgorde, spec), n], collapse = " | "), " |"),
            paste0("| N herontwikkeld | ", paste(ns[match(specvolgorde, spec), n_y1], collapse = " | "), " |"))
  c(kop, lijn, rijen, voet)
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_08", ifnotfound = FALSE))) {
  s1 <- readRDS(cfg$file_stage1_rds)
  s2 <- readRDS(cfg$file_stage2_rds)

  co1 <- data.table(term = names(s1$coef), est = unname(s1$coef), se = sqrt(diag(s1$vcov)))
  co1[, p := 2 * pnorm(-abs(est / se))]
  co1[, lbl := asc_labels[term]]

  uit <- c(
    sprintf("# Papertabellen (v1) — %s, BAG %s, sample %s, prijspeil %d", cfg$area, cfg$bag_date, cfg$stage1_sample, cfg$prijspeil_jaar),
    "", sprintf("Afbakening: OAD ≥ %d (basis). SE's stage 2 geclusterd op gemeente; *** p<0,01 ** p<0,05 * p<0,1.", cfg$oad_min),
    "", "## Stage 1 — conditional logit ontwikkeltype (SN-sites)", "",
    "| | coef (se) |", "|---|---|",
    co1[, sprintf("| %s | %s |", lbl, weergave(est, se, p))],
    "", "## Stage 2 — binomiale logit herontwikkeling: hoofdspecs", "",
    md_tabel(copy(s2$specs), c("basis", "size", "urban1500", "nl", "sloopstart")),
    "", "## Stage 2 — robuustheid", "",
    md_tabel(copy(s2$specs), c("kaal", "winsor", "vol_gem", "excl2012", "bbg_imput")),
    "", "## Gemiddelde marginale effecten (basis, procentpunt)", "",
    "| | AME (pp) |", "|---|---|",
    s2$ame[, sprintf("| %s | %.3f |", labels[term], 100 * ame)])

  bestand <- file.path(cfg$dir_work, sprintf("paper_tabellen%s_%s_%s.md", cfg$sample_suffix, cfg$area, cfg$bag_date))
  writeLines(uit, bestand, useBytes = FALSE)
  rd_log("Weggeschreven: %s", bestand)
}
