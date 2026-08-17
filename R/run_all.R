# run_all.R — run the neighbourhood analysis of the Cities paper end to end.
# Requires: Data/Analyse_PerWijk_<filedate>.csv (GeoDMS, /Analyse/.../Analyse_PerWijk).
#
# 04_validate.R is the gate: it compares the estimates with Tables 3 and 4 as published in
# the first submission. Keep it passing until a reviewer-driven change is deliberately made,
# and re-baseline it in the same commit as that change.

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}

run_01 <- TRUE; source(file.path(.rd_script_dir, "01_load_perwijk.R")); run_01 <- FALSE
run_02 <- TRUE; source(file.path(.rd_script_dir, "02_models.R"));       run_02 <- FALSE
run_03 <- TRUE; source(file.path(.rd_script_dir, "03_tables.R"));       run_03 <- FALSE
run_04 <- TRUE; source(file.path(.rd_script_dir, "04_validate.R"));     run_04 <- FALSE
run_05 <- TRUE; source(file.path(.rd_script_dir, "05_revision.R"));    run_05 <- FALSE
run_06 <- TRUE; source(file.path(.rd_script_dir, "06_omitted.R"));     run_06 <- FALSE
run_07 <- TRUE; source(file.path(.rd_script_dir, "07_spatial.R"));     run_07 <- FALSE
run_08 <- TRUE; source(file.path(.rd_script_dir, "08_nbsplit.R"));     run_08 <- FALSE
run_09 <- TRUE; source(file.path(.rd_script_dir, "09_supplement.R"));  run_09 <- FALSE
run_10 <- TRUE; source(file.path(.rd_script_dir, "10_papertables.R")); run_10 <- FALSE
