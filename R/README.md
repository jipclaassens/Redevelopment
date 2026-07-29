# R analysis pipeline — densification paper (issue #16)

Object-level GeoDMS export → site aggregation → k-means alternatives → two-stage logit →
discrete-time hazard. Style follows the R pipeline in `C:/ProjDir/_Tools/PriceIndices/R`.

## Prerequisites (GeoDMS side, once per BAG vintage)

1. `GeoDmsRun.exe Redevelopment.dms /MaakOntkoppeldeData/Write_FinalMutationTable`
2. `GeoDmsRun.exe Redevelopment.dms /MaakOntkoppeldeData/PerObject_Export`
   → `%LocalDataProjDir%/Temp/PerObject_Export_<StudyArea>_<BAG_file_date>.mmd`
3. `GeoDmsRun.exe Redevelopment.dms /Analyse/PriceComponents/ExportCoefficients_WP4/Export_CSV`
   → `%LocalDataProjDir%/Temp/PriceCoefficients_WP4_<NVM_filedate>.csv`
4. PriceIndices `R/06_volatility.R` → `NVM Prijsindex/Output/Volatility[_rolling]_<tag>_*.csv`

## Steps

| script | does | output (in `%LocalDataDir%/Redevelopment/R_werk`) |
|---|---|---|
| `00_config.R` | paths (registry), classification maps, parameters and defaults | — |
| `01_read_mmd.R` | reader for GeoDMS mmd exports (binary, tiled strings, bit-packed bools; polygon columns skipped) | — |
| `02_load_perobject.R` | mmd → data.table; labels, 2012 flag (#26); hedonic incumbent value `exp(constant + Σ coef·char)` per WP4 + WOZ value non-residential | `perobject_*.rds` |
| `03_sites.R` | step 0: aggregate to sites (incumbent state + realised new state) on `site_id`; demolition costs, permit/timing flags, event year | `sites_*.rds` |
| `04_kmeans.R` | step 1: stage-1 sample filter (`cfg$stage1_sample`, default SN) → winsorize p1/p99 → standardise → elbow (Makles 2012) → final k-means (K = 6, confirmed) | `clusters_sn_*.rds`, `elbow_sn.csv` |
| `05_alternatives.R` | steps 2a–2c: long table site × cluster with revenue (bulk hedonic predict), costs (land production / construction / demolition) and residual value + choice indicator | `alternatieven_sn_*.rds` |
| `06_stage1_logit.R` | steps 3+4: conditional logit (survival::clogit, RV + ASCs) on the stage-1 sample within the OAD scope; robustness without multi-project sites; inclusive value for ALL sites | `stage1_sn_*.rds` |
| `07_stage2_logit.R` | step 5: binomial logit redevelopment (fixest::feglm, SEs clustered on gemeente); 10-spec battery + AMEs | `stage2_sn_*.rds`, `stage2_specs_sn_*.csv` |
| `08_tables.R` | paper tables (markdown): stage 1, stage-2 main + robustness specs, AMEs | `paper_tabellen_sn_*.md` |
| `09_hazard.R` | extension: discrete-time hazard (site × year panel), time-varying rolling volatility + growth (Capozza-Li), H1–H4 battery | `hazard_sn_*.rds` |
| `run_all.R` | everything in sequence | |

Run: `Rscript run_all.R` (or per step; every script runs standalone).

## Key choices (details in the script headers and STATUS.md)

- **Scope**: urban area via OAD ≥ `cfg$oad_min` (1000; replaces the earlier 22-agglomerations
  idea) for the stage-1/2 estimation samples; the cluster menu and inclusive values stay national.
- **Outcome**: sloop-nieuwbouw (SN) = redeveloped; transformation is out of scope (decision
  28-07); demolition/withdrawal without follow-up = pipeline censoring (robustness: `demol_start`).
- **BBG-route SN sites** (`is_sn_door_bbg`): fine for stage 1, excluded from stage-2 estimation
  (acquisition unknown); imputation robustness `bbg_imput`.
- **Price level**: fixed `trans_year_2023` dummy; transactions run through 2023.
- **Incumbent proxies**: regional averages (`reg_<wp4>_*`) for unobserved characteristics;
  `d_hoogte_onbekend` has no regional mean and is set to 0.
- **Volatility**: no robust real-options evidence in regionally identified specs (H1–H3);
  the national uncertainty cycle is strongly negative (H4) but only indicatively identified.
