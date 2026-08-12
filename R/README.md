# R port of the Cities-paper neighbourhood analysis

Replaces `stata/Redevelopment_regressie.do`. The Stata licence has expired, so the do-file
cannot be re-run; this pipeline reproduces its results and is the basis for the revision.

```bash
"C:/Program Files/R/R-4.5.3/bin/Rscript.exe" R/run_all.R
```

Packages: `data.table`, `fixest` (both already installed). No `renv`.

| Script | Does |
|---|---|
| `00_config.R` | paths, export vintage, outcome definitions, Stata-compatible helpers |
| `01_load_perwijk.R` | reads the GeoDMS export, builds the analysis variables (do-file lines 9–210) |
| `02_models.R` | the ten regressions and the marginal effects (do-file lines 219–344) |
| `03_tables.R` | Tables 2–4 as markdown + docx |
| `04_validate.R` | cell-by-cell comparison with the published tables — **the gate** |
| `05_revision.R` | referee specifications: PPML with exposure, municipal FE, Randstad split |
| `06_omitted.R` | omitted-variable robustness: residual land value 2007 |

## Replication status

`04_validate.R` compares 205 cells (Table 3, Table 4 upper panel, Table 4 marginal effects)
plus every sample size and R². Current result:

```
Cells compared : 205
Max |deviation|: 0.0005      (= rounding at three decimals)
Mismatches     : 0
PASS — the R port reproduces Tables 3 and 4 of the first submission exactly.
```

Table 2 reproduces as well: 1.21/2.85, 0.32/0.98, 0.31/1.02, 0.27/1.10, 0.03/0.14,
21.41/15.03, 0.89/3.66, 3.02/13.15, 90.59/9.47, all matching the published values.

## Things found while porting

1. **The do-file points at the wrong export.** `global filedate = 20250603`, but that file
   does not reproduce the paper. In `Analyse_PerWijk_20250603.csv`, GeoDMS wrote *null*
   instead of 0 for `WegSpoor_area` and `Water_area` in the 1,311 neighbourhoods that
   contain neither roads/railways nor surface water. The nulls propagate into `land_area`
   and `p_onbebouwd` and cut every estimation sample roughly in half (N = 1,220 instead of
   2,538). The published tables come from **`20250602`**, which has 0 there.
   When regenerating the export, wrap the area sums in `MakeDefined(..., 0)`; until then
   `01_load_perwijk.R` patches the nulls and warns.

2. **The log transformation drops neighbourhoods.** `ln()` of zero or of a negative net
   change is missing in Stata, so neighbourhoods without net growth leave the sample:

   | Model | Zero | Negative | Lost to log | N |
   |---|---|---|---|---|
   | All | 51 | 0 | 51 | 2,538 |
   | Replacement | 359 | 97 | 456 | 2,162 |
   | New build | 364 | 0 | 364 | 2,239 |
   | Within-building | 211 | 251 | 462 | 2,143 |
   | Transformation | 383 | 525 | 908 | 1,706 |

   The headline model loses only 51 observations, but transformation loses 35%. The dropped
   neighbourhoods are those where demolition exceeded construction, which are spatially
   clustered in the shrinking regions — so the estimates describe growing neighbourhoods.

3. **Column 1 and column 3 are gross, columns 2, 4 and 5 are net.** `count_total_proces_-
   pluschange` sums the positive mutations without subtracting removals, and `New build`
   has no removal term. The manuscript describes all five as net additions.

4. **Two star conventions in one table.** `outreg2` used 0.01/0.05/0.10 for the upper panels
   of Tables 3 and 4; the hand-rolled `putexcel` block that produced the marginal effects
   used 0.001/0.01/0.05. Both footnotes claim the first. `03_tables.R` uses one convention.

5. **Standard errors were never printed.** `outreg2 ... nose` suppressed them, while the
   footnote claims "robust standard errors in parentheses" (reviewer 1, comment 18).
   They are printed now; the values are HC1, matching Stata's `, robust`.

