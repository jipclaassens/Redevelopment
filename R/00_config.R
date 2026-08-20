# 00_config.R — central configuration of the Cities-paper neighbourhood analysis.
# Every step script sources this file; all paths/parameters live here.
# Style and setup follow C:/ProjDir/EconLogicPaper/R.
#
# This pipeline replaces stata/Redevelopment_regressie.do (Stata licence expired).
# Stage 1 of the port is a FAITHFUL translation: it must reproduce Tables 2-4 of the
# first submission before any reviewer-driven change is made. 04_validate.R checks that.

suppressPackageStartupMessages({
  library(data.table)
})

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}

rd_log <- function(fmt, ...) cat(sprintf(paste0("[%s] ", fmt, "\n"), format(Sys.time(), "%H:%M:%S"), ...))
`%||%` <- function(a, b) if (is.null(a)) b else a

cfg <- list()

## -- run identification --------------------------------------------------------
# Working vintage: the export the revision is built on. It uses the same identification
# logic as the first submission but a newer BAG source file, so the counts are about 5%
# higher (net additions 972,611 against 923,895) while the composition is unchanged
# (55.1% within the existing urban fabric in both).
cfg$filedate <- "20260820"

# Replication baseline: the vintage the first submission was estimated on. 04_validate.R
# pins to this and must keep passing, so that any change in results is traceable to a
# deliberate decision rather than to the rewrite.
#
# NOTE: the do-file says `global filedate = 20250603`, but that export does NOT reproduce
# the published tables. In Analyse_PerWijk_20250603.csv, GeoDMS wrote null instead of 0 for
# WegSpoor_area and Water_area in the 1,311 neighbourhoods without roads/railways or surface
# water, which propagated into land_area and p_onbebouwd and halved every estimation sample.
# That was a GeoDMS bug and is fixed in the 20260812 export.
cfg$filedate_published <- "20250602"

## -- paths ---------------------------------------------------------------------
# The paper project lives on OneDrive and the sync root differs per machine; take the
# first candidate that exists (same pattern as EconLogicPaper cfg$dir_nvm_output).
cfg$dir_project <- local({
  cand <- c("D:/OneDrive - Objectvision/VU/Projects/202008-RedevelopmentPaper",
            "C:/Users/JipClaassens/OneDrive - Objectvision/VU/Projects/202008-RedevelopmentPaper",
            file.path(Sys.getenv("USERPROFILE"), "OneDrive - Objectvision/VU/Projects/202008-RedevelopmentPaper"))
  hit <- cand[dir.exists(cand)]
  if (length(hit)) hit[1] else cand[1]
})
cfg$file_perwijk <- function(fd = cfg$filedate)
  file.path(cfg$dir_project, "Data", sprintf("Analyse_PerWijk_%s.csv", fd))
# Monthly series: totals per process, and the same totals restricted to objects inside the 2012
# built-up contour. The pair gives the measured share of each process realised inside the contour,
# which the neighbourhood export cannot provide.
cfg$file_monthly <- function(fd = cfg$filedate)
  file.path(cfg$dir_project, "Data", sprintf("Count_PerRedevType_PerVerslagMaand_%s.csv", fd))
cfg$file_monthly_inside <- function(fd = cfg$filedate)
  file.path(cfg$dir_project, "Data", sprintf("Count_BinnenBBG2012_PerVerslagMaand_%s.csv", fd))

# Neighbourhood x year panel; the only source of the 2007 residual land value.
cfg$file_perwijk_jaar <- file.path(cfg$dir_project, "Data", "Analyse_PerWijk_x_Jaar_20250318.csv")

# External sources, reached through the GeoDMS source-data root (registry SourceDataDir).
cfg$dir_sourcedata <- local({
  cand <- c("D:/SourceData", "C:/SourceData")
  hit <- cand[dir.exists(cand)]; if (length(hit)) hit[1] else cand[1]
})
# CBS 2012 boundaries: used only for neighbourhood centroids (Moran's I). Layer
# `wijk_gegeneraliseerd`, 2,621 features, EPSG:28992 (RD New), key `statcode` = WK code.
cfg$file_wijk_gpkg <- file.path(cfg$dir_sourcedata, "RSOpen/RegioIndelingen/cbsgebiedsindelingen2012.gpkg")
# WOZ value per m2 per neighbourhood; `r2017` is the numeric WK code, `bg2015_groep` 1 =
# residential land use. Reference date 2018, i.e. AFTER the start of the study period.
cfg$file_woz <- file.path(cfg$dir_sourcedata, "RSOpen/Vastgoed/WOZ/190215_wijk_woz.csv")

