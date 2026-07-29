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
cfg$dir_localdata <- get_geodms_dir("LocalDataDir") %||% "C:/LocalData"
cfg$dir_temp      <- file.path(cfg$dir_localdata, "Redevelopment/Temp")
cfg$dir_mmd       <- file.path(cfg$dir_temp, sprintf("PerObject_Export_%s_%s.mmd", cfg$area, cfg$bag_date))
cfg$file_coef     <- file.path(cfg$dir_temp, sprintf("PriceCoefficients_WP4_%s.csv", cfg$nvm_filedate))
cfg$dir_work      <- file.path(cfg$dir_localdata, "Redevelopment/R_werk")
dir.create(cfg$dir_work, recursive = TRUE, showWarnings = FALSE)

cfg$file_perobject_rds <- file.path(cfg$dir_work, sprintf("perobject_%s_%s.rds", cfg$area, cfg$bag_date))
cfg$file_sites_rds     <- file.path(cfg$dir_work, sprintf("sites_%s_%s.rds", cfg$area, cfg$bag_date))
# clusters/alternatives get a sample suffix; see 'stage-1 sample' below

## -- classifications (order = GeoDMS id!) -------------------------------------
# AdditionalClassifications.dms / Redev_ObjectTypes (uint8, ids 0..9)
cfg$redev_types <- c("SN_Sloop", "SN_Sloop_nw", "SN_Nieuwbouw", "Nieuwbouw", "Toevoeging",
                     "Onttrekking", "Transformatie_Plus", "Transformatie_Min", "Sloop", "Onveranderd")
# IsWoon: residential function of the object in its (outcome) state; for min rows and Onveranderd the row is the incumbent
cfg$redev_is_woon <- c(TRUE, FALSE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, TRUE, TRUE)
# plus rows describe the NEW state of a site; min rows + Onveranderd the incumbent state
cfg$redev_plus  <- c("SN_Nieuwbouw", "Nieuwbouw", "Toevoeging", "Transformatie_Plus")
cfg$redev_min   <- c("SN_Sloop", "SN_Sloop_nw", "Onttrekking", "Transformatie_Min", "Sloop")

# Classifications/bag.dms / WP4 (uint8, ids 0..3)
cfg$wp4_names    <- c("vrijstaand", "twee_onder_1_kap", "rijtjeswoning", "appartement")
cfg$wp4_english  <- c("detached", "semidetached", "terraced", "apartment")

## -- price reconstruction parameters -------------------------------------------
cfg$price_level_year <- 2023      # Parameters/NVM_coeff_Year: trans_year dummy that serves as the price level
cfg$ovknoop_floor    <- 0.01     # lower bound (min) for log(tt_ovknoop); estimation input had min ~0.1, tif min ~0.087

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
cfg$dir_nvm_output  <- "C:/Users/JipClaassens/OneDrive - Objectvision/VU/Projects/NVM Prijsindex/Output"
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
  huur_eur_m2  = c(1220, 1190, 1379, 1108))
# vormfactor = living area / GFA (PBL expert judgement): GFA = living area / vormfactor
cfg$vormfactor <- c(eengezins = 0.76, meergezins = 0.78, hoogbouw = 0.65)
# demolition costs Eur per m2 footprint?/GFA, bouwkostenkompas.nl 2017 figures -> x index to 2023
cfg$demolition_costs_2017 <- c(rijtjeswoning = 22, twee_onder_1_kap = 40, vrijstaand = 57,
                          appartement = 22, kantoor = 25)
cfg$demolition_costs_2023 <- cfg$demolition_costs_2017 * cfg$construction_price_index_2017_2023

## -- alternatives-table parameters (steps 2a-2c, 05_alternatieven.R) ------------
# DECISION POINTS with defaults; see the header of 05_alternatieven.R for the rationale.
cfg$construction_costs_column <- "koop_eur_m2"  # CBS 83673NED: owner-occupied or rental figure ('huur_eur_m2')
cfg$alt_d_maintgood  <- 1              # new construction is in good maintenance state (regional average = the alternative)
cfg$vormfactor_wp4   <- c(vrijstaand = "eengezins", twee_onder_1_kap = "eengezins",
                          rijtjeswoning = "eengezins", appartement = "meergezins")  # hoogbouw (0.65) unused: no height info per cluster
