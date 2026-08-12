# 02_models.R — the regressions of Tables 3 and 4.
# Port of the ANALYSES block of stata/Redevelopment_regressie.do (lines 219-344).
# Output: Output/R/models_<filedate>.rds
#
# Two specifications per outcome:
#   base : reg ln_y  p_huurcorp uai p_beschermd p_onbebouwd ib5.construction_period, r
#   inter: reg ln_y  c.p_huurcorp##i.urb  c.uai##i.urb  p_beschermd  c.p_onbebouwd##i.urb
#          ib5.construction_period, r        (+ margins urb, dydx(p_huurcorp uai p_onbebouwd))
#
# Stata `, r` = HC1; fixest vcov = "hetero" applies the same n/(n-k) adjustment.

if (!exists(".rd_script_dir")) {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  .rd_script_dir <- if (length(f)) dirname(normalizePath(f[1])) else getwd()
}
source(file.path(.rd_script_dir, "00_config.R"))
suppressPackageStartupMessages(library(fixest))

# Two-sided normal p-value from a t/z ratio. Stata's `reg` reports t with n-k df; for
# these sample sizes (n > 1700) the normal and t tails agree to more decimals than we print.
p_two <- function(z) 2 * pnorm(-abs(z))

# Tidy a fixest fit into one row per coefficient.
tidy_fit <- function(m) {
  ct <- summary(m)$coeftable
  data.table(term = rownames(ct), estimate = ct[, 1], se = ct[, 2],
             t = ct[, 3], p = ct[, 4])
}

# Average marginal effect of `var` within each density category.
#
# The model is linear, so the marginal effect of x in group g is simply
#   b_x + b_{x:g}   (with b_{x:ref} = 0),
# constant within the group — no averaging over observations is needed, which is why this
# reproduces Stata's `margins urb, dydx(x)` exactly. The standard error follows from the
# variance of that linear combination: Var(a'b) = a' V a.
ame_by_group <- function(m, var, groups) {
  b <- coef(m); V <- vcov(m)
  rbindlist(lapply(groups, function(g) {
    nm <- if (g == cfg$urb_ref) var else paste0(var, ":urbanisation", g)
    # fixest writes interaction terms as "x:factorLevel"; try the reverse order too.
    if (!nm %in% names(b) && g != cfg$urb_ref) {
      alt <- paste0("urbanisation", g, ":", var)
      if (alt %in% names(b)) nm <- alt else stop("Interaction term not found: ", nm)
    }
    a <- rep(0, length(b)); names(a) <- names(b)
    a[var] <- 1
    if (g != cfg$urb_ref) a[nm] <- 1
    est <- sum(a * b); se <- sqrt(drop(t(a) %*% V %*% a))
    data.table(var = var, group = g, estimate = est, se = se,
               t = est / se, p = p_two(est / se))
  }))
}

estimate_all <- function(wijk) {
  groups <- unname(cfg$urb_levels)
  rhs_base  <- "p_huurcorp + uai + p_beschermd + p_onbebouwd + construction_period"
  rhs_inter <- paste("p_huurcorp * urbanisation + uai * urbanisation + p_beschermd +",
                     "p_onbebouwd * urbanisation + construction_period")

  out <- list(base = list(), inter = list(), ames = list())
  for (nm in names(cfg$outcomes)) {
    y <- paste0("ln_", nm)

    m_base <- feols(as.formula(paste(y, "~", rhs_base)), data = wijk, vcov = cfg$vcov_main)
    m_int  <- feols(as.formula(paste(y, "~", rhs_inter)), data = wijk, vcov = cfg$vcov_main)

    out$base[[nm]]  <- list(fit = m_base, ct = tidy_fit(m_base),
                            n = nobs(m_base), r2 = fitstat(m_base, "r2")$r2)
    out$inter[[nm]] <- list(fit = m_int, ct = tidy_fit(m_int),
                            n = nobs(m_int), r2 = fitstat(m_int, "r2")$r2)
    out$ames[[nm]]  <- rbindlist(lapply(c("p_huurcorp", "uai", "p_onbebouwd"),
                                        ame_by_group, m = m_int, groups = groups))
    rd_log("%-16s base: N=%5d R2=%.3f | interaction: N=%5d R2=%.3f",
           cfg$outcomes[[nm]]$label, nobs(m_base), fitstat(m_base, "r2")$r2,
           nobs(m_int), fitstat(m_int, "r2")$r2)
  }
  out
}

## ---------------------------------------------------------------------------
if (sys.nframe() == 0L || isTRUE(get0("run_02", ifnotfound = FALSE))) {
  wijk <- readRDS(cfg$file_wijk_rds)
  models <- estimate_all(wijk)
  saveRDS(models, cfg$file_models_rds)
  rd_log("Written: %s", cfg$file_models_rds)
}
