# 11_permits.R — issue #30: the public step between profitable and realized. Permits, their
# procedure and timing, attempts on sites that stayed unchanged, permitted replacement in the BAG,
# and the zoning plan in force before the project.
#
# Input: the fixed export of the permit track (cfg$dir_permits; repo Stikstof, R/27b_econlogic_export.R),
# flat files keyed on case, building or RD point:
#   zaak.csv                 one row per municipal case: dates, outcome, duration, procedure (uitgebreid),
#                            location, appeal (n_uitspraken), the type from the titles (soort) and the
#                            derived flags nieuwbouw, nieuwbouw_echt, vervanging, sloop_woning
#   pand_zaak.csv            buildings with BAG status 'Bouwvergunning verleend' from June 2021, linked to
#                            their case, with the first date of each later status
#   vbo_bag_datums.csv       per new BAG object: permit, construction start and completion date
#   bag_gepland.csv          new objects not in use (permit granted, started, not realized), permit >= 2012
#   bestemming_punt_<d>.csv  the zoning plan in force on date d per RD point
#   plan_klein_punt.csv      adopted plans below cfg$zoning_small_plan_ha touching an RD point
# plus the upstream results of this pipeline (02 objects, 03 sites, 04 clusters, 05/06 stage 1,
# 07 stage-2 samples, 09 hazard panel).
#
# A. Pipeline per alternative K (SN sites; deliverable 1). The new objects of a site link through
#    pand_zaak to their case. Coverage is the BAG-link window (permit from June 2021), so mostly
#    completions 2022-2026; only projects completed before July 2026 count, so long projects drop
#    out and the differences between alternatives are lower bounds. Within-municipality contrasts
#    against K = 1 (linear, SE clustered on gemeente).
#    The route over the BAG document number does not work (0.5-4.6% of SN sites per completion
#    year match a published case number; Stikstof inzichten ch. 36) and is left out.
# B. Per site, for stage 2 (deliverable 2):
#    attempt: a case for new dwellings or demolition of a dwelling with a precise location, first
#      publication from July 2021 (national coverage) to June 2026, linked to the nearest object;
#      strict = within cfg$attempt_strict_m, no new construction of another site within
#      cfg$attempt_elsewhere_m afterwards (then the case was about that neighbouring plot), and a
#      title that names real new construction, replacement or demolition of a dwelling. It catches
#      18-22% of the true SN projects: a lower bound, and noisy (Stikstof inzichten ch. 36-37).
#    bag_planned: a new object not in use within cfg$bag_planned_m of a standing object (2012-2026,
#      independent of titles; catches about half of true replacements).
# C. Zoning per site (deliverable 3, first version): main land-use group, the densest dwelling type
#    the building designation allows (1 detached .. 4 stacked), max building height, max units,
#    and small plans touching the site (a site-specific plan change). The zoning gap in type terms:
#    allowed type minus the densest existing type.
# D. Models (each only when its upstream results exist):
#    stage 1 'zoning': + infeasible_k (alternative k is denser than the designation of end 2013
#      allows), on SN sites completed from 2018 with a plan of end 2013, against the same sample
#      without it; do the ASCs shrink?
#    stage 2 'pending_y1' (unchanged sites with a permitted, not yet realized replacement in the
#      BAG count as y = 1), 'excl_blocked' (unchanged sites with a refused or withdrawn strict
#      attempt left out), 'window2021' and 'decision2021' (decisions from July 2021: y = SN versus
#      y = SN or a pending or stranded attempt), 'zoning_sample' and 'zoning' (+ zoning gap class).
#    hazard 'H2_permit': the H2 spec of 09 with the BAG permit date as decision moment instead of the
#      first demolition; and the time from permit to construction start against local volatility
#      in the permit year (real options: waiting after the permit).
#
# Endogeneity of zoning: plans are often changed for a project. Only the plan of end 2013 enters,
# with projects completed from 2018; plan changes are a step in the process, not a regressor.
#
# Output: cfg$file_permits_rds (per-site table + all tables and fits) and
# R_werk/permits_tables<suffix>_<area>_<date>.md (+ .docx).

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
# The functions of 07 (stage-2 input and samples, sourced by 09) and 09 (hazard panel), without
# their runs: run_09 is forced to FALSE while sourcing, then restored.
run_09_saved <- get0("run_09", ifnotfound = FALSE); run_09 <- FALSE
source(file.path(.rd_script_dir, "09_hazard.R"))
run_09 <- run_09_saved
# bit64: without its methods as.double() on an integer64 BAG id reinterprets the bits (all ids become 0)
suppressPackageStartupMessages({ library(fixest); library(survival); library(bit64) })

pct  <- function(v) if (!length(v) || all(is.na(v))) NA_real_ else 100 * mean(v, na.rm = TRUE)
med  <- function(v) if (all(is.na(v))) NA_real_ else as.numeric(median(v, na.rm = TRUE))
earliest <- function(v) if (all(is.na(v))) as.IDate(NA) else min(v, na.rm = TRUE)
as_date  <- function(v) as.IDate(substr(as.character(v), 1, 10))
ym_of    <- function(d) as.integer(format(d, "%Y")) * 100L + as.integer(format(d, "%m"))
# Densest dwelling type as an order (building designation in the plans: 1 detached, 2 two-attached,
# 3 terraced, 4 stacked); the WP4 types map onto it.
wp4_order <- c(vrijstaand = 1L, twee_onder_1_kap = 2L, rijtjeswoning = 3L, appartement = 4L)

