# R-analysepijplijn densification-paper (issue #16)

Object-level GeoDMS-export → site-aggregatie → k-means-alternatieven → (t.z.t.) two-stage logit.
Stijl en opzet volgen de R-pipeline in `C:/ProjDir/_Tools/PriceIndices/R`.

## Vereisten (GeoDMS-kant, eenmalig per BAG-vintage)

1. `GeoDmsRun.exe Redevelopment.dms /MaakOntkoppeldeData/Write_FinalMutationTable`
2. `GeoDmsRun.exe Redevelopment.dms /MaakOntkoppeldeData/PerObject_Export`
   → `%LocalDataProjDir%/Temp/PerObject_Export_<StudyArea>_<BAG_file_date>.mmd`
3. `GeoDmsRun.exe Redevelopment.dms /Analyse/PriceComponents/ExportCoefficients_WP4/Export_CSV`
   → `%LocalDataProjDir%/Temp/PriceCoefficients_WP4_<NVM_filedate>.csv`

## Stappen

| script | doet | output (in `%LocalDataDir%/Redevelopment/R_werk`) |
|---|---|---|
| `00_config.R` | paden (registry), classificatie-maps, parameters | — |
| `01_read_mmd.R` | leesfuncties GeoDMS-mmd (binair, tiled strings, bit-packed bools) | — |
| `02_load_perobject.R` | mmd → data.table; labels, 2012-flag (#26); hedonische incumbentwaarde `exp(constant + Σ coef·kenmerk)` per WP4 + WOZ-waarde niet-woon | `perobject_*.rds` |
| `03_sites.R` | stap 0: aggregatie naar sites (incumbent-staat + gerealiseerde nieuwe staat) op `site_id` | `sites_*.rds` |
| `04_kmeans.R` | stap 1: winsorize p1/p99 → standaardiseren → elbow (Makles 2012) → definitieve k-means (K uit `cfg$kmeans_k_final`, 50 starts) | `clusters_*.rds`, `elbow.csv` |
| `05_alternatieven.R` | stap 2a–2c: long-tabel site × cluster met opbrengst (bulk hedonic predict), kosten (grondproductie/bouw/sloop) en residual value + keuze-indicator; defaults gedocumenteerd in de header | `alternatieven_*.rds` |
| `06_stage1_logit.R` | stap 3+4: conditional logit (survival::clogit, RV + ASC's) op het stage-1-sample; robuustheid zonder multi-projectsites; inclusive value voor álle sites | `stage1_*.rds` |
| `run_all.R` | alles achter elkaar | |

Draaien: `Rscript run_all.R` (of stap voor stap; elk script is zelfstandig draaibaar).

## Bewuste keuzes / open punten

- **Prijspeil**: vaste `trans_year_2023`-dummy (`cfg$prijspeil_jaar`); transacties liepen t/m 2023, objecten van 2024–2026 krijgen dus 2023-prijzen.
- **Incumbent-proxies**: nrooms/lotsize/d_maintgood/d_highrise van het object zijn onbekend → regiogemiddelden (`reg_<wp4>_*`, potential 5 km); `d_hoogte_onbekend` heeft geen regiogemiddelde en staat op 0.
- **log(tt_ovknoop)**: ondergrens `cfg$ovknoop_floor` (0.01 min) tegen log(0); de schatting zag waarden vanaf ~0.1.
- **Alternatieventabel (stap 2a–2c)**: defaults en beslispunten staan in de header van
  `05_alternatieven.R` en als `cfg$`-parameters (bouwkosten koop-kental, d_maintgood=1 voor
  nieuwbouw, vormfactor-mapping). Sloopkosten zijn k-invariant: vallen weg in stage 1, tellen
  door in de inclusive value.
- **Stap 3–5** (conditional logit, inclusive value, stage-2 logit) volgen; zie issue #16.
- **Universum stage 2** ("welke sites hadden herontwikkeld kunnen worden") is nog niet afgebakend —
  `sites` in `alternatieven_*.rds` heeft `heeft_incumbent`/`was_redeveloped` als bouwstenen;
  de onveranderde voorraad is via #17 tot potentiële sites geclusterd (`Onv_`-site-ids).
