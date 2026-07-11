# STATUS — sessie-overdracht densification-paper

*Laatst bijgewerkt: 2026-07-07. Bij nieuwe sessie: dit bestand + open GitHub-issues lezen, dan verder.*

## Context

Paper: **"The economic rationale of residential densification"** (Claassens, Koomen & Rouwendal, 2026). Docx op OneDrive: `VU/Projects/202604-RedevEconLogicaPaper/`. Twee beslissingen gemodelleerd: (1) type-keuze via conditional logit over k-means-clusters van gerealiseerde projecten (residual value per optie als verklarende variabele), (2) herontwikkelingsbeslissing via binomiale logit (inclusive value − verwervingskosten + fricties). GeoDMS levert object-level export (`PerObject_Export`, 1 rij per VBO incl. Onveranderd, mmd in `%LocalDataProjDir%/Temp/`); R doet aggregatie naar sites (op `site_id`), k-means, prijsreconstructie `exp(Constant + Σ coef·char)` per WP4, censoring, estimatie.

## Stand van zaken (2026-07-07)

### Net gedaan (gecommit; GUI-check nog uitvoeren)

- **`PerObject_Export`**: 4 merge-kolommen (`reg_lotsize` e.d., alleen eigen WP4) vervangen door **16 expliciete kolommen `reg_<wp4>_<char>`** (4 WP4 × lotsize/nrooms/d_maintgood/d_highrise) — nodig omdat R voor fase 2 (alternatieven-waardering) regiogemiddelden van **alle** WP4-types nodig heeft, niet alleen het incumbent-type. Fase 1 (incumbent) pakt in R de eigen kolom via `obj_housetype`.
- **`ExportCoefficients_WP4`** (PriceComponents.dms): `[float64]`-cast toegevoegd — `estimate` komt als String uit de Estimates-CSV (gdal.vect zonder .csvt). Zelfde patroon als `PrijsIndex/Result`. Vermoedelijk de oorzaak van het rode item.
- **`Sloopkosten`** (PriceComponents.dms): stale ROV-namen gefixt (`Classifications/Vastgoed`→`BAG`, `ModelParameters`→`/Parameters`, `/ModelParameters/Wonen/Sloopkosten`→`/Parameters/Sloopkosten`, `Kantoor`→`kantoor`). Mogelijk resteert een unit/metric-mismatch (`m2 × verblijfsobject × Eur_m2 → eur`) — in GUI checken.

### GUI-checklist (eerstvolgende actie)

1. `/Analyse/PriceComponents/ExportCoefficients_WP4` groen? → CSV-StorageName aanzetten (uitgecommentarieerde regel onderin de unit) en coef-CSV genereren voor R.
2. Nieuwe `reg_*`-kolommen: **mmd regenereren** (PerObject_Export opnieuw laten schrijven; huidige mmd van 20260108/AMS heeft ze niet).
3. Check of Estimates-CSV's (`Estimates_20251024_*.csv`) rijen `2024.trans_year` bevatten: de naam-mapping in `PrijsIndex.dms` stopt bij Y2023 → die rijen vallen nu **stil** weg (raakt prijspeil-dummies in R). Bij #20 meteen Y2024/25 toevoegen aan mapping én aan `Classifications/BAG/HouseCharacteristics_src`.

### Resterende rode items in /Analyse/PriceComponents — legacy, bewust niet gefixt

Achterhaald door de componenten→R-aanpak; uitcommentariëren of laten staan:

- `Verwervingskosten.dms:69-70` — `pand_startjaar` nergens gedefinieerd (doodt Niet_Woningen + Totaal).
- `Verwervingskosten.dms:68` — `SourceData/Vastgoed/WOZ/...`: woz.dms-include staat uit én pad/structuur kloppen niet.
- `Verwervingskosten.dms:81` — `Parameters/BaseDataOntkoppeld` bestaat niet.
- `Grondproductiekosten.dms:61-69` — `Classified/...`-container ontbreekt; `Grondproductiekosten/T.dms:85` — `SourceData/Diversen` bestaat niet.

## Volgende stappen (volgorde)