## ---- the fixed export --------------------------------------------------------------------
read_permit_export <- function(dir = cfg$dir_permits) {
  if (is.na(dir) || !dir.exists(dir)) stop("11_permits.R: permit export not found (cfg$dir_permits = ", dir, ")")
  f <- function(name) {
    p <- file.path(dir, name)
    if (!file.exists(p)) stop("11_permits.R: missing in the permit export: ", p)
    p
  }
  zk <- fread(f("zaak.csv"), sep = ";", encoding = "UTF-8",
              colClasses = list(character = c("creator", "sleutelsoort", "sleutel", "uitkomst", "locatietype", "eerste_identifier", "soort")))
  for (v in c("eerste_datum", "datum_aanvraag", "datum_uitkomst")) set(zk, j = v, value = as_date(zk[[v]]))
  pz <- fread(f("pand_zaak.csv"), sep = ";", colClasses = list(character = "pand_id"))
  for (v in c("verg_begin", "start_begin", "gebruik_begin", "niet_gerealiseerd_begin")) set(pz, j = v, value = as_date(pz[[v]]))
  stopifnot(!anyDuplicated(pz$pand_id))
  vd <- fread(f("vbo_bag_datums.csv"), sep = ";", colClasses = list(character = c("vbo_id", "documentnummer")))
  for (v in c("verg_datum", "bouwstart_datum", "oplevering_datum")) set(vd, j = v, value = as_date(vd[[v]]))
  stopifnot(!anyDuplicated(vd$vbo_id))
  gp <- fread(f("bag_gepland.csv"), sep = ";", colClasses = list(character = c("vbo_id", "pand_id", "status")))
  gp[, verg_datum := as_date(verg_datum)]
  zf <- f(sprintf("bestemming_punt_%s.csv", cfg$zoning_date))
  zp <- fread(zf, sep = ";", encoding = "UTF-8", colClasses = list(character = c("plan", "hoofdgroep")))
  zp[, plandatum := as_date(plandatum)]
  sp <- fread(f("plan_klein_punt.csv"), sep = ";", colClasses = list(character = "plan"))
  sp[, datum := as_date(datum)]
  rd_log("Permit export %s: %s cases, %s building links, %s new objects with BAG dates, %s planned objects, %s zoning points, %s small-plan links",
         basename(dir), format(nrow(zk), big.mark = ","), format(nrow(pz), big.mark = ","), format(nrow(vd), big.mark = ","),
         format(nrow(gp), big.mark = ","), format(nrow(zp), big.mark = ","), format(nrow(sp), big.mark = ","))
  list(zaak = zk, pand_zaak = pz, vbo_dates = vd, planned = gp, zoning = zp, small_plans = sp, dir = dir)
}

## ---- objects and sites -------------------------------------------------------------------
# A slim object table (site, BAG ids as 16-digit strings, role, coordinates, dwelling type). The
# perobject rds is ~5 GB; the slim copy is cached next to it and rebuilt when the rds is newer.
slim_objects <- function() {
  cache <- file.path(cfg$dir_work, sprintf("permits_objects_%s_%s.rds", cfg$area, cfg$bag_date))
  if (file.exists(cache) && file.mtime(cache) > file.mtime(cfg$file_perobject_rds)) return(readRDS(cache))
  x <- readRDS(cfg$file_perobject_rds)
  stopifnot(max(x$vbo_bag_nr, na.rm = TRUE) < 2^53, max(x$pand_bag_nr, na.rm = TRUE) < 2^53)
  o <- x[, .(site_id, vbo_id = sprintf("%016.0f", as.double(vbo_bag_nr)), pand_id = sprintf("%016.0f", as.double(pand_bag_nr)),
             is_plus, is_min, is_incumbent, obj_is_woon, housetype = as.character(obj_housetype_lbl),
             redev_yearmonth, x = as.numeric(x_coord), y = as.numeric(y_coord))]
  rm(x); invisible(gc())
  o[x >= 4294967295 | y >= 4294967295, `:=`(x = NA_real_, y = NA_real_)]   # GeoDMS uint32 null as coordinate
  saveRDS(o, cache, compress = FALSE)
  o
}

# One row per site with group, scope, alternative K and the timing of the new construction.
site_table <- function(s, cl) {
  st <- s$attrs[!is.na(site_id), .(site_id, oad, gemeente_code, site_size)]
  st[, group := sub("_.*$", "", site_id)][group == "OnvS", group := "Onv"]
  st[, has_incumbent := site_id %chin% s$incumbent$site_id]
  st[s$incumbent, on = "site_id", `:=`(n_obj = i.n_obj, n_units_res = i.n_units_res)]
  st[s$new, on = "site_id", `:=`(redev_ym = i.redev_yearmonth, n_units_new = i.n_units_new)]
  st[cl$sites, on = "site_id", K := i.cluster]
  st[, urban := !is.na(oad) & oad >= cfg$oad_min]
  st[, oad_class := fcase(is.na(oad), NA_character_, oad < cfg$oad_min, sprintf("OAD < %d", cfg$oad_min),
                          oad < 1500, sprintf("OAD %d-1499", cfg$oad_min), default = "OAD >= 1500")]
  st[]
}

# Name of each alternative from its centroid: dominant dwelling type and the canonical numbering of 04.
alternative_labels <- function(cl) {
  ctr <- cl$centroids
  shares <- as.matrix(ctr[, paste0("share_", cfg$wp4_names), with = FALSE])
  dom <- cfg$wp4_names[max.col(shares, ties.method = "first")]
  data.table(K = ctr$cluster, dominant = dom, order = unname(wp4_order[dom]),
             label = sprintf("%d %s (%.0f/ha, %.0f m2)", ctr$cluster, dom, ctr$density_per_ha, ctr$unit_size_mean))
}

