# 04_kmeans.R — stap 1 (issue #16): k-means-clustering van gerealiseerde
# replacement-sites tot ontwikkel-alternatieven ("menu van wat in de praktijk
# gebouwd wordt"), incl. elbow-curve (Makles 2012, Stata Journal 12(2)).
#
# Clustervariabelen: aandelen per WP4, FAR, dichtheid (units/ha), gemiddelde
# unitgrootte. (Hoogte is als exportvariabele gedropt — AHN-snapshot
# tijd-inconsistent — en doet dus niet mee.) Eerst winsoriseren op p1/p99,
# dan standaardiseren (anders domineert FAR door schaalverschil).

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))

winsorize <- function(v, p = cfg$winsor_p) {
  q <- quantile(v, p, na.rm = TRUE, names = FALSE)
  pmin(pmax(v, q[1]), q[2])
}

cluster_vars <- function() c(paste0("aandeel_", cfg$wp4_names), "far", "dichtheid_per_ha", "unit_size_mean")

maak_clusterinput <- function(sites_nieuw) {
  cv <- cluster_vars()
  d <- sites_nieuw[complete.cases(sites_nieuw[, ..cv]) & is.finite(far) & is.finite(dichtheid_per_ha)]
  rd_log("Clusterinput: %s van %s replacement-sites compleet", format(nrow(d), big.mark = ","), format(nrow(sites_nieuw), big.mark = ","))
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
             # Makles (2012): eta^2 en proportionele reductie van fouten (PRE)
             eta2 = 1 - wss / wss[1],
             pre  = c(NA, 1 - wss[-1] / wss[-length(wss)]))
}

definitieve_clustering <- function(ci, k = cfg$kmeans_k_final) {
  set.seed(cfg$kmeans_seed)
  km <- kmeans(ci$m, centers = k, nstart = cfg$kmeans_nstart, iter.max = 100)
  ci$sites[, cluster := km$cluster]

  # centroides terug naar de oorspronkelijke (ongestandaardiseerde) schaal voor interpretatie + alternatieventabel
  ctr <- t(t(km$centers) * attr(ci$m, "scaled:scale") + attr(ci$m, "scaled:center"))
  centroids <- as.data.table(ctr)[, cluster := .I]
  setcolorder(centroids, "cluster")

  list(sites = ci$sites, kmeans = km, centroids = centroids)
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_04", ifnotfound = FALSE))) {
  s  <- readRDS(cfg$file_sites_rds)
  ci <- maak_clusterinput(s$nieuw)

  eb <- elbow(ci$m)
  rd_log("Elbow-curve (kies K waar PRE afvlakt):")
  print(eb)
  fwrite(eb, file.path(cfg$dir_work, "elbow.csv"))

  res <- definitieve_clustering(ci)
  rd_log("Definitieve clustering K = %d; omvang per cluster:", cfg$kmeans_k_final)
  print(res$sites[, .N, by = cluster][order(cluster)])
  rd_log("Centroides (oorspronkelijke schaal):")
  print(res$centroids)

  saveRDS(list(elbow = eb, sites = res$sites, centroids = res$centroids, kmeans = res$kmeans),
          cfg$file_clusters_rds, compress = FALSE)
  rd_log("Weggeschreven: %s", cfg$file_clusters_rds)
}
