# 00_config.R — centrale configuratie van de redevelopment-analysepijplijn (issue #16)
# Elk stap-script source't dit bestand; alle paden/parameters staan hier.
# Stijl en opzet volgen C:/ProjDir/_Tools/PriceIndices/R.

suppressPackageStartupMessages({
  library(data.table)
})

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}

rd_log <- function(fmt, ...) cat(sprintf(paste0("[%s] ", fmt, "\n"), format(Sys.time(), "%H:%M:%S"), ...))
`%||%` <- function(a, b) if (is.null(a)) b else a

## -- GeoDMS-directories via registry (zelfde bron als de GeoDMS GUI) ---------
get_geodms_dir <- function(name) {
  key <- try(utils::readRegistry("Software\\ObjectVision", hive = "HCU", maxdepth = 3), silent = TRUE)
  if (inherits(key, "try-error")) return(NULL)
  for (m in key) if (is.list(m) && !is.null(m$GeoDMS[[name]])) return(m$GeoDMS[[name]])
  NULL
}

cfg <- list()

## -- run-identificatie: welke GeoDMS-export lezen we -------------------------
cfg$area         <- "Nederland"   # Parameters/StudyArea in de GeoDMS-config
cfg$bag_date     <- "20260710"    # Parameters/BAG_file_date
cfg$nvm_filedate <- "20260711"    # Parameters/NVM_filedate (coefficienten-CSV, spec 'redev')

## -- paden --------------------------------------------------------------------
cfg$dir_localdata <- get_geodms_dir("LocalDataDir") %||% "C:/LocalData"
cfg$dir_temp      <- file.path(cfg$dir_localdata, "Redevelopment/Temp")
cfg$dir_mmd       <- file.path(cfg$dir_temp, sprintf("PerObject_Export_%s_%s.mmd", cfg$area, cfg$bag_date))
cfg$file_coef     <- file.path(cfg$dir_temp, sprintf("PriceCoefficients_WP4_%s.csv", cfg$nvm_filedate))
cfg$dir_work      <- file.path(cfg$dir_localdata, "Redevelopment/R_werk")
dir.create(cfg$dir_work, recursive = TRUE, showWarnings = FALSE)

cfg$file_perobject_rds <- file.path(cfg$dir_work, sprintf("perobject_%s_%s.rds", cfg$area, cfg$bag_date))
cfg$file_sites_rds     <- file.path(cfg$dir_work, sprintf("sites_%s_%s.rds", cfg$area, cfg$bag_date))
cfg$file_clusters_rds  <- file.path(cfg$dir_work, sprintf("clusters_%s_%s.rds", cfg$area, cfg$bag_date))

## -- classificaties (volgorde = GeoDMS-id!) -----------------------------------
# AdditionalClassifications.dms / Redev_ObjectTypes (uint8, ids 0..9)
cfg$redev_types <- c("SN_Sloop", "SN_Sloop_nw", "SN_Nieuwbouw", "Nieuwbouw", "Toevoeging",
                     "Onttrekking", "Transformatie_Plus", "Transformatie_Min", "Sloop", "Onveranderd")
# IsWoon: woonfunctie van het object in zijn (uitkomst-)toestand; voor min-rijen en Onveranderd is de rij de incumbent
cfg$redev_is_woon <- c(TRUE, FALSE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, TRUE, TRUE)
# plus-rijen beschrijven de NIEUWE staat van een site; min-rijen + Onveranderd de incumbent-staat
cfg$redev_plus  <- c("SN_Nieuwbouw", "Nieuwbouw", "Toevoeging", "Transformatie_Plus")
cfg$redev_min   <- c("SN_Sloop", "SN_Sloop_nw", "Onttrekking", "Transformatie_Min", "Sloop")

# Classifications/bag.dms / WP4 (uint8, ids 0..3)
cfg$wp4_names    <- c("vrijstaand", "twee_onder_1_kap", "rijtjeswoning", "appartement")
cfg$wp4_english  <- c("detached", "semidetached", "terraced", "apartment")

## -- parameters prijsreconstructie ---------------------------------------------
cfg$prijspeil_jaar   <- 2023      # Parameters/NVM_coeff_Year: trans_year-dummy die als prijspeil dient
cfg$ovknoop_floor    <- 0.01     # ondergrens (min) voor log(tt_ovknoop); schattingsinput had min ~0.1, tif-min ~0.087

## -- parameters k-means (stap 1, Makles 2012) ----------------------------------
cfg$kmeans_k_max     <- 20
cfg$kmeans_k_final   <- 6        # definitieve K; heroverwegen na elbow-plot
cfg$kmeans_nstart    <- 50
cfg$winsor_p         <- c(0.01, 0.99)
cfg$kmeans_seed      <- 20260716

## -- kostenkentallen (stap 2: residual value = revenue - grondproductie - bouw) --
## Bron: RSopen_NL2120 ModelParameters/Wonen (2023-waarden, consistent met prijspeil_jaar).
## Grondproductiekosten zitten als Eur/ha-grids in de export (loc_grondprod_eur_ha[_low|_high],
## 2023-peil): kosten site = Eur/ha x site_size/1e4.
cfg$prijsindex_bouw_2017_2023 <- 1.29    # CBS 83887NED, inputprijsindex bouwkosten nieuwbouw, 2017=100
# CBS 83673NED (uitgelezen sept 2025): nieuwbouw-bouwkosten Eur per m2 BVO(!), per landsdeel, 2023
cfg$bouwkosten_2023 <- data.table(
  landsdeel    = c("Noord-Nederland", "Oost-Nederland", "West-Nederland", "Zuid-Nederland"),
  koop_eur_m2  = c(1193, 1100, 1233, 1089),
  huur_eur_m2  = c(1220, 1190, 1379, 1108))
# vormfactor = woonoppervlak / BVO (PBL expert judgement): BVO = woonopp / vormfactor
cfg$vormfactor <- c(eengezins = 0.76, meergezins = 0.78, hoogbouw = 0.65)
# sloopkosten Eur per m2 footprint?/BVO, bouwkostenkompas.nl 2017-kentallen -> x index naar 2023
cfg$sloopkosten_2017 <- c(rijtjeswoning = 22, twee_onder_1_kap = 40, vrijstaand = 57,
                          appartement = 22, kantoor = 25)
cfg$sloopkosten_2023 <- cfg$sloopkosten_2017 * cfg$prijsindex_bouw_2017_2023