# Nearest object within r metres for every point, via a grid with cells of r metres.
# p: pid, x, y; q: qid, qx, qy. Returns pid, qid, d (the nearest q per p).
nearest_within <- function(p, q, r, all_pairs = FALSE) {
  q <- q[, .(qid, qx, qy, cx = floor(qx / r), cy = floor(qy / r))]
  setkey(q, cx, cy)
  res <- rbindlist(lapply(-1:1, function(dx) rbindlist(lapply(-1:1, function(dy) {
    a <- p[, .(pid, px = x, py = y, cx = floor(x / r) + dx, cy = floor(y / r) + dy)]
    q[a, on = .(cx, cy), nomatch = 0L, .(pid, qid, d = sqrt((qx - px)^2 + (qy - py)^2))]
  }))))
  res <- res[d <= r]
  if (all_pairs) return(res)
  setorder(res, pid, d)
  res[!duplicated(pid)]
}

## ---- A. pipeline of the realized sites ---------------------------------------------------
pipeline_sites <- function(pe, o, st) {
  zk <- pe$zaak
  pl <- o[is_plus == TRUE & site_id %chin% st[group == "SN", site_id], .(site_id, vbo_id, pand_id)]
  pl[pe$vbo_dates, on = "vbo_id", `:=`(verg = i.verg_datum, start = i.bouwstart_datum, compl = i.oplevering_datum)]
  rd_log("A. New objects on SN sites: %s, with a BAG permit date %.1f%%, building in the BAG-case link %.1f%%",
         format(nrow(pl), big.mark = ","), pct(!is.na(pl$verg)), pct(pl$pand_id %chin% pe$pand_zaak$pand_id))
  ps <- pl[, .(verg = earliest(verg), start = earliest(start), compl = earliest(compl)), by = site_id]
  # per site the case that got most of the new buildings; on a tie the earliest permit
  pp <- unique(pl[, .(site_id, pand_id)])[pe$pand_zaak, on = "pand_id", nomatch = 0L]
  sz <- pp[, .(n_bld = .N, verg_z = min(verg_begin)), by = .(site_id, zaak_id)]
  setorder(sz, site_id, -n_bld, verg_z)
  sz[, n_cases := .N, by = site_id]
  sz <- sz[!duplicated(site_id)]
  A <- st[group == "SN", .(site_id, K, urban, oad_class, redev_ym, gemeente_code, site_size)]
  A[ps, on = "site_id", `:=`(verg = i.verg, start = i.start, compl = i.compl)]
  A[sz, on = "site_id", `:=`(zaak_id = i.zaak_id, n_cases = i.n_cases)]
  A[zk, on = "zaak_id", `:=`(z_newbuild = i.nieuwbouw == 1L, z_type = i.soort, z_extended = i.uitgebreid == 1L,
                             z_outcome = i.uitkomst, z_days = i.doorlooptijd_dagen, z_ext = i.n_verlengingen,
                             z_appeal = i.n_uitspraken > 0L, z_ro = i.act_ro == 1L, z_applied = i.datum_aanvraag,
                             z_first_id = i.eerste_identifier)]
  A[, in_window := !is.na(verg) & verg >= cfg$permits_bag_from]
  A[]
}

pipeline_measures <- function(d) {
  g <- d[in_window == TRUE]
  k <- g[!is.na(zaak_id)]
  nb <- k[z_newbuild %in% TRUE]
  data.table(sites = nrow(d), in_window = nrow(g), linked = nrow(k), pct_linked = pct(!is.na(g$zaak_id)),
             pct_newbuild_case = pct(k$z_newbuild), newbuild_cases = nrow(nb),
             pct_extended = pct(nb$z_extended), pct_refused_withdrawn = pct(k$z_outcome %chin% c("geweigerd", "ingetrokken")),
             pct_appeal = pct(k$z_appeal), pct_extension = pct(k$z_ext > 0),
             days_procedure_med = med(nb$z_days), days_permit_start_med = med(as.integer(g$start - g$verg)),
             days_start_compl_med = med(as.integer(g$compl - g$start)), days_permit_compl_med = med(as.integer(g$compl - g$verg)))
}

# Within-municipality contrasts per alternative against K = 1 (linear, SE clustered on gemeente):
# extended procedure (percentage points) and log durations.
pipeline_contrasts <- function(A) {
  tk <- A[in_window == TRUE & !is.na(zaak_id) & !is.na(K)]
  tk[, `:=`(extended = 100 * (z_extended %in% TRUE), log_procedure = log(pmax(z_days, 1)),
            log_permit_start = log(pmax(as.integer(start - verg), 1)), log_start_compl = log(pmax(as.integer(compl - start), 1)))]
  one <- function(y, d) {
    if (nrow(d) < 50L || uniqueN(d$K) < 2L) return(NULL)
    m <- feols(as.formula(sprintf("%s ~ i(K, ref = 1) | gemeente_code", y)), data = d, cluster = ~gemeente_code, notes = FALSE)
    ct <- coeftable(m)
    data.table(outcome = y, K = as.integer(sub(".*::", "", rownames(ct))), b = ct[, 1], se = ct[, 2], p = ct[, 4], n = nobs(m))
  }
  rbind(one("extended", tk[z_newbuild %in% TRUE]), one("log_procedure", tk[z_newbuild %in% TRUE & !is.na(z_days)]),
        one("log_permit_start", tk[!is.na(start) & start >= verg]),
        one("log_start_compl", tk[!is.na(compl) & !is.na(start) & compl >= start]))
}

