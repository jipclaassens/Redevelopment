# Redevelopment — GeoDMS-configuratie densification-paper

GeoDMS-configuratie voor het paper **Claassens, Koomen & Rouwendal (2026), "The economic rationale of residential densification"** (Brueckner–Wheaton-raamwerk, two-stage logit: conditional logit over ontwikkeltypes + binomiale logit over herontwikkeling; 22 agglomeraties, 2012–2026).

**Lees bij sessiestart eerst `STATUS.md`** — daar staat de actuele stand, openstaande punten en volgende stappen van de lopende sessie-overdracht.

## Structuur

- `analysis/Redevelopment.dms` — configuratie-root (Parameters, includes).
- `analysis/Redevelopment/Analyse/redev_obv_hele_bag.dms` — kern: BAG-mutatietypering (PrepBAG, CBS-regels), FinalDomains per Redev_ObjectType, en **`PerObject_Export`** (dé object-level export naar R, 1 rij per VBO incl. onveranderde voorraad; schrijft mmd naar `%LocalDataProjDir%/Temp/`).
- `analysis/Redevelopment/Analyse/PriceComponents.dms` (+ subdir) — hedonische prijscomponenten: `ExportCoefficients_WP4` (coef-CSV voor R), `RegionalAvgCharacteristics` (NVM-regiotifs per WP4×kenmerk op rdc_25m), PrijsIndex (leest Estimates-CSV's per WP4), plus legacy Verwervingskosten/Grondproductiekosten (deels achterhaald, zie STATUS.md).
- `analysis/Redevelopment/SourceData/` — BAG, RegioIndelingen (CBS gebiedsindelingen per jaar), NVM, kwb-xlsx; `woz.dms` is dormant (include uitgecommentarieerd).
- `analysis/Redevelopment/Classifications/bag.dms` — WP4 (vrijstaand, twee_onder_1_kap, rijtjeswoning, appartement), HouseCharacteristics(_src), WP4xHouseChar.
- `stata/` — schattingscode.

## Werkafspraken

- Prijsberekening gebeurt in **R**, niet in GeoDMS: GeoDMS exporteert ruwe componenten (rauwe euro's/kenmerken, geen winsorizing); R bouwt `prijs = exp(Constant + Σ coef·char)` per WP4. Locatie-/regiotermen zijn grid-gebaseerd (rdc_25m) zodat ze óók voor gesloopte objecten werken.
- GeoDMS GUI: start `GeoDmsGuiQt.exe` met het .dms-bestand als argument; let op dubbele instanties.
- Data staat machine-specifiek onder `%SourceDataDir%` (registry: HKCU\Software\ObjectVision\<machine>); `Redev_DataDir = %SourceDataDir%/RuimteScanner/SD/RSOpen` (ConfigSettings.dms).
- GitHub-issues in deze repo sturen het werk: #13 (export-umbrella), #16 (R-analyse), #17 (clustering Onveranderd), #18 (OV-knooppunten), #19 (UAI 2012), #20 (hedoon-herschatting). Export pas definitief na #18–20.
- Wiki: github.com/jipclaassens/Redevelopment/wiki/BAG-mutaties (mutatietypering vs CBS-regels).
