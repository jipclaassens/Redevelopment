# 07_stage2_logit.R — stap 5 (issue #16): stage-2 binomiale logit ("wordt er
# uberhaupt herontwikkeld"), een rij per site in de voorraad.
#
# Universum & uitkomst (besluiten 28-07):
#   y = 1 : SN-sites (sloop-nieuwbouw gerealiseerd 2012-2026) MET incumbent-rijen;
#           BBG-route-SN-sites (sloop voor het venster) hebben geen reconstrueerbare
#           verwerving en vallen buiten de estimatie (wel in stage 1).
#   y = 0 : potentiele sites uit de onveranderde woonvoorraad (#17, prefix Onv;
#           mmd's van voor de naamgevingsronde 27-07 gebruiken OnvS — beide herkend).
#   eruit : Sloop/Onttrekking zonder vervolg (pijplijn; robuustheid: als y=1),
#           Transformatie (buiten scope), pure nieuwbouw (geen incumbent).
#   scope : stedelijk gebied via OAD >= cfg$oad_min (besluit 28-07-avond, vervangt de
#           22 agglomeraties); sensitiviteiten OAD >= 1500 en heel NL.
#
# Schatting: fixest::feglm (logit) met standaardfouten GECLUSTERD op gemeente —
# herontwikkelingsbeslissingen binnen een gemeente delen beleid/marktschokken, dus
# i.i.d.-SE's zijn te klein. Clustering verandert de coefficienten niet.
#
# Verklaarders (theorie + fricties):
#   iv [+], acq_mln [-], p_owner_occupier_buurt [- holdout], p_socialhousing_buurt [?],
#   isprotectheritagearea [-], is_natura2000 [-], vol_dlnp [- real options],
#   bouwperiode_inc (modus bouwjaar incumbent, ref va2002) [ouder -> +, afschrijving]
#
# Specs (allemaal in de export-CSV):
#   basis      OAD>=1000, volledige covariaten
#   kaal       basis zonder bouwperiode-control (isoleert wat bouwjaar met heritage doet)
#   urban1500  OAD>=1500 (sterk stedelijk)
#   nl         geen OAD-filter
#   size       basis + ln(site_ha) (comparability-control site-vorming 10m/20m)
#   winsor     basis met iv/acq gewinsorized p1/p99 (mega-site-staarten; separation-warning)
#   vol_gem    volatiliteit met gemeente-korrel primair (i.p.v. grid5km-eerst)
#   sloopstart S-sites (sloop zonder vervolg = onomkeerbare start) tellen als y=1;
#              Onttrekking blijft er ook hier uit (overwegend administratief, en de
#              78k O-sites gaven een vlakke likelihood / quasi-separatie)
#   excl2012   basis zonder sites met 2012-dubbeltellingsverdenking (#26: nieuwbouw
#              geregistreerd in 2012 met bouwjaar <= 2010 = vermoedelijk Woningregister-
#              administratie, geen echte herontwikkeling)
#   bbg_imput  basis + de BBG-route-SN-sites (geen slooprijen in het venster) als y=1,
#              met GEIMPUTEERDE verwerving (mediaan acq/ha van waargenomen SN-sites x
#              site_ha); zonder bouwperiode-control (incumbent onbekend bij die sites)
#
# Output: cfg$file_stage2_rds + R_werk/stage2_specs<suffix>_<area>_<date>.csv
# (term;estimate;se_cluster;z;spec;n;n_y1) + AME's van de kernvariabelen (basis).

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))
source(file.path(.rd_script_dir, "02_load_perobject.R"))   # voor bouwperiode_term()
suppressPackageStartupMessages(library(fixest))