## ---- B. attempts and permitted replacement per site --------------------------------------
attempts_per_site <- function(pe, o, st) {
  zk <- pe$zaak
  cand <- zk[(nieuwbouw == 1L | sloop_woning == 1L) & !is.na(x) & !is.na(eerste_datum) &
             eerste_datum >= cfg$permits_national_from & eerste_datum <= cfg$permits_end &
             n_zelfde_punt <= cfg$attempt_max_same_pt &
             (locatietype %chin% c("Punt", "Adres", "Perceel") |
              (locatietype %chin% "Vlak" & !is.na(breedte_m) & breedte_m <= cfg$attempt_plane_max_m))]
  cand[, r := fifelse(locatietype == "Vlak", cfg$attempt_radius_plane, cfg$attempt_radius_point)]
  obj <- o[!is.na(x) & site_id %chin% st$site_id, .(qid = .I, site_id, qx = x, qy = y)]
  nn <- rbindlist(lapply(unique(cand$r), function(rad) nearest_within(cand[r == rad, .(pid = zaak_id, x, y)], obj, rad)))
  nn[obj, on = "qid", site_id := i.site_id]
  rd_log("B. %s candidate cases (new dwellings or demolition of a dwelling, precise location, %s to %s); %.1f%% within reach of an object",
         format(nrow(cand), big.mark = ","), format(cfg$permits_national_from), format(cfg$permits_end), 100 * nrow(nn) / nrow(cand))
  at <- merge(cand[, .(zaak_id, x, y, eerste_datum, uitkomst, uitgebreid, nieuwbouw, nieuwbouw_echt, vervanging, sloop_woning,
                       n_uitspraken, eerste_identifier)],
              nn[, .(zaak_id = pid, site_id, d)], by = "zaak_id")
  at[, zym := ym_of(eerste_datum)]
  # New construction of ANOTHER site within cfg$attempt_elsewhere_m after the case: the case was
  # most likely about that plot (often the vacant lot next door), not about this site.
  r_e <- cfg$attempt_elsewhere_m
  nw <- o[is_plus == TRUE & !is.na(x), .(qid = .I, site_n = site_id, qx = x, qy = y, ym = redev_yearmonth)]
  pr <- nearest_within(at[, .(pid = zaak_id, x, y)], nw, r_e, all_pairs = TRUE)
  pr[nw, on = "qid", `:=`(site_n = i.site_n, ym = i.ym)]
  pr[at, on = .(pid = zaak_id), `:=`(site_id = i.site_id, zym = i.zym)]
  at[, elsewhere := zaak_id %in% pr[ym >= zym & site_n != site_id, pid]]
  at[, strict := !elsewhere & d <= cfg$attempt_strict_m & (nieuwbouw_echt == 1L | vervanging == 1L | sloop_woning == 1L)]
  rd_log("   linked cases %s; followed by new construction of another site within %d m: %.1f%%; strict: %s",
         format(nrow(at), big.mark = ","), r_e, pct(at$elsewhere), format(at[, sum(strict)], big.mark = ","))
  s <- at[strict == TRUE, .(att_n = .N, att_first = min(eerste_datum),
                            att_granted = any(uitkomst %chin% "verleend"), att_refused = any(uitkomst %chin% "geweigerd"),
                            att_withdrawn = any(uitkomst %chin% "ingetrokken"), att_extended = any(uitgebreid %in% 1L),
                            att_appeal = any(n_uitspraken > 0L), att_replacement = any(vervanging == 1L)), by = site_id]
  list(cases = at, per_site = s)
}

planned_per_site <- function(pe, o, st) {
  inc <- o[is_incumbent == TRUE & !is.na(x) & site_id %chin% st$site_id, .(qid = .I, site_id, qx = x, qy = y)]
  gp <- pe$planned[!is.na(x) & !is.na(y), .(pid = .I, status, verg_datum, x = as.numeric(x), y = as.numeric(y))]
  nn <- nearest_within(gp, inc, cfg$bag_planned_m)
  nn[inc, on = "qid", site_id := i.site_id][gp, on = "pid", `:=`(status = i.status, verg = i.verg_datum)]
  rd_log("B. Planned new objects not in use (permit from 2012): %s; within %g m of a standing object: %s",
         format(nrow(gp), big.mark = ","), cfg$bag_planned_m, format(nrow(nn), big.mark = ","))
  nn[, .(plan_n = .N, plan_first_permit = min(verg),
         plan_not_started = any(status == "Bouwvergunning_verleend"), plan_started = any(status == "Bouw_gestart"),
         plan_not_realized = any(status == "Niet_gerealiseerd_pand")), by = site_id]
}

## ---- C. zoning per site ------------------------------------------------------------------
zoning_per_site <- function(pe, o, st) {
  inc <- o[is_incumbent == TRUE & !is.na(x) & site_id %chin% st$site_id,
           .(site_id, x = round(x), y = round(y), obj_is_woon, housetype)]
  zp <- pe$zoning[, .(x = round(x), y = round(y), plan, plandatum, hoofdgroep, woningtype_orde, bouwhoogte, wooneenheden, in_bouwvlak)]
  zp <- unique(zp, by = c("x", "y"))
  z <- zp[inc, on = .(x, y), nomatch = 0L]
  mx <- function(v) if (all(is.na(v))) NA_real_ else as.numeric(max(v, na.rm = TRUE))
  hg <- z[!is.na(hoofdgroep), .N, by = .(site_id, hoofdgroep)][order(site_id, -N, hoofdgroep)][!duplicated(site_id), .(site_id, zon_group = hoofdgroep)]
  zs <- z[, .(zon_allowed_order = as.integer(mx(woningtype_orde)), zon_height = mx(bouwhoogte), zon_units = mx(wooneenheden),
              zon_in_bouwvlak = mean(in_bouwvlak), zon_plan_date = max(plandatum), zon_points = .N), by = site_id]
  zs <- merge(hg, zs, by = "site_id", all = TRUE)
  # densest existing dwelling type (same order as the designation)
  ex <- inc[obj_is_woon == TRUE & housetype %chin% names(wp4_order), .(existing_order = max(wp4_order[housetype])), by = site_id]
  zs[ex, on = "site_id", existing_order := i.existing_order]
  zs[, zon_residential := zon_group %chin% c("wonen", "woongebied")]
  # zoning gap in type terms; without a designation the plan does not fix the type (own class)
  zs[, zon_gap_class := fcase(is.na(zon_group), NA_character_,
                              !zon_residential, "non-residential zoning",
                              is.na(zon_allowed_order), "residential, no type designation",
                              is.na(existing_order) | zon_allowed_order > existing_order, "residential, room for a denser type",
                              default = "residential, no room for a denser type")]
  # small plans touching the site: dates only (per site, sorted)
  sp <- unique(pe$small_plans[, .(x = round(x), y = round(y), plan, datum)])[unique(inc[, .(site_id, x, y)]), on = .(x, y), nomatch = 0L]
  sp <- unique(sp[!is.na(datum), .(site_id, plan, datum)])
  rd_log("C. Zoning of %s: %s of %s sites with a plan (%.1f%%); small plans touching a site: %s links",
         cfg$zoning_date, format(zs[!is.na(zon_group), .N], big.mark = ","), format(nrow(st), big.mark = ","),
         100 * zs[!is.na(zon_group), .N] / nrow(st), format(nrow(sp), big.mark = ","))
  list(per_site = zs, small_plans = sp)
}

