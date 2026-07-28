# 09_hazard.R — discrete-time hazard (extensie op stap 5): site x jaar-panel 2012-2026,
# y_st = 1 in het STARTJAAR van de herontwikkeling. Doel: het real-options-kanaal toetsen
# met TIJDVARIERENDE volatiliteit, waar de cross-sectionele maat in 07 geen bewijs vond —
# identificatie komt hier uit de tijdsvariatie binnen locaties (crisis- vs boomjaren).
#
# Opzet (Allison-style): binomiale logit op het panel = discrete-time hazard. Een site is
# "at risk" vanaf 2012 tot en met zijn startjaar (SN) of t/m 2026 (Onveranderd, gecensord).
#
# Aannames/keuzes (default, gedocumenteerd voor het paper):
#  - beslismoment ~ eerste min-mutatie op de site (event_yearmonth uit 03: de eerste
#    sloop-/intrekkingsregistratie — de onomkeerbare stap). Vergunningsdatum zou eerder
#    liggen maar vergt een extra bron; future refinement.
#  - universum = stage-2-basis: SN-met-incumbent + Onveranderd, OAD >= cfg$oad_min,
#    zonder pijplijn (S/O), BBG-SN (startjaar/verwerving onbekend) en onbekend bouwjaar.
#  - vol_roll5 = sd van de lokale indexgroei over de 5 jaar vóór het besluitjaar
#    (PriceIndices Volatility_rolling_*; grid5km, fallback gemeente; na het laatste
#    beschikbare besluitjaar wordt de laatst bekende waarde gebruikt).
#  - iv/verwerving/fricties tijdvast (2023-peil); jaar-fixed-effects vangen de nationale
#    prijscyclus en de baseline hazard; 2026 is een half jaar (BAG t/m juli) — de
#    jaardummy vangt dat niveau.
#  - feglm logit met jaar-FE, SE geclusterd op gemeente.
#
# Output: cfg$file_hazard_rds (coeftabellen hoofdmodel + variant zonder vol; n's).

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
run_07_bewaar <- get0("run_07", ifnotfound = FALSE); run_07 <- FALSE
source(file.path(.rd_script_dir, "07_stage2_logit.R"))   # maak_stage2_input + config/fixest
run_07 <- run_07_bewaar

maak_hazard_panel <- function(alt, s, s1) {
  uni <- maak_stage2_input(alt, s, s1)
  uni <- uni[bbg_sn == FALSE & pijplijn == FALSE & bouwperiode_inc != "bp_onbekend"]
  uni[, bouwperiode_inc := droplevels(bouwperiode_inc)]
  uni[s$incumbent, on = "site_id", event_ym := i.event_yearmonth]

  vars <- c("iv", "acq_mln", "p_owner_occupier_buurt", "p_socialhousing_buurt",
            "isprotectheritagearea", "is_natura2000")
  uni <- uni[complete.cases(uni[, ..vars]) & !is.na(oad) & oad >= cfg$oad_min]
  n_zonder_event <- uni[y == TRUE & is.na(event_ym), .N]
  uni <- uni[y == FALSE | !is.na(event_ym)]
  rd_log("Hazard-universum: %s sites (y=1: %s; %s SN-sites zonder eventdatum vervallen)",
         format(nrow(uni), big.mark = ","), format(uni[, sum(y)], big.mark = ","),
         format(n_zonder_event, big.mark = ","))

  uni[, event_jaar := fifelse(y, event_ym %/% 100L, NA_integer_)]
  uni[, jaar_eind  := fifelse(y, pmin(event_jaar, 2026L), 2026L)]
  uni <- uni[jaar_eind >= 2012L]

  panel <- uni[rep(seq_len(.N), jaar_eind - 2012L + 1L)]
  panel[, jaar := 2011L + rowid(site_id)]
  panel[, y_jaar := as.integer(y & jaar == jaar_eind)]

  # tijdvariërende volatiliteit: grid5km-cel, fallback gemeente; laatste bekende waarde na afloop
  vg  <- fread(cfg$file_vol_rolling("grid5km"))
  vgm <- fread(cfg$file_vol_rolling("gemeente_code"))
  panel[, jaar_vol := pmin(jaar, max(vg$besluitjaar))]
  panel[vg,  on = .(cel = regio, jaar_vol = besluitjaar),           vol_roll := i.vol_roll5]
  panel[vgm, on = .(gemeente_code = regio, jaar_vol = besluitjaar), vol_roll_gm := i.vol_roll5]
  panel[, vol_roll := fcoalesce(vol_roll, vol_roll_gm)]
  rd_log("Panel: %s site-jaren (%s events, %.3f%% per jaar); vol_roll-dekking %.1f%%",
         format(nrow(panel), big.mark = ","), format(sum(panel$y_jaar), big.mark = ","),
         100 * mean(panel$y_jaar), 100 * mean(!is.na(panel$vol_roll)))
  panel
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_09", ifnotfound = FALSE))) {
  alt <- readRDS(cfg$file_alt_rds)
  s   <- readRDS(cfg$file_sites_rds)
  s1  <- readRDS(cfg$file_stage1_rds)
  panel <- maak_hazard_panel(alt, s, s1)

  f_haz <- y_jaar ~ iv + acq_mln + p_owner_occupier_buurt + p_socialhousing_buurt +
                    isprotectheritagearea + is_natura2000 + vol_roll + bouwperiode_inc | jaar
  est <- panel[!is.na(vol_roll)]
  m      <- feglm(f_haz, data = est, family = binomial(), cluster = ~gemeente_code, glm.iter = 100)
  m_kaal <- feglm(update(f_haz, . ~ . - vol_roll | jaar), data = est, family = binomial(),
                  cluster = ~gemeente_code, glm.iter = 100)
  if (!isTRUE(m$convStatus)) rd_log("NB: hazard-hoofdmodel niet geconvergeerd — check separatie")

  ct <- as.data.table(summary(m)$coeftable, keep.rownames = "term")
  setnames(ct, c("term", "estimate", "se_cluster", "z", "p"))
  rd_log("Discrete-time hazard (jaar-FE, SE geclusterd op gemeente):")
  print(ct[!(term %like% "bouwperiode"), .(term, estimate = round(estimate, 4), se_cluster = round(se_cluster, 4), z = round(z, 1))])
  rd_log("vol_roll = het real-options-resultaat: negatief = onzekerheid remt de start")

  saveRDS(list(coef = ct, coef_kaal = coef(m_kaal), n = m$nobs, n_events = est[, sum(y_jaar)]),
          cfg$file_hazard_rds, compress = FALSE)
  rd_log("Weggeschreven: %s", cfg$file_hazard_rds)
}
