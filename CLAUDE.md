# Redevelopment — GeoDMS-configuratie densification-paper

GeoDMS-configuratie voor het paper **Claassens, Koomen & Rouwendal (2026), "The economic rationale of residential densification"** (Brueckner–Wheaton-raamwerk, two-stage logit: conditional logit over ontwikkeltypes + binomiale logit over herontwikkeling; sites in buurten met OAD ≥ 1000, 2012–2026).

**Lees bij sessiestart eerst `STATUS.md`** — daar staat de actuele stand, openstaande punten en volgende stappen van de lopende sessie-overdracht.

## Papers en terminologie

Nummering volgens de volledige reeks van Jip Claassens (vaste co-auteurs: Eric Koomen en Jan Rouwendal). Zeg bij twijfel de naam, niet het nummer: de repo draagt paper 3 en 4.

1. Claassens, Koomen & Rouwendal (2020), *Urban density and spatial planning: the unforeseen impacts of Dutch devolution*. PLOS ONE. Eigen repo: github.com/jipclaassens/Verdichting.
2. Claassens, Rouwendal, Koomen & Lankhuizen (2026), *Impacts of new light rail investment on accessibility and housing markets: a difference-in-differences hedonic analysis in Amsterdam*. Urban Studies. Eigen repo.
3. **Cities-paper** (intern ook "Redevelopmentpaper"): Claassens, Koomen & Rouwendal (2026), *Uncovering Dutch Residential Development Processes*, ingediend bij Cities. Branch `RedevPaper`, lokaal `C:\ProjDir\RedevelopmentPaper`, OneDrive `VU/Projects/202008-RedevelopmentPaper`.
4. **EconLogic-paper**, het paper van deze branch: Claassens, Koomen & Rouwendal (2026), *The economic rationale of residential densification*. Branch `main`, lokaal `C:\ProjDir\EconLogicPaper`, OneDrive `VU/Projects/202604-RedevEconLogicaPaper`.

"Redevelopment" is meerduidig: de reponaam (beide papers), de interne naam van het Cities-paper, en de oude lokale map van deze repo (`C:\ProjDir\Redevelopment`, sessies tot augustus 2026). De LocalData-map volgt de naam van de repomap (GeoDMS `%LocalDataProjDir%`): op OVSRV06 is dat `C:\LocalData\EconLogicPaper` voor dit paper en `C:\LocalData\redevelopmentpaper` voor het Cities-paper.

## Structuur

- `analysis/Redevelopment.dms` — configuratie-root (Parameters, includes).
- `analysis/Redevelopment/Analyse/redev_obv_hele_bag.dms` — kern: BAG-mutatietypering (PrepBAG, CBS-regels), FinalDomains per Redev_ObjectType, en **`PerObject_Export`** (dé object-level export naar R, 1 rij per VBO incl. onveranderde voorraad; schrijft mmd naar `%LocalDataProjDir%/Temp/`).
- `analysis/Redevelopment/Analyse/PriceComponents.dms` (+ subdir) — hedonische prijscomponenten: `ExportCoefficients_WP4` (coef-CSV voor R), `RegionalAvgCharacteristics` (NVM-regiotifs per WP4×kenmerk op rdc_25m), PrijsIndex (leest Estimates-CSV's per WP4), plus legacy Verwervingskosten/Grondproductiekosten (deels achterhaald, zie STATUS.md).
- `analysis/Redevelopment/SourceData/` — BAG, RegioIndelingen (CBS gebiedsindelingen per jaar), NVM, kwb-xlsx; `woz.dms` is dormant (include uitgecommentarieerd).
- `analysis/Redevelopment/Classifications/bag.dms` — WP4 (vrijstaand, twee_onder_1_kap, rijtjeswoning, appartement), HouseCharacteristics(_src), WP4xHouseChar.
- `R/`: R-pipeline 00 t/m 10 (`Rscript R/run_all.R`, zie `R/README.md`). Leest en schrijft in `%LocalDataDir%/<naam repomap>/{Temp,R_werk}`, dezelfde map als GeoDMS' `%LocalDataProjDir%`.
- `stata/` — schattingscode.

## Werkafspraken

- Prijsberekening gebeurt in **R**, niet in GeoDMS: GeoDMS exporteert ruwe componenten (rauwe euro's/kenmerken, geen winsorizing); R bouwt `prijs = exp(Constant + Σ coef·char)` per WP4. Locatie-/regiotermen zijn grid-gebaseerd (rdc_25m) zodat ze óók voor gesloopte objecten werken.
- GeoDMS GUI: start `GeoDmsGuiQt.exe` met het .dms-bestand als argument; let op dubbele instanties.
- Data staat machine-specifiek onder `%SourceDataDir%` (registry: HKCU\Software\ObjectVision\<machine>); `Redev_DataDir = %SourceDataDir%/RuimteScanner/SD/RSOpen` (ConfigSettings.dms).
- GitHub-issues in deze repo sturen het werk: #13 (export-umbrella), #16 (R-analyse), #17 (clustering Onveranderd), #18 (OV-knooppunten), #19 (UAI 2012), #20 (hedoon-herschatting), #28 (paper-tekst in lijn met de implementatie), #29 (bootstrap-standaardfouten stage 2). De export is af: #13 en #17 t/m #20 zijn gesloten; #16, #28 en #29 lopen nog.
- Wiki: github.com/jipclaassens/Redevelopment/wiki/BAG-mutaties (mutatietypering vs CBS-regels).
