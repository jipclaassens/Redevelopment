# 09_hazard.R — discrete-time hazard (extension of step 5): site x year panel 2012-2026,
# y_st = 1 in the START YEAR of the redevelopment. Goal: test the real-options channel
# with TIME-VARYING volatility, where the cross-sectional measure in 07 found no evidence —
# identification here comes from time variation within locations (crisis vs boom years).
#
# Setup (Allison-style): binomial logit on the panel = discrete-time hazard. A site is
# "at risk" from 2012 up to and including its start year (SN) or through 2026 (Onveranderd, censored).
#
# Assumptions/choices (default, documented for the paper):
#  - decision moment ~ first minus-mutation on the site (event_yearmonth from 03: the first
#    demolition/withdrawal registration — the irreversible step). The permit date would be
#    earlier but requires an extra source; future refinement.
#  - universe = stage-2 base: SN-with-incumbent + Onveranderd, OAD >= cfg$oad_min,
#    excluding pipeline (S/O), BBG-SN (start year/acquisition unknown) and unknown building year.
#  - vol_roll5 = sd of local index growth over the 5 years before the decision year
#    (PriceIndices Volatility_rolling_*; grid5km, fallback gemeente; after the last
#    available decision year the last known value is used).
#  - iv/acquisition/frictions time-invariant (2023 level); year fixed effects capture the
#    national price cycle and the baseline hazard; 2026 is half a year (BAG through July) —
#    the year dummy captures that level.
#  - feglm logit with year FE, SE clustered on gemeente.
#
# Output: cfg$file_hazard_rds (coefficient tables main model + variant without vol; n's).

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
run_07_saved <- get0("run_07", ifnotfound = FALSE); run_07 <- FALSE
source(file.path(.rd_script_dir, "07_stage2_logit.R"))   # build_stage2_input + config/fixest
run_07 <- run_07_saved

