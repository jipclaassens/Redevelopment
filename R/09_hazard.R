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
#  - iv and acquisition per hectare with ln(site area) as control, as in the stage-2 base
#    spec (decision 25-09; see 06/07).
#  - iv/acquisition/frictions time-invariant (2023 level); year fixed effects capture the
#    national price cycle and the baseline hazard; 2026 is half a year (BAG through July) —
#    the year dummy captures that level.
#  - feglm logit with year FE, SE clustered on gemeente.
#
# Output: cfg$file_hazard_rds (coefficient tables main model + variant without vol; n's).

# Locate the folder this script lives in, so the source() below finds its sibling script
# from any working directory: under Rscript the path comes from the --file= argument,
# in an interactive session it falls back to getwd().
if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
# Load the helper functions and config from script 07 WITHOUT re-running its estimation:
# run_07 is forced to FALSE while sourcing (07 checks that flag), then restored afterwards.
run_07_saved <- get0("run_07", ifnotfound = FALSE); run_07 <- FALSE
source(file.path(.rd_script_dir, "07_stage2_logit.R"))   # build_stage2_input + config/fixest
run_07 <- run_07_saved

build_hazard_panel <- function(alt, s, s1) {
  # Build the site x year risk panel. Start from the stage-2 universe (one row per site)
  # and keep only sites where the hazard clock is well defined: no BBG-SN (start year
  # unknown), no pipeline sites, and a known building period of the incumbent.
  # droplevels then removes the factor levels emptied by this filter, so the regression
  # later does not create dummies for categories with zero observations.
  uni <- build_stage2_input(alt, s, s1)
  uni <- uni[bbg_sn == FALSE & pipeline == FALSE & bouwperiode_inc != "bp_onbekend"]
  if (isTRUE(cfg$stage2_requires_dwellings)) uni <- uni[inc_has_dwellings == TRUE]   # replacement of housing (25-09)
  uni[, bouwperiode_inc := droplevels(bouwperiode_inc)]
  # Update join: each site_id of uni is looked up in s$incumbent, and := writes the matched
  # event_yearmonth into uni itself as event_ym (the i. prefix = "column from the joined
  # table"). This is the first minus-mutation date, used as the redevelopment decision
  # moment. See README, data.table primer, for update joins.
  uni[s$incumbent, on = "site_id", event_ym := i.event_yearmonth]

  # Estimation-sample filter: keep only sites where all listed regressors are observed
  # (complete.cases; ..vars means "the columns named in the vars vector") and where OAD
  # meets the configured density threshold, mirroring the stage-2 sample.
  vars <- c("iv", "acq_ha", "ln_site_ha", "p_owner_occupier_buurt", "p_socialhousing_buurt",
            "isprotectheritagearea")
  uni <- uni[complete.cases(uni[, ..vars]) & is.finite(ln_site_ha) & !is.na(oad) & oad >= cfg$oad_min]
  # Redeveloped sites (y = TRUE) without an event date cannot be placed on the time axis;
  # count them for the log, then drop them. Censored sites (y = FALSE) need no date.
  n_without_event <- uni[y == TRUE & is.na(event_ym), .N]
  uni <- uni[y == FALSE | !is.na(event_ym)]
  rd_log("Hazard universe: %s sites (y=1: %s; %s SN sites without event date dropped)",
         format(nrow(uni), big.mark = ","), format(uni[, sum(y)], big.mark = ","),
         format(n_without_event, big.mark = ","))

  # Last at-risk year per site: event_ym is coded YYYYMM, so integer division %/% 100
  # extracts the year. Redeveloped sites leave the risk set in their event year (capped at
  # 2026); censored sites stay at risk through 2026. Events before the 2012 panel start
  # have no at-risk years inside the window and are dropped.
  uni[, event_year := fifelse(y, event_ym %/% 100L, NA_integer_)]
  uni[, year_end  := fifelse(y, pmin(event_year, 2026L), 2026L)]
  uni <- uni[year_end >= 2012L]

  # Row expansion into the panel: rep(seq_len(.N), k) repeats each site's row k times,
  # once for every year the site is at risk (2012 through year_end). rowid(site_id) then
  # numbers those copies 1,2,3,... within each site, which 2011L + turns into the calendar
  # year. y_year is the discrete-time hazard outcome: 1 only in the site's own event year.
  panel <- uni[rep(seq_len(.N), year_end - 2012L + 1L)]
  panel[, year := 2011L + rowid(site_id)]
  panel[, y_year := as.integer(y & year == year_end)]

  # time-varying volatility + growth expectation: grid5km cell, fallback gemeente (and
  # vice versa as variant); national series separate; last known value after the end
  # Mechanics: fread loads the three volatility CSVs; three update joins then write the
  # matched vol/growth values into the panel by reference (:=). The join key can rename on
  # the fly: on = .(cel = regio, year_vol = besluitjaar) matches panel$cel to csv$regio and
  # panel$year_vol to csv$besluitjaar. year_vol caps the lookup year at the last year the
  # series covers, so later panel years reuse the last known value (carry-forward).
  # fcoalesce takes the first non-missing value per row, implementing the fallback order:
  # vol_roll prefers grid5km with gemeente as backup, vol_rollG the other way around.
  # See README, data.table primer, for update joins.
  vg  <- fread(cfg$file_vol_rolling("grid5km"))
  vgm <- fread(cfg$file_vol_rolling("gemeente_code"))
  vnl <- fread(cfg$file_vol_rolling("nationaal"))
  panel[, year_vol := pmin(year, max(vg$besluitjaar))]
  panel[vg,  on = .(cel = regio, year_vol = besluitjaar),           `:=`(vol_g_ = i.vol_roll5, gr_g_ = i.g_roll5)]
  panel[vgm, on = .(gemeente_code = regio, year_vol = besluitjaar), `:=`(vol_m_ = i.vol_roll5, gr_m_ = i.g_roll5)]
  panel[vnl, on = .(year_vol = besluitjaar),                        `:=`(vol_nl = i.vol_roll5, g_nl = i.g_roll5)]
  panel[, `:=`(vol_roll  = fcoalesce(vol_g_, vol_m_), g_roll  = fcoalesce(gr_g_, gr_m_),    # finest grain first
               vol_rollG = fcoalesce(vol_m_, vol_g_), g_rollG = fcoalesce(gr_m_, gr_g_))]   # gemeente primary (less measurement noise)
  # Center the calendar year on 2019 (roughly mid-panel); used as linear trend in spec H4.
  panel[, year_c := year - 2019L]
  rd_log("Panel: %s site-years (%s events, %.3f%% per year); vol_roll coverage %.1f%%",
         format(nrow(panel), big.mark = ","), format(sum(panel$y_year), big.mark = ","),
         100 * mean(panel$y_year), 100 * mean(!is.na(panel$vol_roll)))
  panel
}

