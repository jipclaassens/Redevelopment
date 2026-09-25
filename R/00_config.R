# 00_config.R — central configuration of the redevelopment analysis pipeline (issue #16)
# Every step script sources this file; all paths/parameters live here.
# Style and setup follow C:/ProjDir/_Tools/PriceIndices/R.

suppressPackageStartupMessages({
  library(data.table)
})

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}

rd_log <- function(fmt, ...) cat(sprintf(paste0("[%s] ", fmt, "\n"), format(Sys.time(), "%H:%M:%S"), ...))
`%||%` <- function(a, b) if (is.null(a)) b else a

## -- GeoDMS directories via the registry (same source as the GeoDMS GUI) -----
get_geodms_dir <- function(name) {
  key <- try(utils::readRegistry("Software\\ObjectVision", hive = "HCU", maxdepth = 3), silent = TRUE)
  if (inherits(key, "try-error")) return(NULL)
  for (m in key) if (is.list(m) && !is.null(m$GeoDMS[[name]])) return(m$GeoDMS[[name]])
  NULL
}

cfg <- list()

## -- run identification: which GeoDMS export we read --------------------------
cfg$area         <- "Nederland"   # Parameters/StudyArea in the GeoDMS config
cfg$bag_date     <- "20260710"    # Parameters/BAG_file_date
cfg$nvm_filedate <- "20260711"    # Parameters/NVM_filedate (coefficients CSV, spec 'redev')

## -- paths --------------------------------------------------------------------
# GeoDMS writes to %LocalDataProjDir% = <LocalDataDir>/<name of the repo folder>. Follow the same
# rule, so the export and R_werk are found on every machine, whatever the repo folder is called there.
cfg$dir_repo <- local({
  d <- normalizePath(.rd_script_dir, winslash = "/", mustWork = FALSE)
  while (!file.exists(file.path(d, "analysis", "Redevelopment.dms")) && dirname(d) != d) d <- dirname(d)
  if (!file.exists(file.path(d, "analysis", "Redevelopment.dms")))
    stop("00_config.R: repo root (folder with analysis/Redevelopment.dms) not found above ", .rd_script_dir)
  d
})
cfg$dir_localdata <- get_geodms_dir("LocalDataDir") %||% "C:/LocalData"
cfg$dir_project   <- file.path(cfg$dir_localdata, basename(cfg$dir_repo))
cfg$dir_temp      <- file.path(cfg$dir_project, "Temp")
cfg$dir_mmd       <- file.path(cfg$dir_temp, sprintf("PerObject_Export_%s_%s.mmd", cfg$area, cfg$bag_date))
cfg$file_coef     <- file.path(cfg$dir_temp, sprintf("PriceCoefficients_WP4_%s.csv", cfg$nvm_filedate))
cfg$dir_work      <- file.path(cfg$dir_project, "R_werk")
dir.create(cfg$dir_work, recursive = TRUE, showWarnings = FALSE)

cfg$file_perobject_rds <- file.path(cfg$dir_work, sprintf("perobject_%s_%s.rds", cfg$area, cfg$bag_date))
cfg$file_sites_rds     <- file.path(cfg$dir_work, sprintf("sites_%s_%s.rds", cfg$area, cfg$bag_date))

## -- Word output: convert a markdown table file to docx via pandoc -------------
# The paper is written in Word; pandoc turns our markdown tables into real Word
# tables (RStudio bundles pandoc, so no extra R packages are needed).
cfg$pandoc <- local({
  cand <- c(Sys.which("pandoc"),
            "C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools/pandoc.exe",
            "C:/Program Files/RStudio/bin/quarto/bin/tools/pandoc.exe",
            "C:/Program Files/RStudio/bin/pandoc/pandoc.exe")
  cand <- cand[nzchar(cand) & file.exists(cand)]
  if (length(cand)) cand[1] else NA_character_
})
rd_md_to_docx <- function(md_file) {
  if (is.na(cfg$pandoc)) { rd_log("pandoc not found; no docx for %s", basename(md_file)); return(invisible(NULL)) }
  docx <- sub("[.]md$", ".docx", md_file)
  status <- system2(cfg$pandoc, c("-f", "gfm", "-t", "docx",
                                  "--resource-path", shQuote(dirname(md_file), type = "cmd"),
                                  "-o", shQuote(docx, type = "cmd"), shQuote(md_file, type = "cmd")))
  if (status == 0) rd_log("Written: %s", docx) else rd_log("pandoc failed (status %d) on %s", status, md_file)
  invisible(docx)
}
# clusters/alternatives get a sample suffix; see 'stage-1 sample' below