## ---- the per-site table ------------------------------------------------------------------
build_permit_sites <- function(pe, o, st) {
  A  <- pipeline_sites(pe, o, st)
  at <- attempts_per_site(pe, o, st)
  pl <- planned_per_site(pe, o, st)
  zo <- zoning_per_site(pe, o, st)
  ps <- copy(st)
  ps[A, on = "site_id", `:=`(sn_permit = i.verg, sn_start = i.start, sn_compl = i.compl, sn_zaak_id = i.zaak_id,
                             sn_case_first_id = i.z_first_id)]
  ps[at$per_site, on = "site_id", names(at$per_site)[-1] := mget(paste0("i.", names(at$per_site)[-1]))]
  ps[pl, on = "site_id", names(pl)[-1] := mget(paste0("i.", names(pl)[-1]))]
  ps[zo$per_site, on = "site_id", names(zo$per_site)[-1] := mget(paste0("i.", names(zo$per_site)[-1]))]
  ps[is.na(att_n), `:=`(att_n = 0L, att_granted = FALSE, att_refused = FALSE, att_withdrawn = FALSE,
                        att_extended = FALSE, att_appeal = FALSE, att_replacement = FALSE)]
  ps[, attempt := att_n > 0L]
  ps[is.na(plan_n), `:=`(plan_n = 0L, plan_not_started = FALSE, plan_started = FALSE, plan_not_realized = FALSE)]
  ps[, bag_planned := plan_n > 0L]
  # plan change as a step: a small plan in the five years before completion (SN), or dated in a
  # calendar year (per-year rate for the other sites)
  sp <- zo$small_plans
  sn <- ps[group == "SN" & !is.na(redev_ym), .(site_id, compl_d = as.IDate(sprintf("%d-%02d-15", redev_ym %/% 100L, redev_ym %% 100L)))]
  x <- sp[sn, on = "site_id", nomatch = 0L][datum < compl_d & datum >= compl_d - round(5 * 365.25)]
  ps[, small_plan_5y_before := fifelse(group == "SN" & !is.na(redev_ym), site_id %chin% x$site_id, NA)]
  list(sites = ps, pipeline = A, attempts = at$cases, small_plans = sp)
}

## ---- tables ------------------------------------------------------------------------------
permit_tables <- function(P, labels) {
  A <- P$pipeline
  A[labels, on = "K", alt := i.label]
  tabs <- list()
  tabs$pipeline_K <- rbind(
    A[!is.na(K), cbind(scope = "all", pipeline_measures(.SD)), keyby = .(K, alt)],
    A[!is.na(K) & urban == TRUE, cbind(scope = sprintf("OAD >= %d", cfg$oad_min), pipeline_measures(.SD)), keyby = .(K, alt)])
  tabs$pipeline_oad <- A[!is.na(oad_class), pipeline_measures(.SD), keyby = oad_class]
  tabs$pipeline_year <- A[, .(sites = .N, in_window = sum(in_window), linked = sum(in_window & !is.na(zaak_id))),
                          keyby = .(completion_year = redev_ym %/% 100L)]
  tabs$pipeline_case_type <- A[in_window == TRUE & !is.na(zaak_id), .N, by = .(type = fcoalesce(z_type, "no application"))][
    , pct := 100 * N / sum(N)][order(-N)]
  tabs$pipeline_contrasts <- pipeline_contrasts(A)
  S <- P$sites
  S[, grp := fcase(group == "SN" & redev_ym >= ym_of(cfg$permits_national_from), "SN, completed from July 2021",
                   group == "SN", "SN, completed before July 2021", group == "S", "demolition without follow-up",
                   group == "O", "withdrawal", group == "Onv", "unchanged", default = NA_character_)]
  meas <- function(d) d[, .(sites = .N, pct_attempt = pct(attempt), attempt_pct_granted = pct(att_granted[attempt]),
                            attempt_pct_refused = pct(att_refused[attempt]), attempt_pct_withdrawn = pct(att_withdrawn[attempt]),
                            attempt_pct_extended = pct(att_extended[attempt]), attempt_pct_appeal = pct(att_appeal[attempt]),
                            pct_bag_planned = pct(bag_planned), planned_pct_not_started = pct(plan_not_started[bag_planned]),
                            planned_pct_started = pct(plan_started[bag_planned]), planned_pct_not_realized = pct(plan_not_realized[bag_planned]))]
  U <- S[!is.na(grp) & has_incumbent == TRUE]
  tabs$attempts_group <- rbind(cbind(scope = "all", U[, meas(.SD), keyby = grp]),
                               cbind(scope = sprintf("OAD >= %d", cfg$oad_min), U[urban == TRUE, meas(.SD), keyby = grp]))
  tabs$attempt_capture <- S[group == "SN" & redev_ym >= ym_of(cfg$permits_national_from),
                            .(sites = .N, pct_attempt = pct(attempt), pct_bag_planned = pct(bag_planned)), keyby = .(completion_year = redev_ym %/% 100L)]
  tabs$planned_unchanged_year <- S[group == "Onv" & bag_planned == TRUE, .(sites = .N, pct_not_started = pct(plan_not_started),
                                                                           pct_started = pct(plan_started), pct_not_realized = pct(plan_not_realized)),
                                   keyby = .(permit_year = as.integer(format(plan_first_permit, "%Y")))]
  # zoning of end 2013: redeveloped (completed from cfg$zoning_redev_from) against unchanged
  Z <- S[has_incumbent == TRUE & (group == "Onv" | (group == "SN" & redev_ym >= cfg$zoning_redev_from))]
  Z[, zgrp := fifelse(group == "SN", sprintf("SN, completed from %d", cfg$zoning_redev_from %/% 100L), "unchanged")]
  tabs$zoning_coverage <- Z[, .(sites = .N, pct_with_plan = pct(!is.na(zon_group)), pct_with_designation = pct(!is.na(zon_allowed_order)),
                                pct_with_height = pct(!is.na(zon_height)), pct_with_units = pct(!is.na(zon_units))), keyby = .(urban, zgrp)]
  tabs$zoning_gap <- dcast(Z[!is.na(zon_gap_class), .N, by = .(urban, zgrp, zon_gap_class)][, pct := 100 * N / sum(N), by = .(urban, zgrp)],
                           urban + zon_gap_class ~ zgrp, value.var = "pct", fill = 0)
  tabs$zoning_group <- dcast(Z[!is.na(zon_group), .N, by = .(urban, zgrp, zon_group)][, pct := 100 * N / sum(N), by = .(urban, zgrp)],
                             urban + zon_group ~ zgrp, value.var = "pct", fill = 0)[order(urban, -unchanged)]
  sk <- Z[group == "SN" & !is.na(K)]
  sk[labels, on = "K", `:=`(alt = i.label, alt_order = i.order)]
  tabs$zoning_K <- sk[, .(sites = .N, with_plan = sum(!is.na(zon_group)), pct_residential_zoning = pct(zon_residential[!is.na(zon_group)]),
                          with_designation = sum(!is.na(zon_allowed_order)),
                          pct_denser_than_allowed = pct((alt_order > zon_allowed_order)[!is.na(zon_allowed_order)]),
                          pct_small_plan_5y_before = pct(small_plan_5y_before)), keyby = .(K, alt)]
  tabs
}

