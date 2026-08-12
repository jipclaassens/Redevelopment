# 04_validate.R — check the R port against the published tables of the first submission.
#
# The Stata licence has expired, so the do-file cannot be re-run. Instead we compare the R
# estimates cell by cell with the numbers as printed in Submission/Cities/2nd submission/
# Table 3.docx and Table 4.docx. If this script reports no mismatches, the port is faithful
# and any later difference in results is caused by a deliberate change, not by the rewrite.
#
# Published tables report three decimals, so the tolerance is half a unit in the last digit.

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))

cfg$tol <- 0.0005

# Map the fixest coefficient names onto the row labels used in the published tables.
term_map <- c(
  "(Intercept)"                                      = "Constant",
  "p_huurcorp"                                       = "Social housing",
  "uai"                                              = "UAI",
  "p_beschermd"                                      = "Heritage",
  "p_onbebouwd"                                      = "Available land",
  "construction_periodConstruction 1929 and earlier" = "cp <=1929",
  "construction_periodConstruction 1930-1945"        = "cp 1930-1945",
  "construction_periodConstruction 1946-1960"        = "cp 1946-1960",
  "construction_periodConstruction 1961-1970"        = "cp 1961-1970",
  "construction_periodConstruction 1981-1990"        = "cp 1981-1990",
  "construction_periodConstruction 1991-2000"        = "cp 1991-2000",
  "construction_periodConstruction 2000-2012"        = "cp 2001-2012",
  "urbanisationMedium density"                       = "Is medium density",
  "urbanisationLow density"                          = "Is low density",
  # fixest keeps "variable:factorLevel" for the first interaction in the formula but flips
  # to "factorLevel:variable" for the later ones, so both spellings are mapped here.
  "p_huurcorp:urbanisationMedium density"            = "Social housing x medium",
  "p_huurcorp:urbanisationLow density"               = "Social housing x low",
  "urbanisationMedium density:p_huurcorp"            = "Social housing x medium",
  "urbanisationLow density:p_huurcorp"               = "Social housing x low",
  "uai:urbanisationMedium density"                   = "UAI x medium",
  "uai:urbanisationLow density"                      = "UAI x low",
  "urbanisationMedium density:uai"                   = "UAI x medium",
  "urbanisationLow density:uai"                      = "UAI x low",
  "p_onbebouwd:urbanisationMedium density"           = "Available land x medium",
  "p_onbebouwd:urbanisationLow density"              = "Available land x low",
  "urbanisationMedium density:p_onbebouwd"           = "Available land x medium",
  "urbanisationLow density:p_onbebouwd"              = "Available land x low")

# ---- published Table 3 (baseline, one column per outcome) --------------------------
pub3 <- data.table(
  label = c("Social housing", "UAI", "Heritage", "Available land",
            "cp <=1929", "cp 1930-1945", "cp 1946-1960", "cp 1961-1970",
            "cp 1981-1990", "cp 1991-2000", "cp 2001-2012", "Constant"),
  all = c( 0.041,  0.031,  0.008, -0.112, -0.512, -0.112, -0.161,  0.005, -0.201, -0.140,  0.565, 7.829),
  sn  = c( 0.042, -0.016,  0.005, -0.148, -0.680, -0.350, -0.039,  0.117, -0.102, -0.332,  0.124, 9.718),
  nb  = c( 0.034, -0.019, -0.001, -0.111, -0.798, -0.576, -0.638, -0.222, -0.131, -0.069,  1.065, 6.663),
  div = c( 0.033,  0.025,  0.014, -0.133, -0.071,  0.259,  0.060,  0.084, -0.048, -0.248,  0.030, 7.737),
  trf = c( 0.017,  0.025,  0.014, -0.109,  0.024,  0.139,  0.002,  0.024,  0.099, -0.037, -0.246, 4.666))
pub3_n  <- c(all = 2538, sn = 2162, nb = 2239, div = 2143, trf = 1706)
pub3_r2 <- c(all = 0.609, sn = 0.603, nb = 0.391, div = 0.629, trf = 0.575)

# ---- published Table 4, upper panel (interaction model) ----------------------------
pub4 <- data.table(
  label = c("Social housing", "UAI", "Heritage", "Available land",
            "Is medium density", "Is low density",
            "Social housing x medium", "Social housing x low",
            "UAI x medium", "UAI x low",
            "Available land x medium", "Available land x low",
            "cp <=1929", "cp 1930-1945", "cp 1946-1960", "cp 1961-1970",
            "cp 1981-1990", "cp 1991-2000", "cp 2001-2012", "Constant"),
  all = c( 0.013,  0.034,  0.002, -0.075, -4.180,  0.870,  0.013,  0.028,  0.279,  0.421,  0.035, -0.033,
          -0.301, -0.034, -0.064,  0.041, -0.250, -0.104,  0.594, 6.061),
  sn  = c( 0.022,  0.011, -0.000, -0.084, -1.756, 12.414,  0.000,  0.013,  0.210,  0.366,  0.011, -0.152,
          -0.457, -0.171,  0.048,  0.141, -0.145, -0.293,  0.093, 5.432),
  nb  = c( 0.013, -0.001, -0.006, -0.066, -2.549,  4.637,  0.001,  0.016,  0.040,  0.251,  0.024, -0.068,
          -0.544, -0.420, -0.513, -0.181, -0.149, -0.064,  1.033, 3.946),
  div = c( 0.008,  0.023,  0.008, -0.102, -6.321,  0.186,  0.013,  0.010,  0.415,  0.632,  0.055, -0.023,
          -0.058,  0.188,  0.074,  0.106, -0.156, -0.224,  0.044, 6.663),
  trf = c(-0.003,  0.024,  0.009, -0.089, -4.265, -1.203,  0.016,  0.017,  0.419,  0.911,  0.035, -0.004,
           0.041,  0.134,  0.044,  0.036,  0.022,  0.011, -0.115, 3.986))