## ---------------------------------------------------------------------------
# The estimation below runs only when this file is executed directly (sys.nframe() == 0)
# or when a caller explicitly sets run_09 <- TRUE; sourcing the file just for the function
# above stays side-effect free.
if (sys.nframe() == 0L || isTRUE(get0("run_09", ifnotfound = FALSE))) {
  # Load the objects saved by earlier pipeline steps, then build the site x year panel.
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
  # Common right-hand side shared by all four specs; mk() appends the spec-specific
  # volatility terms and, unless fe = FALSE, the year fixed effects ("| year" is fixest
  # notation for fixed effects). est keeps only site-years where every volatility series
  # is observed, so H1-H4 are all estimated on the identical sample and are comparable.
  # Natura 2000 is left out here too, matching the stage-2 base spec (see the note in 07).
  f_rhs <- paste("iv + acq_ha + ln_site_ha + p_owner_occupier_buurt + p_socialhousing_buurt +",
                 "isprotectheritagearea + bouwperiode_inc")
  mk <- function(extra, fe = TRUE) as.formula(paste("y_year ~", f_rhs, "+", extra, if (fe) "| year" else ""))
  est <- panel[!is.na(vol_roll) & !is.na(g_roll) & !is.na(vol_nl)]

  # Helper: fit one binomial logit with fixest::feglm, SE clustered on gemeente; convert
  # the coefficient table into a data.table, tag it with the spec label, and log the key
  # coefficients. %chin% is data.table's fast %in% for character vectors.
  fits <- list()
  fit_and_log <- function(fml, label) {
    m <- feglm(fml, data = est, family = binomial(), cluster = ~gemeente_code,
               glm.iter = 100, glm.tol = 1e-6)   # see the glm.tol note in 07
    if (!isTRUE(m$convStatus)) rd_log("  NB: '%s' did not converge", label)
    ct <- as.data.table(summary(m)$coeftable, keep.rownames = "term")
    setnames(ct, c("term", "estimate", "se_cluster", "z", "p"))
    ct[, spec := label]
    shown <- ct[term %chin% c("vol_roll", "g_roll", "vol_rollG", "g_rollG", "vol_nl", "g_nl", "iv", "acq_ha")]
    rd_log("  %-9s: %s", label, shown[, paste(sprintf("%s %+.2f (z %.1f)", term, estimate, z), collapse = "; ")])
    ct
  }
  rd_log("Hazard specs (SE clustered on gemeente):")
  fits$H1 <- fit_and_log(mk("vol_roll"), "H1_vol")
  fits$H2 <- fit_and_log(mk("vol_roll + g_roll"), "H2_capozza")
  fits$H3 <- fit_and_log(mk("vol_rollG + g_rollG"), "H3_muni")
  fits$H4 <- fit_and_log(mk("vol_roll + g_roll + vol_nl + g_nl + year_c", fe = FALSE), "H4_national")

  # Stack the four per-spec coefficient tables into one long table (rbindlist), print the
  # headline H2 estimates, and save results plus sample sizes to cfg$file_hazard_rds.
  specs <- rbindlist(fits)
  rd_log("Key variables H2 (main spec):")
  print(specs[spec == "H2_capozza" & !(term %like% "bouwperiode"),
              .(term, estimate = round(estimate, 4), se_cluster = round(se_cluster, 4), z = round(z, 1))])
  saveRDS(list(specs = specs, n = uniqueN(est$site_id), n_site_jaren = nrow(est), n_events = est[, sum(y_year)]),
          cfg$file_hazard_rds, compress = FALSE)
  rd_log("Written: %s", cfg$file_hazard_rds)
}