maak_stage2_input <- function(alt, s, s1) {
  st <- alt$sites
  # BBG-route-SN-sites (heeft_incumbent == FALSE): alleen voor de imputatie-spec
  uni <- st[heeft_incumbent == TRUE | site_id %like% "^SN_"]
  uni[, prefix := sub("_.*$", "", site_id)]
  uni[prefix == "OnvS", prefix := "Onv"]                       # oude naamgeving (mmd < 28-07)
  uni <- uni[prefix %chin% c("SN", "Onv", "S", "O")]           # TMmin buiten scope
  uni[, y := prefix == "SN"]
  uni[, pijplijn := prefix %chin% c("S", "O")]
  uni[, bbg_sn := heeft_incumbent == FALSE]
  uni[bbg_sn == TRUE, `:=`(acq_cost_total_eur = NA_real_, sloop_cost_eur = NA_real_)]  # 05 zette 0; hier echt onbekend
  rd_log("BBG-route-SN-sites (verwerving onbekend, alleen imputatie-spec): %s",
         format(uni[bbg_sn == TRUE, .N], big.mark = ","))

  uni[s1$iv, on = "site_id", iv := i.iv]
  uni[, acq_mln := acq_cost_total_eur / 1e6]
  uni[, ln_site_ha := log(site_ha)]

  # bouwperiode incumbent (modus bouwjaar per site; onbekend als eigen niveau — niets weggooien)
  uni[s$incumbent, on = "site_id", modus_bouwjaar := i.modus_bouwjaar]
  uni[, bouwperiode_inc := factor(fifelse(is.na(modus_bouwjaar), "bp_onbekend", bouwperiode_term(modus_bouwjaar)))]
  uni[, bouwperiode_inc := relevel(bouwperiode_inc, "bouwperiode_va2002")]

  # volatiliteit: grid5km-cel uit RD-coordinaten + gemeente-variant (2024-codes: matcht
  # alleen waar de GM-code sinds onze 2012-indeling ongewijzigd is)
  vol_g  <- fread(cfg$file_vol("grid5km"))
  vol_gm <- fread(cfg$file_vol("gemeente_code"))
  uni[, cel := paste0(x_coord %/% cfg$vol_cel_m, "_", y_coord %/% cfg$vol_cel_m)]
  uni[vol_g,  on = .(cel = regio),           vol_grid_ := i.vol_dlnp]
  uni[vol_gm, on = .(gemeente_code = regio), vol_gem_  := i.vol_dlnp]
  uni[, vol_dlnp     := fcoalesce(vol_grid_, vol_gem_)]   # basis: fijnste korrel eerst
  uni[, vol_dlnp_gem := fcoalesce(vol_gem_, vol_grid_)]   # variant: gemeente primair
  rd_log("Volatiliteit: grid5km %.1f%%, met gemeente-fallback %.1f%%",
         100 * uni[, mean(!is.na(vol_grid_))], 100 * uni[, mean(!is.na(vol_dlnp))])

  # 2012-dubbeltellingsflag (#26) zit op de plus-kant (sites_nieuw)
  uni[s$nieuw, on = "site_id", n_flag_2012 := i.n_flag_2012]
  uni[is.na(n_flag_2012), n_flag_2012 := 0L]
  uni[]
}

