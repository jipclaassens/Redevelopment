# run_all.R — run the redevelopment analysis pipeline (issue #16) end to end.
# Requires: a fresh PerObject_Export mmd (GeoDMS, /MaakOntkoppeldeData/PerObject_Export),
# the coefficient CSV (/Analyse/PriceComponents/ExportCoefficients_WP4/Export_CSV) and
# the volatility CSVs from PriceIndices (R/06_volatility.R over there).

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}

run_02 <- TRUE; source(file.path(.rd_script_dir, "02_load_perobject.R")); run_02 <- FALSE
run_03 <- TRUE; source(file.path(.rd_script_dir, "03_sites.R"));          run_03 <- FALSE
run_04 <- TRUE; source(file.path(.rd_script_dir, "04_kmeans.R"));         run_04 <- FALSE
run_05 <- TRUE; source(file.path(.rd_script_dir, "05_alternatives.R"));   run_05 <- FALSE  # re-sources 02 (functions only); run_02 must already be FALSE
run_06 <- TRUE; source(file.path(.rd_script_dir, "06_stage1_logit.R"));   run_06 <- FALSE
run_07 <- TRUE; source(file.path(.rd_script_dir, "07_stage2_logit.R"));   run_07 <- FALSE
run_08 <- TRUE; source(file.path(.rd_script_dir, "08_tables.R"));         run_08 <- FALSE
run_09 <- TRUE; source(file.path(.rd_script_dir, "09_hazard.R"))