## ---- D. models ---------------------------------------------------------------------------
# Stage 1 with feasibility: infeasible_k = alternative k needs a denser type than the building
# designation of end 2013 allows. Same sites with and without the term, so the ASCs compare.
stage1_zoning <- function(alt, ps, labels) {
  st <- alt$sites
  real <- st[!is.na(cluster_real), site_id]
  est <- alt$long[site_id %chin% real]
  complete <- est[, .(ok = !anyNA(rv_ha_eur)), by = site_id][ok == TRUE, site_id]
  est <- est[site_id %chin% complete]
  est[st, on = "site_id", `:=`(oad = i.oad, site_ha = i.site_ha, gemeente_code = i.gemeente_code)]
  est[ps, on = "site_id", `:=`(redev_ym = i.redev_ym, zon_allowed_order = i.zon_allowed_order, zon_group = i.zon_group)]
  est <- est[!is.na(oad) & oad >= cfg$oad_min & site_ha > 0 & redev_ym >= cfg$zoning_redev_from & !is.na(zon_group)]
  est[, `:=`(rv_ha = rv_ha_eur / 1e6, alt_f = factor(cluster_alt))]
  est[labels, on = .(cluster_alt = K), alt_order := i.order]
  est[, infeasible := as.integer(!is.na(zon_allowed_order) & alt_order > zon_allowed_order)]
  f0 <- clogit(ca ~ rv_ha + alt_f + strata(site_id) + cluster(gemeente_code), data = est, method = "efron")
  f1 <- clogit(ca ~ rv_ha + alt_f + infeasible + strata(site_id) + cluster(gemeente_code), data = est, method = "efron")
  tab <- function(f, lab) { cf <- summary(f)$coefficients
    data.table(spec = lab, term = rownames(cf), estimate = cf[, "coef"], se_cluster = cf[, "robust se"], z = cf[, "z"],
               p = cf[, "Pr(>|z|)"], n_sites = f$nevent) }
  res <- rbind(tab(f0, "zoning_sample"), tab(f1, "zoning"))
  rd_log("D. Stage 1 on %s SN sites with a plan of end 2013 (completed from %d): infeasible %+.3f (z %.1f), rv_ha %+.3f -> %+.3f",
         format(f1$nevent, big.mark = ","), cfg$zoning_redev_from %/% 100L, coef(f1)[["infeasible"]],
         summary(f1)$coefficients["infeasible", "z"], coef(f0)[["rv_ha"]], coef(f1)[["rv_ha"]])
  list(coef = res, share_infeasible_chosen = est[ca == 1L, pct(infeasible == 1L)], share_infeasible_all = est[, pct(infeasible == 1L)])
}