6. **`wk_code` was dropped before saving** (do-file line 208), which is why no municipal
   identifier was available. `01_load_perwijk.R` derives `gm_code` from it and keeps it, for
   the fixed-effects specification reviewer 2 asks for.

## The revision specifications (`05_revision.R`)

Four specifications side by side per development process, output in
`Output/R/revision_tables_<filedate>.docx`:

1. **as published** — OLS on the log net change per hectare, HC1;
2. **PPML** — Poisson on gross additions with land area as exposure, HC1;
3. **PPML + municipal fixed effects**, standard errors clustered on municipality;
4. **PPML + Randstad interaction**, clustered on municipality.

Findings:

- The **selection disappears**: every PPML fit uses 2,558 neighbourhoods (the only loss is the
  63 missing social-housing values), against 1,706 for transformation in the published table.
- **Social housing and land availability survive every specification**, including municipal
  fixed effects. These are the two headline results and they are now much better defended.
- **Urban attractivity and heritage do not**: both lose significance in the "All" model once
  municipal fixed effects are added (0.031\*\*\* → 0.011 n.s. and 0.008\*\*\* → −0.003 n.s.),
  so those associations are largely *between* municipalities rather than within one. Heritage
  does survive for transformation (0.006\*\*), which is a sharper finding than the published
  general claim.
- **Spatial dependence is real**: the residual intraclass correlation at municipal level is
  0.23–0.31, so referee 2's fifth point is justified and clustering is required.
- **The Randstad differs systematically**: the land-availability coefficient is −0.127 outside
  the Randstad and −0.062 inside it (interaction +0.065\*\*\*, significant for all five
  processes), while urban attractivity matters more inside (+0.044\*\*\*).

Note that the PPML specifications model **gross** additions per process, which is what a count
model requires and which also removes the gross/net inconsistency of point 3 above. Removals
should therefore be reported separately rather than netted away.

## Omitted variables (`06_omitted.R`)

Adds the residual land value per m2 (2007, per PC4) — the only price measure that predates the
observation period — to the PPML + municipal FE specification. Observed for 2,160 of 2,621
neighbourhoods, so a middle column repeats the baseline on that subsample to separate the
sample effect from the effect of controlling for price.

- Land price is a strong predictor: elasticity 0.69–0.91, significant for every process.
- **Social housing and land availability survive it.** Land availability attenuates by roughly
  a quarter (−0.091 → −0.067 for "All") but stays strongly negative; note that land price and
  available land correlate at r = −0.67, so part of that attenuation is collinearity.
- **Heritage turns significantly negative once price is controlled for** (−0.004 n.s. →
  −0.009\*\*\*), which is theoretically more coherent: protected areas have high land values,
  and only after conditioning on those does the restraining effect of protection show up.
- The sample effect is negligible.

## Deferred deliberately

The EconLogicPaper configuration has newer identification logic (new construction and
related rules) and other configuration updates that are **not** in this repository. The
decision is to answer the review with the current implementation first and port those
changes afterwards, together with the newer data, so that this paper lines up with the next
one. Do not pull them in mid-revision.

The working tree does differ from the last commit, but only in storage format (`.fss` →
`.mmd`) and paths — `git diff` on `PrepBAG.dms` shows no change to the mutation logic.

## Next

See `Submission/Cities/2nd submission/Revision plan.md` in the OneDrive project for the
remaining items (greenfield/infill split, omitted variables, text edits). The pipeline is
arranged so reviewer-driven changes are additions rather than edits: new outcome definitions go
in `cfg$outcomes`, new specifications in `05_revision.R`, and `04_validate.R` keeps guarding the
original numbers until they are deliberately superseded.

Not yet possible here: Moran's I on the residuals needs `sf` and `spdep` (not installed) plus
neighbourhood centroids, which the current GeoDMS export does not contain. The residual
intraclass correlation is used as a substitute. Province comes from the
`Analyse_PerWijk_x_Jaar` export, since the cross-section carries no regional identifier —
worth adding `provincie_rel` and a centroid to `Analyse_PerWijk` when it is regenerated.