## -- classifications (order = GeoDMS id!) -------------------------------------
# AdditionalClassifications.dms / Redev_ObjectTypes (uint8, ids 0..9)
cfg$redev_types <- c("SN_Sloop", "SN_Sloop_nw", "SN_Nieuwbouw", "Nieuwbouw", "Toevoeging",
                     "Onttrekking", "Transformatie_Plus", "Transformatie_Min", "Sloop", "Onveranderd",
                     "Onveranderd_NW")   # id 10 (25-09): unchanged non-residential units, see 02/03
# IsWoon: residential function of the object in its (outcome) state; for min rows and Onveranderd the row is the incumbent
cfg$redev_is_woon <- c(TRUE, FALSE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, TRUE, TRUE, FALSE)
# plus rows describe the NEW state of a site; min rows + Onveranderd the incumbent state
cfg$redev_plus  <- c("SN_Nieuwbouw", "Nieuwbouw", "Toevoeging", "Transformatie_Plus")
cfg$redev_min   <- c("SN_Sloop", "SN_Sloop_nw", "Onttrekking", "Transformatie_Min", "Sloop")

# Classifications/bag.dms / WP4 (uint8, ids 0..3)
cfg$wp4_names    <- c("vrijstaand", "twee_onder_1_kap", "rijtjeswoning", "appartement")
cfg$wp4_english  <- c("detached", "semidetached", "terraced", "apartment")

# NietWoonWaardering.dms (export from 25-09): object class, floor-area flag and BAG use (uint8 codes)
cfg$nonres_classes   <- c("woon", "hal", "overig")
cfg$floor_area_flags <- c("ongewijzigd", "geen_oppervlak", "woon_groter_dan_5x_voetafdruk", "woon_afgekapt_op_500",
                          "nietwoon_afgekapt_op_pandhoogte", "nietwoon_afgekapt_op_45_lagen")
cfg$gebruiksdoelen   <- c("bijeenkomst", "cel", "gezondheidszorg", "industrie", "kantoor", "logies", "onderwijs",
                          "overige_gebruiks", "sport", "winkel", "woon", "utiliteit_combi")

## -- price reconstruction parameters -------------------------------------------
cfg$price_level_year <- 2023      # Parameters/NVM_coeff_Year: trans_year dummy that serves as the price level
cfg$ovknoop_floor    <- 0.01     # lower bound (min) for log(tt_ovknoop); estimation input had min ~0.1, tif min ~0.087
# Every non-dummy term of the hedonic model that the price formulas (02, 05) supply. read_coefficients()
# stops when the coefficient file holds another term, so an estimated term can no longer drop out
# silently. d_hoogte_onbekend is supplied as 0 on purpose (no regional average; see 02).
cfg$price_terms <- c("constant", "lnsize", "lnlotsize", "nrooms", "d_maintgood", "d_highrise", "d_hoogte_onbekend",
                     "lntt_500k_2024", "lntt_ovknoop", "uai_2012", "fr_natuur_tot2500m", "fr_water_500m")
# Export columns with the green and water shares per object (GeoDMS, added 25-09).
cfg$green_cols <- c(fr_natuur_tot2500m = "loc_fr_natuur_tot2500m", fr_water_500m = "loc_fr_water_500m")

## -- stage-1 sample: which realized sites form the menu + the choice data ----
# 'sn'    = only sloop-nieuwbouw (SN) sites (true redevelopment; recommended default)
# 'sn_tr' = SN + transformation sites
# 'alle'  = all replacement sites incl. pure new construction/additions (old behavior;
#           dominated by greenfield and 1-unit addition sites, see STATUS 27-07)
cfg$stage1_sample  <- "sn"
cfg$sample_suffix  <- if (cfg$stage1_sample == "alle") "" else paste0("_", cfg$stage1_sample)
cfg$file_clusters_rds <- file.path(cfg$dir_work, sprintf("clusters%s_%s_%s.rds", cfg$sample_suffix, cfg$area, cfg$bag_date))
cfg$file_alt_rds      <- file.path(cfg$dir_work, sprintf("alternatieven%s_%s_%s.rds", cfg$sample_suffix, cfg$area, cfg$bag_date))
cfg$file_stage1_rds   <- file.path(cfg$dir_work, sprintf("stage1%s_%s_%s.rds", cfg$sample_suffix, cfg$area, cfg$bag_date))
cfg$file_stage2_rds   <- file.path(cfg$dir_work, sprintf("stage2%s_%s_%s.rds", cfg$sample_suffix, cfg$area, cfg$bag_date))
# multi-project flag (stage-1 robustness): a site with >multiproj_n_doc document numbers AND
# >multiproj_months months of spread in the new construction counts as "lumped-together projects"
cfg$multiproj_n_doc <- 2L
cfg$multiproj_months <- 24L