cfg$dir_work <- file.path(cfg$dir_project, "Output", "R")
dir.create(cfg$dir_work, recursive = TRUE, showWarnings = FALSE)

cfg$file_wijk_rds   <- file.path(cfg$dir_work, sprintf("perwijk_%s.rds", cfg$filedate))
cfg$file_models_rds <- file.path(cfg$dir_work, sprintf("models_%s.rds", cfg$filedate))

## -- optional covariates, present from the 20260812 export onwards ------------------
# Added at the referees' request; 01_load_perwijk.R picks them up when the columns exist so
# that older vintages still load. Demographics and address density are 2012; the travel
# times are 2020 grids and therefore post-treatment (robustness only).
cfg$extra_vars <- c(
  aant_inw        = "Population",
  gem_hh_gr       = "Average household size",
  p_65_eo_jr      = "Population aged 65 and over (%)",
  p_25_44_jr      = "Population aged 25-44 (%)",
  avg_tt_100k_inw = "Travel time to 100k inhabitants (min)",
  avg_tt_500k_inw = "Travel time to 500k inhabitants (min)")

## -- benchmark for the built-up contour -------------------------------------------
# Share of the standing residential stock (type Onveranderd) that lies INSIDE the 2012 contour.
# Read from GeoDMS, Analyse/Redev_obv_hele_bag/Voorraad_x_BBG2012/Aandeel_binnen, because the
# monthly series cannot carry it: unchanged units have no mutation month. Refresh alongside the
# export. Vintage 20260820: 6,542,427 of 7,126,659.
#
# It matters because a process being "outside the contour" is only meaningful against how much of
# the stock is out there to begin with. Without it, 13% outside reads as small when it is in fact
# well above the stock share.
cfg$stock_inside_contour <- 0.9180216143356936

## -- estimation settings -------------------------------------------------------
# Stata `reg ..., r` is HC1 (White with the n/(n-k) small-sample adjustment).
# fixest's vcov = "hetero" applies the same adjustment by default, so the two match.
cfg$vcov_main <- "hetero"

# Reference category for the construction-period dummies. In Stata this is `ib5.`,
# i.e. the FIFTH level of the encoded variable. `encode` numbers levels alphabetically,
# and because every label starts with "Construction " followed by a year, alphabetical
# order equals chronological order here — level 5 is 1971-1980.
cfg$cp_ref <- "Construction 1971-1980"

# Significance stars. NOTE: the do-file is internally inconsistent here. outreg2 (upper
# panels of Tables 3 and 4) uses 0.01/0.05/0.10, but the hand-rolled `putexcel` margins
# block (lower panel of Table 4, do-file lines 319-338) uses 0.001/0.01/0.05. Both table
# footnotes claim 0.01/0.05/0.10. We reproduce both variants so the replication check can
# match the published tables cell by cell; `cfg$stars_main` is what the revision should use
# everywhere once the tables are rebuilt.
cfg$stars_main    <- c(0.01, 0.05, 0.10)   # outreg2 convention, matches the table footnotes
cfg$stars_margins <- c(0.001, 0.01, 0.05)  # putexcel convention used for the published AMEs

## -- density categories ---------------------------------------------------------
# GeoDMS Classifications.dms/UrbanisationK, exported as UrbanisationK_rel (uint8).
# Verified against the data: WK000300 (OAD 1001) -> 1, WK000700 (OAD 124) -> 2.
# CBS urbanity classes are aggregated from five to three: >=1500 high, 500-1500 medium,
# <500 low addresses per km2.
cfg$urb_levels  <- c("0" = "High density", "1" = "Medium density", "2" = "Low density")
cfg$urb_ref     <- "High density"   # Stata base level (i.urbanisationk_rel, base = 0)

