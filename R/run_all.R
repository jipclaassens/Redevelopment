# run_all.R — draai de redevelopment-analysepijplijn (issue #16) van begin tot eind.
# Vereist: verse PerObject_Export-mmd (GeoDMS, /MaakOntkoppeldeData/PerObject_Export)
# en de coefficienten-CSV (/Analyse/PriceComponents/ExportCoefficients_WP4/Export_CSV).

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}

run_02 <- TRUE; source(file.path(.rd_script_dir, "02_load_perobject.R"))
run_03 <- TRUE; source(file.path(.rd_script_dir, "03_sites.R"))
run_04 <- TRUE; source(file.path(.rd_script_dir, "04_kmeans.R"))
