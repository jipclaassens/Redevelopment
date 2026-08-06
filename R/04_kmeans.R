# 04_kmeans.R — step 1 (issue #16): k-means clustering of realized
# replacement sites into development alternatives ("menu of what gets
# built in practice"), incl. elbow curve (Makles 2012, Stata Journal 12(2)).
#
# Cluster variables: shares per WP4, FAR, density (units/ha), mean unit
# size. (Height was dropped as an export variable — AHN snapshot
# time-inconsistent — so it does not participate.) First winsorize at p1/p99,
# then standardize (otherwise FAR dominates due to scale differences).

# Locate the directory this script lives in, so 00_config.R can be sourced with an
# absolute path no matter where R was started. Under Rscript the path comes from the
# "--file=" command-line argument; in an interactive session it falls back to getwd().
if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))

# Cap a numeric vector at its p1/p99 quantiles (winsorizing): values below the 1st
# percentile are raised to it, values above the 99th are lowered to it. This keeps a
# handful of extreme sites from dragging the cluster centroids around.
winsorize <- function(v, p = cfg$winsor_p) {
  q <- quantile(v, p, na.rm = TRUE, names = FALSE)
  pmin(pmax(v, q[1]), q[2])
}

# Names of the columns the clustering runs on: one share_ column per WP4 house type
# (vrijstaand, twee_onder_1_kap, rijtjeswoning, appartement), plus FAR, units/ha and
# mean unit size. Kept in one function so input building and reporting stay in sync.
cluster_vars <- function() c(paste0("share_", cfg$wp4_names), "far", "density_per_ha", "unit_size_mean")

# stage-1 sample (cfg$stage1_sample): the "menu" should consist of what REDEVELOPERS
# build; with 'alle' greenfield and 1-unit addition sites dominate (see STATUS 27-07)
filter_stage1_sample <- function(sites_new) {
  # switch() picks one branch by the config string. Each branch is a data.table row
  # filter: dt[condition] keeps only the rows where the condition is TRUE (here: sites
  # with SN demolition and/or transformation). 'alle' keeps everything; an unknown
  # setting aborts with an error instead of silently clustering the wrong sample.
  d <- switch(cfg$stage1_sample,
              alle  = sites_new,
              sn    = sites_new[has_sn == TRUE],
              sn_tr = sites_new[has_sn == TRUE | has_transformation == TRUE],
              stop("unknown stage1_sample: ", cfg$stage1_sample))
  rd_log("Stage-1 sample '%s': %s of %s replacement sites", cfg$stage1_sample,
         format(nrow(d), big.mark = ","), format(nrow(sites_new), big.mark = ","))
  d
}

# Turn the site table into a numeric matrix that kmeans() can digest. kmeans cannot
# handle NA/Inf, so rows missing any cluster variable are dropped first.
build_cluster_input <- function(sites_new) {
  cv <- cluster_vars()
  # dt[, ..cv] selects the columns whose NAMES are stored in the character vector cv
  # (the ".." prefix means "look up this variable, it is not itself a column"; see
  # README, data.table primer). complete.cases() flags rows without any NA there;
  # is.finite() additionally drops Inf, e.g. FAR on a zero-area site.
  d <- sites_new[complete.cases(sites_new[, ..cv]) & is.finite(far) & is.finite(density_per_ha)]
  rd_log("Cluster input: %s of %s replacement sites complete", format(nrow(d), big.mark = ","), format(nrow(sites_new), big.mark = ","))
  # apply(.., 2, ..) winsorizes column by column; scale() then standardizes each column
  # to mean 0 / sd 1 so that FAR (large numbers) and shares (0..1) weigh equally in the
  # Euclidean distances that k-means minimizes. Both the raw and scaled matrix are kept.
  m <- as.matrix(d[, ..cv])
  m <- apply(m, 2, winsorize)
  list(sites = d, m_raw = m, m = scale(m))
}

