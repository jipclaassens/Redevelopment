# 04_kmeans.R — step 1 (issue #16): k-means clustering of realized
# replacement sites into development alternatives ("menu of what gets
# built in practice"), incl. elbow curve (Makles 2012, Stata Journal 12(2)).
#
# Cluster variables: shares per WP4, FAR, density (units/ha), mean unit
# size. (Height was dropped as an export variable — AHN snapshot
# time-inconsistent — so it does not participate.) First winsorize at p1/p99,
# then standardize (otherwise FAR dominates due to scale differences).

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))

winsorize <- function(v, p = cfg$winsor_p) {
  q <- quantile(v, p, na.rm = TRUE, names = FALSE)
  pmin(pmax(v, q[1]), q[2])
}

cluster_vars <- function() c(paste0("share_", cfg$wp4_names), "far", "density_per_ha", "unit_size_mean")

# stage-1 sample (cfg$stage1_sample): the "menu" should consist of what REDEVELOPERS
# build; with 'alle' greenfield and 1-unit addition sites dominate (see STATUS 27-07)
filter_stage1_sample <- function(sites_new) {
  d <- switch(cfg$stage1_sample,
              alle  = sites_new,
              sn    = sites_new[has_sn == TRUE],
              sn_tr = sites_new[has_sn == TRUE | has_transformation == TRUE],
              stop("unknown stage1_sample: ", cfg$stage1_sample))
  rd_log("Stage-1 sample '%s': %s of %s replacement sites", cfg$stage1_sample,
         format(nrow(d), big.mark = ","), format(nrow(sites_new), big.mark = ","))
  d
}

build_cluster_input <- function(sites_new) {
  cv <- cluster_vars()
  d <- sites_new[complete.cases(sites_new[, ..cv]) & is.finite(far) & is.finite(density_per_ha)]
  rd_log("Cluster input: %s of %s replacement sites complete", format(nrow(d), big.mark = ","), format(nrow(sites_new), big.mark = ","))
  m <- as.matrix(d[, ..cv])
  m <- apply(m, 2, winsorize)
  list(sites = d, m_raw = m, m = scale(m))
}

elbow <- function(m, k_max = cfg$kmeans_k_max) {
  set.seed(cfg$kmeans_seed)
  wss <- vapply(seq_len(k_max), function(k)
    kmeans(m, centers = k, nstart = 10, iter.max = 50)$tot.withinss, numeric(1))
  data.table(k = seq_len(k_max), wss = wss,
             wss_ratio = wss / wss[1],
             # Makles (2012): eta^2 and proportional reduction of error (PRE)
             eta2 = 1 - wss / wss[1],
             pre  = c(NA, 1 - wss[-1] / wss[-length(wss)]))
}

final_clustering <- function(ci, k = cfg$kmeans_k_final) {
  set.seed(cfg$kmeans_seed)
  km <- kmeans(ci$m, centers = k, nstart = cfg$kmeans_nstart, iter.max = 100)
  ci$sites[, cluster := km$cluster]

  # centroids back to the original (unstandardized) scale for interpretation + alternatives table
  ctr <- t(t(km$centers) * attr(ci$m, "scaled:scale") + attr(ci$m, "scaled:center"))
  centroids <- as.data.table(ctr)[, cluster := .I]
  setcolorder(centroids, "cluster")

  list(sites = ci$sites, kmeans = km, centroids = centroids)
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_04", ifnotfound = FALSE))) {
  s  <- readRDS(cfg$file_sites_rds)
  ci <- build_cluster_input(filter_stage1_sample(s$new))

  eb <- elbow(ci$m)
  rd_log("Elbow curve (choose K where PRE levels off):")
  print(eb)
  fwrite(eb, file.path(cfg$dir_work, paste0("elbow", cfg$sample_suffix, ".csv")))

  res <- final_clustering(ci)
  rd_log("Final clustering K = %d; size per cluster:", cfg$kmeans_k_final)
  print(res$sites[, .N, by = cluster][order(cluster)])
  rd_log("Centroids (original scale):")
  print(res$centroids)

  saveRDS(list(elbow = eb, sites = res$sites, centroids = res$centroids, kmeans = res$kmeans),
          cfg$file_clusters_rds, compress = FALSE)
  rd_log("Written: %s", cfg$file_clusters_rds)
}