build_hazard_panel <- function(alt, s, s1) {
  uni <- build_stage2_input(alt, s, s1)
  uni <- uni[bbg_sn == FALSE & pipeline == FALSE & bouwperiode_inc != "bp_onbekend"]
  uni[, bouwperiode_inc := droplevels(bouwperiode_inc)]
  uni[s$incumbent, on = "site_id", event_ym := i.event_yearmonth]

  vars <- c("iv", "acq_mln", "p_owner_occupier_buurt", "p_socialhousing_buurt",
            "isprotectheritagearea", "is_natura2000")
  uni <- uni[complete.cases(uni[, ..vars]) & !is.na(oad) & oad >= cfg$oad_min]
  n_without_event <- uni[y == TRUE & is.na(event_ym), .N]
  uni <- uni[y == FALSE | !is.na(event_ym)]
  rd_log("Hazard universe: %s sites (y=1: %s; %s SN sites without event date dropped)",
         format(nrow(uni), big.mark = ","), format(uni[, sum(y)], big.mark = ","),
         format(n_without_event, big.mark = ","))

  uni[, event_year := fifelse(y, event_ym %/% 100L, NA_integer_)]
  uni[, year_end  := fifelse(y, pmin(event_year, 2026L), 2026L)]
  uni <- uni[year_end >= 2012L]

  panel <- uni[rep(seq_len(.N), year_end - 2012L + 1L)]
  panel[, year := 2011L + rowid(site_id)]
  panel[, y_year := as.integer(y & year == year_end)]

  # time-varying volatility + growth expectation: grid5km cell, fallback gemeente (and
  # vice versa as variant); national series separate; last known value after the end
  vg  <- fread(cfg$file_vol_rolling("grid5km"))
  vgm <- fread(cfg$file_vol_rolling("gemeente_code"))
  vnl <- fread(cfg$file_vol_rolling("nationaal"))
  panel[, year_vol := pmin(year, max(vg$besluitjaar))]
  panel[vg,  on = .(cel = regio, year_vol = besluitjaar),           `:=`(vol_g_ = i.vol_roll5, gr_g_ = i.g_roll5)]
  panel[vgm, on = .(gemeente_code = regio, year_vol = besluitjaar), `:=`(vol_m_ = i.vol_roll5, gr_m_ = i.g_roll5)]
  panel[vnl, on = .(year_vol = besluitjaar),                        `:=`(vol_nl = i.vol_roll5, g_nl = i.g_roll5)]
  panel[, `:=`(vol_roll  = fcoalesce(vol_g_, vol_m_), g_roll  = fcoalesce(gr_g_, gr_m_),    # finest grain first
               vol_rollG = fcoalesce(vol_m_, vol_g_), g_rollG = fcoalesce(gr_m_, gr_g_))]   # gemeente primary (less measurement noise)
  panel[, year_c := year - 2019L]
  rd_log("Panel: %s site-years (%s events, %.3f%% per year); vol_roll coverage %.1f%%",
         format(nrow(panel), big.mark = ","), format(sum(panel$y_year), big.mark = ","),
         100 * mean(panel$y_year), 100 * mean(!is.na(panel$vol_roll)))
  panel
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_09", ifnotfound = FALSE))) {
  alt <- readRDS(cfg$file_alt_rds)
  s   <- readRDS(cfg$file_sites_rds)
  s1  <- readRDS(cfg$file_stage1_rds)
  panel <- build_hazard_panel(alt, s, s1)

  # Real-options spec battery (28-07 evening). NB: no update() on two-part fixest formulas.
  #  H1 vol      : year FE + regional vol (identification = regional deviation from the national cycle)
  #  H2 capozza  : H1 + growth expectation g_roll (Capozza & Li: growth AND uncertainty raise the
  #                option value of waiting; without a growth control vol is potentially biased)
  #  H3 muni     : as H2 but gemeente grain primary (less measurement noise -> less attenuation)
  #  H4 national : NO year FE; regional + national vol/growth + linear trend. Here the national
  #                volatility cycle also contributes to identification — but the national
  #                terms then absorb EVERY macro shock (interest rates, policy): explicitly
  #                labeled as indicative, not as a main result.
  f_rhs <- paste("iv + acq_mln + p_owner_occupier_buurt + p_socialhousing_buurt +",
                 "isprotectheritagearea + is_natura2000 + bouwperiode_inc")
  mk <- function(extra, fe = TRUE) as.formula(paste("y_year ~", f_rhs, "+", extra, if (fe) "| year" else ""))
  est <- panel[!is.na(vol_roll) & !is.na(g_roll) & !is.na(vol_nl)]

  fits <- list()
  fit_and_log <- function(fml, label) {
    m <- feglm(fml, data = est, family = binomial(), cluster = ~gemeente_code, glm.iter = 100)
    if (!isTRUE(m$convStatus)) rd_log("  NB: '%s' did not converge", label)
    ct <- as.data.table(summary(m)$coeftable, keep.rownames = "term")
    setnames(ct, c("term", "estimate", "se_cluster", "z", "p"))
    ct[, spec := label]
    shown <- ct[term %chin% c("vol_roll", "g_roll", "vol_rollG", "g_rollG", "vol_nl", "g_nl", "iv", "acq_mln")]
    rd_log("  %-9s: %s", label, shown[, paste(sprintf("%s %+.2f (z %.1f)", term, estimate, z), collapse = "; ")])
    ct
  }
  rd_log("Hazard specs (SE clustered on gemeente):")
  fits$H1 <- fit_and_log(mk("vol_roll"), "H1_vol")
  fits$H2 <- fit_and_log(mk("vol_roll + g_roll"), "H2_capozza")
  fits$H3 <- fit_and_log(mk("vol_rollG + g_rollG"), "H3_muni")
  fits$H4 <- fit_and_log(mk("vol_roll + g_roll + vol_nl + g_nl + year_c", fe = FALSE), "H4_national")

  specs <- rbindlist(fits)
  rd_log("Key variables H2 (main spec):")
  print(specs[spec == "H2_capozza" & !(term %like% "bouwperiode"),
              .(term, estimate = round(estimate, 4), se_cluster = round(se_cluster, 4), z = round(z, 1))])
  saveRDS(list(specs = specs, n = uniqueN(est$site_id), n_site_jaren = nrow(est), n_events = est[, sum(y_year)]),
          cfg$file_hazard_rds, compress = FALSE)
  rd_log("Written: %s", cfg$file_hazard_rds)
}