# Stage-2 robustness on the base sample of 07.
stage2_permit_specs <- function(alt, s, s1, ps) {
  uni  <- build_stage2_input(alt, s, s1)
  smp  <- stage2_samples(uni)
  base <- smp$core[oad >= cfg$oad_min]
  cols <- c("attempt", "att_refused", "att_withdrawn", "bag_planned", "plan_not_started", "plan_started", "plan_first_permit",
            "att_first", "sn_permit", "redev_ym", "zon_gap_class")
  base[ps, on = "site_id", (cols) := mget(paste0("i.", cols))]
  f <- stage2_f_base
  fits <- list()
  fits$base <- fit_stage2(f, base, "base")
  # (1) unchanged sites with a permitted replacement that is not (yet) realized decided to redevelop
  d1 <- copy(base)[prefix == "Onv" & (plan_not_started | plan_started), y := TRUE]
  fits$pending_y1 <- fit_stage2(f, d1, "pending_y1")
  # (2) without unchanged sites where a strict attempt was refused or withdrawn (a public block)
  fits$excl_blocked <- fit_stage2(f, base[!(prefix == "Onv" & (att_refused | att_withdrawn))], "excl_blocked")
  # (3) decisions from July 2021, when the announcements are nationally complete: SN sites whose
  #     first BAG permit falls in the window against the unchanged sites; y = SN, and then y = SN or
  #     an attempt or permitted replacement on an unchanged site in the window (decision2021)
  w0 <- cfg$permits_national_from
  d3 <- base[prefix == "Onv" | (y == TRUE & !is.na(sn_permit) & sn_permit >= w0)]
  fits$window2021 <- fit_stage2(f, d3, "window2021")
  d4 <- copy(d3)[prefix == "Onv" & (attempt | (!is.na(plan_first_permit) & plan_first_permit >= w0 & (plan_not_started | plan_started))),
                 y := TRUE]
  fits$decision2021 <- fit_stage2(f, d4, "decision2021")
  # (4) zoning of end 2013 (unchanged sites and SN completed from cfg$zoning_redev_from with a plan)
  d5 <- base[!is.na(zon_gap_class) & (prefix == "Onv" | redev_ym >= cfg$zoning_redev_from)]
  d5[, zon_gap_class := relevel(factor(zon_gap_class), "residential, no type designation")]
  fits$zoning_sample <- fit_stage2(f, d5, "zoning_sample")
  fits$zoning <- fit_stage2(update(f, . ~ . + zon_gap_class), d5, "zoning")
  rbindlist(lapply(fits, `[[`, "ct"))
}

# Hazard with the BAG permit date as decision moment (SN sites with a permit date), H2 spec of 09.
hazard_permit <- function(alt, s, s1, ps) {
  s2 <- s
  s2$incumbent <- copy(s$incumbent)
  pm <- ps[group == "SN" & !is.na(sn_permit), .(site_id, pym = ym_of(sn_permit))]
  s2$incumbent[pm, on = "site_id", event_yearmonth := i.pym]
  # SN sites without a BAG permit date leave the permit panel (no decision date)
  s2$incumbent[startsWith(site_id, "SN_") & !site_id %chin% pm$site_id, event_yearmonth := NA_integer_]
  fit <- function(panel, label) {
    est <- panel[!is.na(vol_roll) & !is.na(g_roll)]
    m <- feglm(as.formula(paste("y_year ~", hazard_f_rhs, "+ vol_roll + g_roll | year")), data = est,
               family = binomial(), cluster = ~gemeente_code, glm.iter = 100, glm.tol = 1e-6)
    ct <- as.data.table(summary(m)$coeftable, keep.rownames = "term")
    setnames(ct, c("term", "estimate", "se_cluster", "z", "p"))
    ct[, `:=`(spec = label, n_site_years = nrow(est), n_events = est[, sum(y_year)])]
    rd_log("D. Hazard %s: %s site-years, %s events; vol_roll %+.2f (z %.1f), iv %+.3f (z %.1f)", label,
           format(nrow(est), big.mark = ","), format(est[, sum(y_year)], big.mark = ","),
           ct[term == "vol_roll", estimate], ct[term == "vol_roll", z], ct[term == "iv", estimate], ct[term == "iv", z])
    ct
  }
  rbind(fit(build_hazard_panel(alt, s, s1), "H2_demolition"), fit(build_hazard_panel(alt, s2, s1), "H2_permit"))
}

# Waiting after the permit: log days from BAG permit to construction start against the rolling
# local volatility and growth in the permit year, within gemeente and permit year, per alternative.
# Only sites that started (censoring: late starters drop out).
permit_start_volatility <- function(A, st_coords) {
  d <- A[!is.na(verg) & !is.na(start) & start >= verg & !is.na(K)]
  d[, `:=`(year_vol = as.integer(format(verg, "%Y")), log_wait = log(pmax(as.integer(start - verg), 1)))]
  d <- d[year_vol >= 2012L & year_vol <= cfg$hazard_last_year]
  d[st_coords, on = "site_id", `:=`(x_coord = i.x_coord, y_coord = i.y_coord)]
  d[, cel := paste0(x_coord %/% cfg$vol_cel_m, "_", y_coord %/% cfg$vol_cel_m)]
  vg  <- fread(cfg$file_vol_rolling("grid5km")); vgm <- fread(cfg$file_vol_rolling("gemeente_code"))
  d[vg,  on = .(cel = regio, year_vol = besluitjaar), `:=`(v1 = i.vol_roll5, g1 = i.g_roll5)]
  d[vgm, on = .(gemeente_code = regio, year_vol = besluitjaar), `:=`(v2 = i.vol_roll5, g2 = i.g_roll5)]
  d[, `:=`(vol_roll = fcoalesce(v1, v2), g_roll = fcoalesce(g1, g2), ln_site_ha = log(site_size / 1e4))]
  d <- d[!is.na(vol_roll) & is.finite(ln_site_ha)]
  m <- feols(log_wait ~ vol_roll + g_roll + i(K, ref = 1) + ln_site_ha | year_vol + gemeente_code, data = d,
             cluster = ~gemeente_code, notes = FALSE)
  ct <- coeftable(m)
  res <- data.table(term = rownames(ct), estimate = ct[, 1], se_cluster = ct[, 2], p = ct[, 4], n = nobs(m))
  rd_log("D. Permit to start (log days) on %s SN sites: vol_roll %+.2f (p %.2f)", format(nobs(m), big.mark = ","),
         res[term == "vol_roll", estimate], res[term == "vol_roll", p])
  list(coef = res, by_year = d[, .(sites = .N, days_med = med(exp(log_wait))), keyby = year_vol])
}