# Diagnostics for choosing the number of clusters K: run k-means for K = 1..k_max and
# record the total within-cluster sum of squares (WSS) each time. Where extra clusters
# stop reducing WSS much (the "elbow"), adding more K buys little. Seeded for
# reproducibility; vapply is just a type-safe loop returning one number per K.
elbow <- function(m, k_max = cfg$kmeans_k_max) {
  set.seed(cfg$kmeans_seed)
  # The high-K runs emit R's "Quick-TRANSfer stage steps exceeded maximum" warning: a limit
  # inside Hartigan-Wong that raising iter.max does not lift (checked 30-07 at 50 and 200).
  # It only touches the tail of the diagnostic curve; the knee this function exists to find
  # is unaffected (PRE 0.27 at K=6 against 0.12 and 0.07 at K=7 and 8), and the FINAL
  # clustering is clean: it converges in 3 iterations, warning-free, and comes out identical
  # at iter.max 100 and 10,000.
  wss <- vapply(seq_len(k_max), function(k)
    kmeans(m, centers = k, nstart = 10, iter.max = 200)$tot.withinss, numeric(1))
  # One row per candidate K. eta2 = share of total variance explained by the clustering;
  # PRE = relative WSS drop versus K-1 (NA for K=1, which has no predecessor).
  data.table(k = seq_len(k_max), wss = wss,
             wss_ratio = wss / wss[1],
             # Makles (2012): eta^2 and proportional reduction of error (PRE)
             eta2 = 1 - wss / wss[1],
             pre  = c(NA, 1 - wss[-1] / wss[-length(wss)]))
}

# The definitive clustering at the chosen K: these clusters ARE the development
# alternatives of the stage-1 conditional logit. nstart runs k-means from many random
# starting points and keeps the best solution (k-means can get stuck in local optima).
final_clustering <- function(ci, k = cfg$kmeans_k_final) {
  set.seed(cfg$kmeans_seed)
  km <- kmeans(ci$m, centers = k, nstart = cfg$kmeans_nstart, iter.max = 100)
  # := is data.table assignment by reference: the cluster label is added as a new column
  # directly inside the sites table, no copy is made (see README, data.table primer).
  ci$sites[, cluster := km$cluster]

  # centroids back to the original (unstandardized) scale for interpretation + alternatives table
  # scale() stored each column's mean and sd as attributes on the matrix; undoing the
  # z-score is multiply by sd, then add the mean. The double t() is a trick to apply
  # these per-COLUMN vectors (R recycles per row, hence transpose, scale, transpose back).
  ctr <- t(t(km$centers) * attr(ci$m, "scaled:scale") + attr(ci$m, "scaled:center"))
  # .I is the row number inside a data.table, so cluster gets ids 1..K; setcolorder
  # merely moves that id to the first column for readability.
  centroids <- as.data.table(ctr)[, cluster := .I]
  setcolorder(centroids, "cluster")

  list(sites = ci$sites, kmeans = km, centroids = centroids)
}

## ---------------------------------------------------------------------------
# Script body. The guard means: run only when this file is executed directly as a
# script (sys.nframe() == 0), or when a driver script opts in by setting run_04 = TRUE.
# Sourcing the file otherwise only loads the functions above, without side effects.
if (sys.nframe() == 0L || isTRUE(get0("run_04", ifnotfound = FALSE))) {
  # Load the site tables built in the previous step; s$new holds the replacement sites
  # (what got built), which are filtered to the stage-1 sample and matrix-ified.
  s  <- readRDS(cfg$file_sites_rds)
  ci <- build_cluster_input(filter_stage1_sample(s$new))

  # Elbow diagnostics: printed for the log and written to CSV so the K choice can be
  # documented in the paper appendix.
  eb <- elbow(ci$m)
  rd_log("Elbow curve (choose K where PRE levels off):")
  print(eb)
  fwrite(eb, file.path(cfg$dir_work, paste0("elbow", cfg$sample_suffix, ".csv")))

  res <- final_clustering(ci)
  rd_log("Final clustering K = %d; size per cluster:", cfg$kmeans_k_final)
  # Grouped aggregation: .N counts the rows per group, "by = cluster" makes one group
  # per cluster label; the chained [order(cluster)] sorts the resulting count table.
  print(res$sites[, .N, by = cluster][order(cluster)])
  rd_log("Centroids (original scale):")
  print(res$centroids)

  # Bundle everything downstream steps need (labelled sites, centroids = the
  # alternatives table, plus the full kmeans object) into one RDS file.
  saveRDS(list(elbow = eb, sites = res$sites, centroids = res$centroids, kmeans = res$kmeans),
          cfg$file_clusters_rds, compress = FALSE)
  rd_log("Written: %s", cfg$file_clusters_rds)
}