## -- regions -----------------------------------------------------------------------
# Province names as the 20260812 export writes them, with underscores turned into hyphens.
# Older vintages carry no province; 05_revision.R then joins provincie_rel (0-11, the row
# order of the CBS 2012 province layer) from the neighbourhood x year panel instead.
cfg$provinces <- c("Groningen", "Friesland", "Drenthe", "Overijssel", "Flevoland", "Gelderland",
                   "Utrecht", "Noord-Holland", "Zuid-Holland", "Zeeland", "Noord-Brabant", "Limburg")
# Randstad as a province approximation. The conurbation does not follow province borders, so
# this is a proxy; Flevoland is included because Almere and Lelystad function as overspill.
cfg$randstad <- c("Utrecht", "Noord-Holland", "Zuid-Holland", "Flevoland")

## -- outcome definitions ---------------------------------------------------------
# One entry per column of Tables 3 and 4. `expr` is evaluated inside the data.table and
# gives the COUNT that is divided by land area in hectares before taking logs.
#
# WARNING (carried over deliberately, do not "fix" here — see 04_validate.R):
#   - `all` and `nb` are GROSS counts, the other three are NET. The manuscript describes
#     all five as net additions, which is wrong for columns 1 and 3.
#   - log() of zero or a negative net change is missing, so neighbourhoods without net
#     growth drop out of the estimation sample. That is the selection problem the revision
#     has to address; it is reproduced faithfully here.
cfg$outcomes <- list(
  all = list(label = "All",             expr = quote(count_sn_nieuwbouw + count_nieuwbouw + count_toevoeging + count_transformatie_plus)),
  sn  = list(label = "Replacement",     expr = quote(count_sn_nieuwbouw - count_sn_sloop)),
  nb  = list(label = "New build",       expr = quote(count_nieuwbouw)),
  div = list(label = "Within-building", expr = quote(count_toevoeging - count_onttrekking)),
  trf = list(label = "Transf.",         expr = quote(count_transformatie_plus - count_transformatie_min))
)

## -- new build split by the 2000 built-up area contour (reviewer 1, comment 1) -------
# Present from the export that carries count_Nieuwbouw_infill / _expansion. 01_load_perwijk.R
# appends these to cfg$outcomes when the columns exist, so every downstream script picks them
# up without further changes; on older exports the pipeline runs unchanged.
cfg$outcomes_nb_split <- list(
  nb_in  = list(label = "New build: infill",    expr = quote(count_nieuwbouw_infill)),
  nb_out = list(label = "New build: expansion", expr = quote(count_nieuwbouw_expansion))
)

## -- Word output: convert a markdown table file to docx via pandoc ----------------
# The paper is written in Word; pandoc turns our markdown tables into real Word tables
# (RStudio bundles pandoc, so no extra R packages are needed).
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

## -- Stata-compatible helpers -----------------------------------------------------
# Stata's ln() returns MISSING for zero and for negative arguments; R's log() returns
# -Inf and NaN (with a warning). Every log in this pipeline must go through this helper,
# otherwise the estimation sample silently differs from the published tables.
stata_log <- function(x) {
  out <- rep(NA_real_, length(x))
  ok <- !is.na(x) & x > 0
  out[ok] <- log(x[ok])
  out
}

# Stata allows unambiguous abbreviation of variable names, which the do-file relies on
# throughout (`wegspoor` for wegspoor_area, `opp_besch` for opp_BeschStadDorpgezichten2020,
# `mean_uai` for mean_UAI_2012, ...). The exported column names also drift between GeoDMS
# vintages. This resolves a prefix to exactly one column, and fails loudly otherwise.
pick_col <- function(dt, prefix) {
  hit <- grep(paste0("^", prefix), names(dt), value = TRUE)
  if (length(hit) == 1L) return(hit)
  if (length(hit) == 0L) stop(sprintf("No column starting with '%s' in the export.", prefix))
  stop(sprintf("Column prefix '%s' is ambiguous: %s", prefix, paste(hit, collapse = ", ")))
}