1. **GUI-verificatie** (checklist hierboven) → dan de twee gewijzigde .dms-files committen.
2. **WOZ-pipeline niet-woningen bouwen** (laatste GeoDMS-gat in #13 fase 1) — voorstel hieronder, wacht op go.
3. **#18–20** (OV-knooppuntvariabele, UAI 2012, hedoon-herschatting zonder groen): wordt opgepakt in een **andere config** (NVM-schattingskant). Daarna hier: coef-CSV regenereren, `loc_tt_station2006_min`-placeholder vervangen, naam-mapping bijwerken.
4. **R-kant opzetten** (#16): mmd/CSV inlezen, site-aggregatie, k-means (#13 fase 2: cluster-kenmerken → alternatieven), estimatie.
5. **Paper bijwerken** (kan parallel): zie inconsistenties hieronder.
6. Mutatietypering documenteren als md voor de wiki; sensitiviteit 2e-instantie C+-trigger (telt eerdere C+ mee bij CBS?) nog waard om te draaien.

## WOZ-voorstel niet-woningen (stap 2, wacht op go)

Doel: `loc_woz_nonres_eur_m2` in PerObject_Export; verwervingskosten niet-woon in R = €/m² × `obj_floor_area_res_m2` (voor `obj_is_woonfunctie == FALSE`).

Geen actieve WOZ-bron in de config. Twee bronnen op schijf:

- **A (aanbevolen): `190215_{buurt,wijk,gem}_woz.csv`** (PBL, peiljaar 2017; in `%Alt_DataDir%/Overig` én `%Redev_DataDir%/Vastgoed/WOZ/`): `wozm2_mean` per regio × bodemgebruik-groep (woongebied/voorzieningen/bedrijfsterreinen/overigen). Gemeente-file aanwezig → volledige fallback buurt→wijk→gemeente.
- **B: `WOZ_per_m2_2015_{Buurten,Wijken}.csv`**: expliciete NIETWON-€/m²-kolommen (2012+2015), functie-zuiver, maar geen gemeente-file en veel lege buurten. Gebruiken als sanity-check in R.

Implementatie A: dormante `SourceData/woz.dms` herschrijven — include aanzetten (SourceData.dms:20), StorageName herwijzen (files staan NIET in `%Redev_DataDir%/Overig`), stale refs vervangen (`/Analyse/RegioUnit_*` bestaat niet meer → `impl/CBS/Y2017`-domeinen, CSV-codes zijn 2017-vintage; `BAG/Snapshots` bestaat niet meer), en **mean + sd → plain mean** (huidige code telt 1 sd op). Grid-route aanhouden (per groep een rdc-grid met MakeDefined-fallback-keten — staat al in woz.dms — object prikt via `per_rdc_25m`, groep via BBG-klasse van de cel): werkt ook op gesloopte objecten en omzeilt de vintage-mismatch (Buurt_rel in export = Y2012-domein). Kanttekening: groep = bodemgebruik van de locatie, niet functie van het object.

## Export-architectuur en genomen besluiten (samenvatting)

- Kolommen aanwezig: identifiers (site_id, vbo/pand_bag_nr, docnums, x/y), outcomes (was_redeveloped, redev_type [10 Redev_ObjectTypes; mapping naar none/SN_W_W/SN_MX_W/transformatie doet R], redev_yearmonth), incumbent (site_size, site_sum_footprint, obj_building_year, obj_floor_area_res_m2, obj_housetype [WP4], obj_is_woonfunctie), prijscomponenten (loc_tt_500k_min, loc_tt_station2006_min [placeholder #18], 16× reg_*, UAI_2012 [#19]), regio (gemeente/wijk/buurt_code, agglomeratie), buurt/wijk (p_owner_occupier_buurt, p_socialhousing_buurt, wijk_p_woningcorporatie, OAD, UrbanisationK), planning (IsProtectHeritageArea, is_natura2000).
- **Gedropt** (besluiten juni 2026): `pand_hoogte` (AHN-snapshot tijd-inconsistent), `vogelaar` (programma ~2012 afgelopen), `n_owners_site` (BRK in config heeft alleen perceelgeometrie; herverkaveling na herontwikkeling maakt snapshot-timing fataal). `local_price_vol` = R-side uit NVM.
- Mutatietypering (PrepBAG) gecontroleerd tegen CBS-doc "Afleiden van de woonvoorraad" + mailwissel Straetemans/vd Wal; vier fixes en dedup gecommit (0489602, 7d1d4d3). Verschil met Statline = CBS' niet-openbare correctiebronnen, gedocumenteerd op de wiki.

## Paper — openstaande punten

- Results/conclusie leeg (wacht op R); Figuur 2 (study area) placeholder; cost-data-sectie onaf; `[SOURCE]` bij PBL/Fakton; bouwjaar-buckets "NEEDS A REF"; Table 3 descriptives stamt uit eerdere versie.
- **Inconsistenties met data-besluiten** (paper belooft gedropte variabelen): (1) "number of distinct owners on a site" als holdout-frictie → gedropt, herschrijven (alleen % owner-occupiers buurt blijft); (2) vogelaar/"designated deprived neighbourhood" als covariaat en in Table 3 → gedropt; (3) hedonic-beschrijving noemt "green areas within 100m" en "travel time to nearest railway station" → wijzigen bij #20/#18.

## Los van dit repo

- GeoDMS-engine-issue #1144 (ItemReadLock-assert bij Write_FinalMutationTable): engine-fix gebouwd en geverifieerd in `C:\Dev\GeoDMS_2026` (machine-specifiek, uncommitted op main). Openstaand daar: E = model-metainfo-fout in `PrepBAG/AfleidingPandtype` ("Unknown identifier 'F1'" bij `rectangles/R0_C0/neighbours/coded_pair`).