schat_stage2 <- function(uni) {
  f_basis <- y ~ iv + acq_mln + p_owner_occupier_buurt + p_socialhousing_buurt +
                 isprotectheritagearea + is_natura2000 + vol_dlnp + bouwperiode_inc
  vars <- setdiff(all.vars(f_basis), "bouwperiode_inc")
  w    <- function(v) { q <- quantile(v, c(.01, .99), na.rm = TRUE); pmin(pmax(v, q[1]), q[2]) }

  # sites zonder bouwjaar: quasi-separatie (vrijwel geen events op de bp_onbekend-dummy laat de
  # likelihood vlak doordraaien) -> uit de estimatie; in het stedelijke sample gaat het om ~5 sites.
  # BBG-SN-sites (per definitie zonder incumbent-bouwjaar) blijven staan voor de imputatie-spec.
  n_onb <- uni[bbg_sn == FALSE & bouwperiode_inc == "bp_onbekend", .N]
  uni   <- uni[bbg_sn == TRUE | bouwperiode_inc != "bp_onbekend"]
  rd_log("Sites met onbekend bouwjaar uit de estimatie: %s", format(n_onb, big.mark = ","))

  kern <- uni[pijplijn == FALSE & bbg_sn == FALSE]
  kern <- kern[complete.cases(kern[, ..vars]) & !is.na(oad)]
  urb  <- function(d, oad_min) d[oad >= oad_min]

  fit1 <- function(fml, d, label) {
    d <- copy(d)[, bouwperiode_inc := droplevels(bouwperiode_inc)]
    m <- feglm(fml, data = d, family = binomial(), cluster = ~gemeente_code, glm.iter = 100)
    if (!isTRUE(m$convStatus)) rd_log("    NB: '%s' niet geconvergeerd — check separatie", label)
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

  rd_log("Specs (SE geclusterd op gemeente):")
  basis  <- urb(kern, cfg$oad_min)
  f_kaal <- update(f_basis, . ~ . - bouwperiode_inc)

  # BBG-imputatie-sample: verwerving = mediaan acq/ha van de waargenomen SN-sites x site_ha
  acq_rate <- basis[y == TRUE, median(acq_mln / site_ha)]
  bbg <- uni[bbg_sn == TRUE & !is.na(oad) & oad >= cfg$oad_min]
  bbg[, acq_mln := acq_rate * site_ha]
  bbg <- bbg[complete.cases(bbg[, ..vars])]
  rd_log("BBG-imputatie: %s sites erbij als y=1 (acq = %.2f M/ha x site_ha)", format(nrow(bbg), big.mark = ","), acq_rate)

  fits <- list(
    basis     = fit1(f_basis, basis, "basis"),
    kaal      = fit1(f_kaal, basis, "kaal"),
    urban1500 = fit1(f_basis, urb(kern, 1500L), "urban1500"),
    nl        = fit1(f_basis, kern, "nl"),
    size      = fit1(update(f_basis, . ~ . + ln_site_ha), basis, "size"),
    winsor    = fit1(f_basis, copy(basis)[, `:=`(iv = w(iv), acq_mln = w(acq_mln))], "winsor"),
    vol_gem   = fit1(update(f_basis, . ~ . - vol_dlnp + vol_dlnp_gem), basis, "vol_gem"),
    sloopstart = fit1(f_basis, { d <- uni[prefix != "O" & bbg_sn == FALSE]
                                 d <- d[complete.cases(d[, ..vars]) & !is.na(oad) & oad >= cfg$oad_min]
                                 d[, y := prefix != "Onv"]; d }, "sloopstart"),
    excl2012  = fit1(f_basis, basis[n_flag_2012 == 0L], "excl2012"),
    bbg_imput = fit1(f_kaal, rbind(basis, bbg), "bbg_imput"))

  # AME's (basis): gemiddeld marginaal effect op P(herontwikkeling), logit: mean(p(1-p)) x beta
  p <- predict(fits$basis$m, type = "response")
  schaal <- mean(p * (1 - p))
  ame <- fits$basis$ct[term %chin% c("iv", "acq_mln", "vol_dlnp", "p_owner_occupier_buurt"),
                       .(term, ame = schaal * estimate)]
  list(fits = fits, ame = ame, basis_n = nrow(basis))
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_07", ifnotfound = FALSE))) {
  alt <- readRDS(cfg$file_alt_rds)
  s   <- readRDS(cfg$file_sites_rds)
  s1  <- readRDS(cfg$file_stage1_rds)
  uni <- maak_stage2_input(alt, s, s1)
  r   <- schat_stage2(uni)

  rd_log("Hoofdmodel (basis, OAD >= %d) — volledige tabel:", cfg$oad_min)
  print(r$fits$basis$ct[, .(term, estimate = round(estimate, 4), se_cluster = round(se_cluster, 4), z = round(z, 1))])
  rd_log("McFadden R2 (basis): %.3f", r2(r$fits$basis$m, "pr2"))
  rd_log("AME's (procentpunt op P(herontwikkeling), basis):")
  print(r$ame[, .(term, ame_pp = round(100 * ame, 4))])

  specs <- rbindlist(lapply(r$fits, `[[`, "ct"))
  bestand <- file.path(cfg$dir_work, sprintf("stage2_specs%s_%s_%s.csv", cfg$sample_suffix, cfg$area, cfg$bag_date))
  fwrite(specs, bestand, sep = ";")
  saveRDS(list(specs = specs, ame = r$ame, coef = coef(r$fits$basis$m), vcov = vcov(r$fits$basis$m)),
          cfg$file_stage2_rds, compress = FALSE)
  rd_log("Weggeschreven: %s + %s", cfg$file_stage2_rds, bestand)
}
