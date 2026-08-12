# 07_spatial.R — spatial dependence in the residuals (referee 2, point 5).
# Output: Output/R/spatial_tables_<filedate>.md/.docx
#
# The neighbourhood export has no coordinates, so centroids are taken straight from the CBS
# 2012 boundary file (cbsgebiedsindelingen2012.gpkg, layer wijk_gegeneraliseerd, EPSG:28992),
# joined on statcode. Weights are k-nearest-neighbour, row-standardised: contiguity would be
# closer to the usual practice, but with 2,621 neighbourhoods of very unequal size a fixed
# number of neighbours behaves better, and the conclusion does not depend on the choice.
#
# Three residual sets are tested, to show what each fix buys:
#   published   OLS on the log net change per hectare, robust standard errors
#   ppml        Poisson on gross additions with land area as exposure
#   ppml_fe     the same, plus municipal fixed effects
# If Moran's I falls sharply from the first to the third, the municipal fixed effects have
# absorbed most of the spatial structure and referee 2's concern is met.

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))
source(file.path(.rd_script_dir, "05_revision.R"))
suppressPackageStartupMessages({ library(fixest); library(sf); library(spdep) })

cfg$knn <- 8L   # number of nearest neighbours in the spatial weights matrix

# Centroids of the 2012 neighbourhoods, in metres (RD New). Preferred source is the export
# itself (WK_centroide, parsed in 01_load_perwijk.R); the CBS boundary file is the fallback
# for vintages exported before that column existed.
add_centroids <- function(wijk) {
  if (all(c("x_rd", "y_rd") %in% names(wijk)) && wijk[!is.na(x_rd), .N] > 0L) {
    rd_log("Centroids from the export: %d of %d", wijk[!is.na(x_rd), .N], nrow(wijk))
    return(wijk[])
  }
  stopifnot(file.exists(cfg$file_wijk_gpkg))
  g <- st_read(cfg$file_wijk_gpkg, layer = "wijk_gegeneraliseerd", quiet = TRUE)
  cen <- st_coordinates(st_point_on_surface(st_geometry(g)))
  xy <- data.table(wk_code = g$statcode, x_rd = cen[, 1], y_rd = cen[, 2])
  wijk <- merge(wijk, xy, by = "wk_code", all.x = TRUE)
  rd_log("Centroids matched for %d of %d neighbourhoods", wijk[!is.na(x_rd), .N], nrow(wijk))
  wijk[]
}

# Moran's I of a model's residuals, using the coordinates of the observations that the model
# actually used (obs() gives their row numbers in the input data).
moran_resid <- function(m, wijk, label) {
  idx <- obs(m)
  d <- data.table(r = resid(m), x = wijk$x_rd[idx], y = wijk$y_rd[idx])
  d <- d[!is.na(x) & !is.na(y) & !is.na(r)]
  nb <- knn2nb(knearneigh(as.matrix(d[, .(x, y)]), k = cfg$knn))
  lw <- nb2listw(nb, style = "W")
  mt <- moran.test(d$r, lw, zero.policy = TRUE)
  data.table(spec = label, n = nrow(d),
             moran_i = unname(mt$estimate["Moran I statistic"]),
             expected = unname(mt$estimate["Expectation"]),
             z = unname(mt$statistic), p = mt$p.value)
}

rhs <- "p_huurcorp + uai + p_beschermd + p_onbebouwd + construction_period"

run_spatial <- function(wijk) {
  rbindlist(lapply(names(cfg$outcomes), function(nm) {
    fits <- list(
      published = feols(as.formula(paste0("ln_", nm, " ~ ", rhs)), data = wijk, vcov = "hetero"),
      ppml      = fepois(as.formula(paste0("gross_", nm, " ~ ", rhs)), data = wijk,
                         offset = ~log(land_area_ha), vcov = "hetero"),
      ppml_fe   = fepois(as.formula(paste0("gross_", nm, " ~ ", rhs, " | gm_code")), data = wijk,
                         offset = ~log(land_area_ha), vcov = ~gm_code))
    out <- rbindlist(Map(moran_resid, fits, list(wijk), names(fits)))
    out[, outcome := cfg$outcomes[[nm]]$label][]
  }))
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_07", ifnotfound = FALSE))) {
  wijk <- add_centroids(add_gross(add_province(readRDS(cfg$file_wijk_rds))))
  res  <- run_spatial(wijk)
  saveRDS(res, file.path(cfg$dir_work, sprintf("spatial_%s.rds", cfg$filedate)))

  wide <- dcast(res, outcome ~ factor(spec, levels = c("published", "ppml", "ppml_fe")),
                value.var = "moran_i")
  stars <- function(p) fifelse(p < .01, "***", fifelse(p < .05, "**", fifelse(p < .1, "*", "")))
  res[, cell_ := sprintf("%.3f%s", moran_i, stars(p))]
  w2 <- dcast(res, outcome ~ factor(spec, levels = c("published", "ppml", "ppml_fe")), value.var = "cell_")

  md <- c(sprintf("# Spatial dependence in the residuals (export %s)", cfg$filedate), "",
    sprintf("Moran's I on %d-nearest-neighbour, row-standardised weights built from the", cfg$knn),
    "centroids of the 2012 CBS neighbourhoods. Under the null of no spatial autocorrelation",
    sprintf("the expected value is about %.4f.", res$expected[1]), "",
    "| Outcome | OLS log net (published) | PPML gross | PPML gross + municipality FE |",
    "|---|---|---|---|",
    w2[, sprintf("| %s | %s | %s | %s |", outcome, published, ppml, ppml_fe)], "",
    "*** p<0.01, ** p<0.05, * p<0.1 against the null of no spatial autocorrelation.", "",
    "## Reading", "",
    "Positive and significant values in the first column confirm referee 2's point: the",
    "published specification leaves spatially correlated residuals, so its standard errors",
    "are too small. The third column shows how much of that structure municipal fixed",
    "effects absorb; whatever remains is why the standard errors are clustered on",
    "municipality throughout the revision.")

  f <- file.path(cfg$dir_work, sprintf("spatial_tables_%s.md", cfg$filedate))
  writeLines(md, f)
  rd_log("Written: %s", f)
  rd_md_to_docx(f)
  cat("\n---- Moran's I ----\n")
  print(res[, .(outcome, spec, n, moran_i = round(moran_i, 4), z = round(z, 1), p = signif(p, 3))])
}