pub4_r2 <- c(all = 0.679, sn = 0.668, nb = 0.450, div = 0.688, trf = 0.627)

# ---- published Table 4, lower panel (average marginal effects) ---------------------
pub_ame <- data.table(
  var   = rep(c("p_huurcorp", "uai", "p_onbebouwd"), each = 3),
  group = rep(c("High density", "Medium density", "Low density"), times = 3),
  all = c(0.013, 0.026, 0.041,  0.034, 0.313, 0.455, -0.075, -0.039, -0.107),
  sn  = c(0.022, 0.022, 0.034,  0.011, 0.221, 0.377, -0.084, -0.073, -0.236),
  nb  = c(0.013, 0.014, 0.029, -0.001, 0.039, 0.250, -0.066, -0.043, -0.134),
  div = c(0.008, 0.022, 0.019,  0.023, 0.438, 0.655, -0.102, -0.048, -0.125),
  trf = c(-0.003, 0.013, 0.014, 0.024, 0.443, 0.934, -0.089, -0.054, -0.093))

# Compare one published column against the corresponding R estimates.
check_block <- function(block, pub, models, what) {
  rbindlist(lapply(names(cfg$outcomes), function(nm) {
    ct <- copy(models[[block]][[nm]]$ct)
    ct[, label := term_map[term]]
    m <- merge(pub[, .(label, published = get(nm))], ct[, .(label, r = estimate)],
               by = "label", all.x = TRUE)
    m[, `:=`(outcome = cfg$outcomes[[nm]]$label, table = what,
             diff = round(r - published, 4))]
    m[]
  }))
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_04", ifnotfound = FALSE))) {
  # Always validate against the vintage the first submission was estimated on, whatever
  # cfg$filedate currently points at. Re-read and re-estimate rather than reuse the working
  # rds, so this check stays independent of the rest of the pipeline.
  source(file.path(.rd_script_dir, "01_load_perwijk.R"))
  source(file.path(.rd_script_dir, "02_models.R"))
  rd_log("Validating against the published vintage %s", cfg$filedate_published)
  models <- estimate_all(load_perwijk(cfg$file_perwijk(cfg$filedate_published)))

  cmp <- rbind(
    check_block("base",  pub3, models, "Table 3"),
    check_block("inter", pub4, models, "Table 4 upper"))

  # Average marginal effects: reshape the R results to the published layout.
  ame <- rbindlist(lapply(names(cfg$outcomes), function(nm) {
    a <- copy(models$ames[[nm]])
    p <- pub_ame[, .(var, group, published = get(nm))]
    m <- merge(p, a[, .(var, group, r = estimate)], by = c("var", "group"))
    m[, `:=`(outcome = cfg$outcomes[[nm]]$label, table = "Table 4 AME",
             label = paste(var, group, sep = " x "), diff = round(r - published, 4))]
    m[, .(label, published, r, outcome, table, diff)]
  }))
  cmp <- rbind(cmp, ame)

  # Sample sizes and fit statistics.
  fit <- rbindlist(lapply(names(cfg$outcomes), function(nm) data.table(
    outcome = cfg$outcomes[[nm]]$label,
    n_pub = pub3_n[[nm]],           n_r = models$base[[nm]]$n,
    r2_pub = pub3_r2[[nm]],         r2_r = round(models$base[[nm]]$r2, 3),
    r2i_pub = pub4_r2[[nm]],        r2i_r = round(models$inter[[nm]]$r2, 3))))

  cat("\n================ sample sizes and fit ================\n")
  print(fit)
  bad_fit <- fit[n_pub != n_r | abs(r2_pub - r2_r) > cfg$tol | abs(r2i_pub - r2i_r) > cfg$tol]

  cat("\n================ coefficient comparison ================\n")
  miss <- cmp[is.na(r)]
  bad  <- cmp[!is.na(r) & abs(diff) > cfg$tol]
  cat(sprintf("Cells compared : %d\n", cmp[!is.na(r), .N]))
  cat(sprintf("Max |deviation|: %.4f\n", cmp[!is.na(r), max(abs(diff))]))
  cat(sprintf("Mismatches     : %d\n", nrow(bad)))
  if (nrow(miss)) { cat("\nNot found in the R output:\n"); print(miss[, .(table, outcome, label)]) }
  if (nrow(bad))  { cat("\nDeviations beyond tolerance:\n"); print(bad[order(-abs(diff)), .(table, outcome, label, published, r = round(r, 3), diff)]) }

  if (nrow(bad) == 0L && nrow(bad_fit) == 0L && nrow(miss) == 0L) {
    cat("\nPASS — the R port reproduces Tables 3 and 4 of the first submission exactly.\n")
  } else {
    cat("\nFAIL — see the deviations above before building on this port.\n")
  }
}