## -- study area delimitation (decision 28-07 evening) ---------------------------
# Urban area via surrounding-address density (OAD, buurt level), as in the previous
# paper — replaces the earlier 22-agglomerations delimitation. CBS class boundaries:
# >=1000 = moderately urban and up (default); sensitivity 1500 (strongly urban) and
# no filter (all of NL). Applies to the estimation samples of stages 1 and 2; the
# cluster menu (04) and the IV computation (06, all sites) remain nationwide.
cfg$oad_min <- 1000L

## -- price volatility (stage-2 friction; produced by PriceIndices R/06_volatility.R) --
# sd of the year-on-year growth of the hedonically corrected local log price index, 2000-2023.
# Granularity 'grid5km' = RD cell floor(x/5000)_floor(y/5000): vintage-free join via x/y_coord.
# The OneDrive sync root differs per machine; take the first candidate that exists.
cfg$dir_nvm_output <- local({
  cand <- c("D:/OneDrive - Objectvision/VU/Projects/NVM Prijsindex/Output",
            "C:/Users/JipClaassens/OneDrive - Objectvision/VU/Projects/NVM Prijsindex/Output",
            file.path(Sys.getenv("USERPROFILE"), "OneDrive - Objectvision/VU/Projects/NVM Prijsindex/Output"))
  hit <- cand[dir.exists(cand)]
  if (length(hit)) hit[1] else cand[1]
})
cfg$file_vol        <- function(korrel) file.path(cfg$dir_nvm_output, sprintf("Volatility_%s_%s.csv", cfg$nvm_filedate, korrel))
# rolling variant (per regio x besluitjaar; for 09_hazard): sd of 5 growth years up to J-1
cfg$file_vol_rolling <- function(korrel) file.path(cfg$dir_nvm_output, sprintf("Volatility_rolling_%s_%s.csv", cfg$nvm_filedate, korrel))
cfg$vol_cel_m       <- 5000L
cfg$file_hazard_rds <- file.path(cfg$dir_work, sprintf("hazard%s_%s_%s.rds", cfg$sample_suffix, cfg$area, cfg$bag_date))

## -- k-means parameters (step 1, Makles 2012) ----------------------------------
cfg$kmeans_k_max     <- 20
cfg$kmeans_k_final   <- 6        # final K; reconsider after the elbow plot (per sample!)
cfg$kmeans_nstart    <- 50
cfg$winsor_p         <- c(0.01, 0.99)
cfg$kmeans_seed      <- 20260716

## -- cost figures (step 2: residual value = revenue - land production - construction) --
## Source: RSopen_NL2120 ModelParameters/Wonen (2023 values, consistent with price_level_year).
## Land production costs come as Eur/ha grids in the export (loc_grondprod_eur_ha[_low|_high],
## 2023 price level): site costs = Eur/ha x site_size/1e4.
cfg$construction_price_index_2017_2023 <- 1.29    # CBS 83887NED, input price index construction costs new dwellings, 2017=100
# CBS 83673NED (retrieved Sept 2025): new-construction building costs Eur per m2 GFA/BVO(!), per landsdeel, 2023
cfg$construction_costs_2023 <- data.table(
  landsdeel    = c("Noord-Nederland", "Oost-Nederland", "West-Nederland", "Zuid-Nederland"),
  koop_eur_m2  = c(1193, 1100, 1233, 1089),
  huur_eur_m2  = c(1220, 1198, 1379, 1108))
# vormfactor = living area / GFA (PBL expert judgement): GFA = living area / vormfactor
cfg$vormfactor <- c(eengezins = 0.76, meergezins = 0.78, hoogbouw = 0.65)