## ---- markdown output ---------------------------------------------------------------------
md_dt <- function(dt, digits = 2) {
  dt <- copy(dt)
  for (v in names(dt)) if (is.numeric(dt[[v]]) && !is.integer(dt[[v]])) set(dt, j = v, value = round(dt[[v]], digits))
  for (v in names(dt)) set(dt, j = v, value = as.character(dt[[v]]))
  c(paste0("| ", paste(names(dt), collapse = " | "), " |"), paste0("|", strrep("---|", ncol(dt))),
    vapply(seq_len(nrow(dt)), function(i) paste0("| ", paste(unlist(dt[i]), collapse = " | "), " |"), character(1)))
}

write_permit_md <- function(res) {
  t <- res$tables
  sec <- function(title, dt, note = NULL, digits = 2) if (!is.null(dt) && nrow(dt)) c("", paste("##", title), "", if (!is.null(note)) c(note, ""), md_dt(dt, digits))
  out <- c(sprintf("# Permits, procedure and zoning per site (issue #30), %s", format(Sys.time(), "%Y-%m-%d %H:%M")), "",
           sprintf("Permit export: `%s`. Windows: BAG-case link from %s, announcements nationally complete from %s, through %s; zoning plan of %s.",
                   basename(res$permit_dir), format(cfg$permits_bag_from), format(cfg$permits_national_from), format(cfg$permits_end), cfg$zoning_date),
    sec("Pipeline per alternative K (SN sites)", t$pipeline_K,
        "Linked = new buildings of the site in the BAG-case link (permit from June 2021). Procedure, extended and refused/withdrawn refer to the linked case; extended among recognizable new-construction cases. Only projects completed before July 2026: long projects drop out."),
    sec("Contrasts per alternative against K = 1, within the municipality", t$pipeline_contrasts,
        "Linear, SE clustered on gemeente; extended in percentage points, the durations in logs (exp(b) - 1 = relative difference).", 3),
    sec("Pipeline per OAD class (SN sites)", t$pipeline_oad),
    sec("SN sites per completion year: coverage of the BAG-case link", t$pipeline_year),
    sec("Type of the linked case (from the titles)", t$pipeline_case_type),
    sec("Attempts and permitted replacement per group (stage-2 universe)", t$attempts_group,
        "Attempt = strict attempt, first publication July 2021 - June 2026. BAG planned = a new object not in use within 5 m of a standing object, permit from 2012."),
    sec("Capture of the measures among SN sites completed from July 2021", t$attempt_capture),
    sec("Unchanged sites with a planned object, by permit year", t$planned_unchanged_year),
    sec("Zoning of end 2013: coverage", t$zoning_coverage),
    sec("Zoning of end 2013: gap class (percent)", t$zoning_gap),
    sec("Zoning of end 2013: main land-use group (percent)", t$zoning_group),
    sec("Zoning of end 2013 per alternative K (SN sites)", t$zoning_K),
    if (!is.null(res$stage1_zoning)) sec("Stage 1 with feasibility per alternative", res$stage1_zoning$coef,
        sprintf("infeasible = alternative denser than the building designation of end 2013 allows; %.1f%% of all alternatives, %.1f%% of the chosen ones.",
                res$stage1_zoning$share_infeasible_all, res$stage1_zoning$share_infeasible_chosen), 3),
    if (!is.null(res$stage2)) sec("Stage 2: permit and zoning specifications", res$stage2[!(term %like% "bouwperiode")], NULL, 3),
    if (!is.null(res$hazard)) sec("Hazard: decision moment demolition versus permit (H2)", res$hazard[!(term %like% "bouwperiode")], NULL, 3),
    if (!is.null(res$wait)) sec("Waiting after the permit: log days to construction start", res$wait$coef, NULL, 3))
  f <- file.path(cfg$dir_work, sprintf("permits_tables%s_%s_%s.md", cfg$sample_suffix, cfg$area, cfg$bag_date))
  writeLines(out, f, useBytes = FALSE)
  rd_log("Written: %s", f)
  rd_md_to_docx(f)
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_11", ifnotfound = FALSE))) {
  pe <- read_permit_export()
  o  <- slim_objects()
  s  <- readRDS(cfg$file_sites_rds)
  cl <- readRDS(cfg$file_clusters_rds)
  st <- site_table(s, cl)
  labels <- alternative_labels(cl)
  P <- build_permit_sites(pe, o, st)
  rm(o); invisible(gc())
  res <- list(sites = P$sites, tables = permit_tables(P, labels), labels = labels, permit_dir = pe$dir,
              made = format(Sys.time(), "%Y-%m-%d %H:%M"))
  print(res$tables$pipeline_K[, lapply(.SD, function(v) if (is.double(v)) round(v, 1) else v)])

  if (file.exists(cfg$file_alt_rds) && file.exists(cfg$file_stage1_rds)) {
    alt <- readRDS(cfg$file_alt_rds)
    s1  <- readRDS(cfg$file_stage1_rds)
    res$stage1_zoning <- stage1_zoning(alt, P$sites, labels)
    res$stage2 <- stage2_permit_specs(alt, s, s1, P$sites)
    res$hazard <- hazard_permit(alt, s, s1, P$sites)
    rm(alt); invisible(gc())
  } else rd_log("D. No alternatives/stage-1 results yet: models skipped")
  res$wait <- permit_start_volatility(P$pipeline, s$attrs[, .(site_id, x_coord, y_coord)])

  saveRDS(res, cfg$file_permits_rds, compress = FALSE)
  rd_log("Written: %s", cfg$file_permits_rds)
  write_permit_md(res)
}