## -- development costs, following RuimteScanner (RSopen_NL2120 ModelParameters/Wonen, 25-09-2026) --
# Construction cost per m2 GFA differs by dwelling type (IGG kengetallen via five municipal fee
# lists, rijtjeswoning = 1). The index is normalised on the new-build mix of the owner-occupied
# sector (16% apartments; single-family mix 57.6/14.9/27.5 terraced/semi-detached/detached), so
# the mix-weighted average stays equal to the CBS figure per landsdeel. Gives 1.02/1.05/0.91/1.19.
cfg$construction_type_index <- local({
  idx  <- c(vrijstaand = 1.12, twee_onder_1_kap = 1.15, rijtjeswoning = 1.00, appartement = 1.30)
  mix1 <- c(rijtjeswoning = 0.576, twee_onder_1_kap = 0.149, vrijstaand = 0.275)
  idx / (0.16 * idx[["appartement"]] + 0.84 * sum(idx[names(mix1)] * mix1))
})
# New dwellings are sold including 21% VAT, whereas the hedonic price rests on sales of existing
# homes without VAT: the developer keeps revenue / (1 + VAT).
cfg$vat_rate <- 0.21
# Fees, advice, levies, permits and interest during construction, as a share of the construction
# sum (EIB, Kostenoptimalisatie woningbouw, March 2026: EUR 58,000 on EUR 149,300).
cfg$additional_costs_share <- 0.389
# Developer's profit and risk margin on (construction + additional costs). RuimteScanner uses 0.07
# without a source; in a model of observed choices the margin is what the estimates should reveal,
# so 0 here and 0.07 only as a sensitivity run.
cfg$developer_margin <- 0
cfg$developer_margin_sens <- 0.07   # sensitivity run (06 'margin7' variant, 07 spec 'margin7'): the RuimteScanner value

# Land under non-residential buildings (RuimteScanner ModelParameters/Wonen/Grondwaarde, #787;
# decision 25-09). The price of a dwelling covers land plus building, the non-residential price
# per m2 floor area only the building. Where no dwellings stand, the land is bought as well, at
# the RuimteScanner rate for built-up land: 100 euro per m2, the lower end of municipal land price
# letters. Applied to sites without dwellings, over the area of the original buildings (03).
cfg$land_value_builtup_eur_ha <- 1e6

# Demolition costs Eur per m2 floor area (BAG usable area), 2017 price level -> x index to 2023, as
# in RuimteScanner (ModelParameters/Wonen/Sloopkosten): the ratios between the four dwelling types
# from bouwkostenkompas, the level calibrated on EIB sector figures (about 2.2x the bouwkostenkompas
# level used before 25-09); separate rates for halls and other non-residential buildings, and an
# asbestos surcharge for non-residential buildings built before 1994.
cfg$demolition_costs_2017 <- c(rijtjeswoning = 48, twee_onder_1_kap = 88, vrijstaand = 125,
                               appartement = 48, hal = 43, overig_nietwoon = 101)
cfg$demolition_costs_2023   <- cfg$demolition_costs_2017 * cfg$construction_price_index_2017_2023
cfg$asbestos_surcharge_2023 <- 20 * cfg$construction_price_index_2017_2023
cfg$asbestos_year           <- 1994L   # non-residential buildings built before this year

## -- floor area plausibility (RuimteScanner SourceData/Vastgoed/BAG.dms, #700) --------------
# Placeholder codes and areas below 10 m2 are already handled in the GeoDMS export. On top of that:
# a dwelling larger than five times the footprint of its building is an error (-> NA), and dwellings
# above 500 m2 are capped at 500. Exports from 25-09 apply these rules in GeoDMS (obj_floor_area_clean_m2,
# which also caps non-residential units at what fits in the building); the values below are then only
# used for older exports.
cfg$floor_area_max_res            <- 500L
cfg$floor_area_max_ratio_footprint <- 5

## -- stage-2 universe (decision 25-09) -------------------------------------------------------
# The main analysis compares sites that had dwellings before: replacement of housing. Redeveloped
# sites where only non-residential buildings were demolished have no counterpart in the unchanged
# residential stock and go to a separate model (with potential sites from the unchanged
# non-residential stock as comparison group).
cfg$stage2_requires_dwellings <- TRUE

## -- alternatives-table parameters (steps 2a-2c, 05_alternatieven.R) ------------
# DECISION POINTS with defaults; see the header of 05_alternatieven.R for the rationale.
cfg$construction_costs_column <- "koop_eur_m2"  # CBS 83673NED: owner-occupied or rental figure ('huur_eur_m2')
cfg$alt_d_maintgood  <- 1              # new construction is in good maintenance state (regional average = the alternative)
cfg$vormfactor_wp4   <- c(vrijstaand = "eengezins", twee_onder_1_kap = "eengezins",
                          rijtjeswoning = "eengezins", appartement = "meergezins")  # hoogbouw (0.65) unused: no height info per cluster
