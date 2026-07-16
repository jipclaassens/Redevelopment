# STATUS — sessie-overdracht densification-paper

*Laatst bijgewerkt: 2026-07-13. Bij nieuwe sessie: dit bestand + open GitHub-issues lezen, dan verder.*

## Context

Paper: **"The economic rationale of residential densification"** (Claassens, Koomen & Rouwendal, 2026). Docx op OneDrive: `VU/Projects/202604-RedevEconLogicaPaper/`. Twee beslissingen gemodelleerd: (1) type-keuze via conditional logit over k-means-clusters van gerealiseerde projecten (residual value per optie als verklarende variabele), (2) herontwikkelingsbeslissing via binomiale logit (inclusive value − verwervingskosten + fricties). GeoDMS levert object-level export (`PerObject_Export`, 1 rij per VBO incl. Onveranderd, mmd in `%LocalDataProjDir%/Temp/`); R doet aggregatie naar sites (op `site_id`), k-means, prijsreconstructie `exp(Constant + Σ coef·char)` per WP4, censoring, estimatie.

## Stand van zaken (2026-07-13) — CBS-levensloopdoc vergeleken, typering CBS-86098-conform gemaakt

BZK-pdf `analysis/data/levensloop-afleiding-technische-beschrijving.pdf` (CBS levensloop, StatLine 86098, vervangt 81955 per juni 2025) naast onze mutatietypering gelegd. Issues **#21–#25** aangemaakt (allen assigned aan Jip) en #21–#24 gefixt in de working tree (**uncommitted**; #25 = alleen documentatie van bewuste afwijking in `bag.dms`):

- **#21 — 100-dagenregel sloop**: `IDEN_S`/`IDEN_S_NW` typeren nu ook op pandsloopstatus die binnen 100 dagen ná VBO-intrekking geregistreerd wordt (`Pand_HeeftOfKrijgtSloopstatus100d`, dag-index-benadering jaar×365+maand×30+dag); logische-overgang-eis vervallen conform 86098; `IDEN_O` + restbakjes spiegelbeeldig.
- **#22 — DirectInVoorraad-splitsing**: blinde `Cplus→T`/`Cmin→O`-mapping in `Read_FinalMutationTable` verwijderd. Nieuw: `IDEN_N_3` = CBS `DirectInVoorraad_Nieuwbouw` (pand nieuw in BAG zelfde maand via echte pandhistorie `uq_pand_hist`, pand direct in voorraad, bouwjaar ≥ jaar−1), `IDEN_T_1b` = CBS `Toevoeging_DirectInVoorraad` (bestaand pand). `FinalDomains` op zuivere `T`/`O`-domeinen. `IsMutated` telt C±-rijen niet meer (`ZonderCorrecties`-subunit in Write- én Read-tabel) → VBO's met alléén administratieve correcties vallen nu in Onveranderd i.p.v. als nep-event of nergens.
- **#23 — Eenmaligheid N/T**: `IsEersteKeerInVoorraad` (eerste voorraad-begindatum per VBO) als extra eis op `IDEN_N` en `IDEN_T`; vangt herkoppeling bestaande VBO aan nieuw pand en re-entries (die worden C+, conform CBS 'voorraad mutatie anders').
- **#24 — Bouwjaargrens N_3**: bovengrens (≤ jaar+1) geschrapt; CBS-doc bevestigt alleen ondergrens (de oude 'OF-tautologie'-comment is daarmee beantwoord).

Gevalideerd: volledige config parseert (GeoDmsRun 20.8.0.m); operator-constructies apart getest op dummy-config.

### Oud-vs-nieuw vergelijking GEDAAN (nacht 13/14-07, AMS, BAG 20260710)

Beide versies volledig doorgerekend via nieuw exportitem `ExportMutatieVergelijking/Rijen` (CSV per mutatierij; PrepBAG-sibling, include in redev_obv_hele_bag.dms — permanent handig). Old run via selectieve `git stash` van de 3 fix-bestanden; runs ~1-3 min/stuk (BAG-join zat in CalcCache). Rapport-artifact: https://claude.ai/code/artifact/424ea1b0-5d6c-4519-8ac3-8bd81d0346d2 ; CSV's+vergelijkingsscript in sessie-scratchpad; `MutatieRijen_AMS_20260710.csv` (nieuwe typering) in `%LocalDataProjDir%/Temp/`.

Resultaat (153,9k mutaties; 2.929 = 1,9% verandert van type; saldo +79.322→+79.305 ≈ gelijk ✓):
- **C+→T 2.606** (Toevoeging_DirectInVoorraad nu aan bron, #22); C+ blijft 1.774 = admin, uit export. Export-Toevoeging netto −1.591 (31.875→30.284), export-Onttrekking −1.140 (13.941→12.801).
- **Eenmaligheid (#23)**: 202 N→C+, 49 T→C+, 16 T→Rest; geconcentreerd 2019/2023/2024 (−121 N in 2024).
- **100-dagenregel (#21)**: klein in AMS: 2 O→S, 20 C−→S, 30 UnID_NWm→S_nw (sloop +52). AMS registreert strak; **NL kan wezenlijk groter zijn → NL-run vóór definitieve export**.
- Regressiecheck: TM±, O_rest, UnID_T± exact stabiel ✓.
- **Extra fix tijdens run**: `IDEN_T_1b` kreeg zorg-/studentencomplex-exclusies (zelfde als IDEN_Cplus) — anders werden 186 bulkregistraties T.

### Wiki + documentenanalyse (14-07)

- **Wiki BAG-mutaties volledig herschreven** (algemene methodedocumentatie, 15 secties, documententabel als rode draad; commit 236235a op de wiki-repo). Alle 5 CBS-pdf's uit `analysis/data/` gelezen en verwerkt.
- **Issue #26** aangemaakt: 2012/13-dubbeltellingencorrectie CBS (Hoogland-notitie: −56% N, −14% S via Woningregister) is niet reproduceerbaar; opties = flag-proxy (oud bouwjaar) + estimatie-exclusie 2012 als sensitiviteit.
- **URL-referenties in PrepBAG.dms** toegevoegd (IDEN_S → 86098-pdf, stacaravanflag → IenM-brief, Per1Jan → transformatierapport 2018 incl. notitie dat BRP/WOZ-regels 6/7/10/11 CBS-microdata vereisen). Parse-check OK.
- Dekking documenten: 81955-doc volledig geïmplementeerd; 86098 = #21–#24 (+#25 gedocumenteerd); transformaties-2018 = BAG-deel wel, BRP/WOZ-deel onmogelijk; correctiemethode-2012 = niet reproduceerbaar (#26); methodebreuk-2016 = context (n.v.t. op 2012+).

### Resterende checklist vóór commit

1. Steekproef in GUI (lijst klaar: `%LocalDataProjDir%/Temp/Steekproef_Typeringsverschuivingen_AMS_20260710.csv`): 20 C−→S, 2 O→S, sample C+→T, en de 202 N→C+ (= herkoppelings-/Delft-type kandidaten). Per geval: `PrepBAG/BAG_Tabel` filteren op vbo_bag_nr (hele keten met statussen + IDEN-vlaggen) en `ExportMutatieVergelijking/Rijen` voor de typering.
2. **NL-run** (`StudyArea='Nederland'`) — samen doen (user). Onderbouwing hard: CBS-verschillenanalyse toont landelijk O→S 2015–2019 (niet-woon 2016: ±14 dzd logies-VBO's). Diagnose bij run: overlap 100-dagenregel × logies-/studentenfilters (S_nw vs S_rest — filters winnen by design, check of dat de bedoeling blijft).
3. **Beide mmd's regenereren** — doet Jip zelf.
4. ~~Verschillenanalyse opvragen~~ — binnen en verwerkt (wiki §13).
5. ~~Committen~~ — gedaan (14-07): typering-fixes #21–#24, exportitem, URL-refs, hernoemde/nieuwe CBS-pdf's, verslagmaanden t/m 2026-06, bouwjaar-cast; oude Afleiden_woonvoorraad.pdf verwijderd. **Push nog niet gedaan.**
6. #26: besluit = optie 2 (flag). Geen config-wijziging nodig: flag in R afleidbaar uit bestaande exportkolommen (`redev_type == Nieuwbouw && redev_yearmonth in 2012xx && obj_building_year <= 2010`); daar in estimatie op filteren/dummy (= optie 3 als robuustheid). ~~Upgrade-pad koppeltabel~~ — geïnspecteerd (14-07): xls is een landelijk aggregaat (kruistabel WR-typering × BAG-functie × BAG-status per 1-1-2012, geen microdata) → bouwjaar-proxy in R blijft de aanpak. Bijvangst: ±29,4 dzd WR-woningen stonden per 1-1-2012 als 'gevormd' in de BAG (het reservoir van de 2012-dubbeltellingen) — plausibiliteitscheck voor de proxy-omvang.
7. ~~Oude 81955-pdf~~ — verwijderd bij commit.
8. ~~Stikstof-fork~~ — door Jip al gecommit.

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
3. **#18–20 GEREED aan de schattingskant (2026-07-13)**: de R-pipeline in `C:\ProjDir\_Tools\PriceIndices` heeft de volledige keten doorlopen (nieuwe merge/clean → geocodering 20250115-BAG → spatial pass met `uai_2012_network` en `tt_OVknooppunten_2026`). **`Output/Estimates_20260711_redev[_limit]_<type>.csv`** staan klaar: #18 `lntt_ovknoop` i.p.v. station-2006, #19 `uai_2012`, #20 zonder groen, plus `d_hoogte_onbekend`-dummy (app). Format: `term;estimate;std_error;...` met directe GeoDMS-itemnamen (`bouwperiode_1926_1950`, `trans_year_2012`, `constant`). **Hier nog te doen**: (a) PrijsIndex.dms/ExportCoefficients_WP4 omzetten naar het nieuwe format+bestandsnamen (naam-mapping wordt 1-op-1; Y2024/25-gat vervalt); (b) `loc_tt_station2006_min`-placeholder in PerObject_Export vervangen door de OV-knooppunt-variabele (zelfde bron als in PriceIndices/main/Diversen); (c) UAI_2012-grid idem; (d) RegionalAvgCharacteristics herbouwen op de 20260711-set (tifs `NVM_Regiokarakteristieken_20260711/`, RegionalAverages in PriceIndices/main).
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

## WP4-pandtypering: van live Per1Jan-buuranalyse naar SD-lookup + terugzoeken (2026-07-16)

**Aanleiding.** `MaakOntkoppeldeData/Write_FinalMutationTable` liet de GUI "crashen". Bleek geen
crash maar een Windows resource-exhaustion-kill (System-event 2004): het proces groeide tot
**595,8 GiB commit**. Driver: `PandTypering_Mutaties/pand_type` (PrepBAG.dms) deed
`merge(TyperingsJaar_idx, WP4, perJaar/Y2012..Y2026)`, en `merge` houdt **alle ~15 jaartakken
tegelijk levend**. Elke tak trok een volledige live `Per1Jan/<jaar>/select` +
`AfleidingPandtype`-buuranalyse over ~10M panden. (Engine-kant: EmptyWorkingSet-storm apart
gefixt in GeoDMS commit 3d55f4ad; silent OOM = GeoDMS-issue #1158. GeoDMS-crashonderzoek staat
los van dit repo.)

**Twee bronnen voor dezelfde WP4-typering vergeleken** (Y2026, NL, headless, meetscaffold
`Analyse/redev_obv_hele_bag/VergelijkWP4.dms` — permanent handig, hoort niet in productie):

| | Analyse-tak `Per1Jan/<jaar>/select/uq_pand_nr` | SourceData-tak `PerJaar/<jaar>/pand` |
|---|---|---|
| grondslag | `BAG_Tabel` (vbo×pand×periode), `unique(pand_bag_nr)` | `VolledigeBAG/panden/pand` |
| statusfilter | **geen** | **`pand/IsVoorraad`** (CBS-voorraaddef) |
| WP5 | **live berekend** | **uit mmd-cache gelezen** (`WP5/<Selection_string>_<jaar>_<area>.mmd`) |
| omvang | 6,77M panden | 11,16M panden |

Gedeelde panden: **93,85% identiek WP4**, 0,83% ander type. Die 0,83% (56.220) is geen ruis maar
**buur-besmetting**: de Analyse-tak laat gesloopte/niet-voorraad panden meedoen als buur, dus een
rijtjeswoning naast een gesloopt gat wordt vrijstaand. De SD-tak typeert op een schone
voorraad-only burenset. **SD is dus correcter, niet alleen goedkoper.**

**Dekking op de échte mutatierijen** (2.325.426; `MutatieDekking`-scaffold, geen pandtypering
nodig): 8,14% van de rijen vindt zijn pand niet in de SD-set van zijn typeringsjaar. Uitgesplitst
(`Per_Type`): **min-mutaties 20,2%, plus 4,2%**; binnen min is **sloop (S/S_nw) 43,6%**,
onttrekking 0,5%. Het gat zit dus vrijwel volledig in sloop — logisch: bij sloop staat het pand
dat jaar niet meer in de voorraad. De gemiste panden zijn **100% wonen**; naar status:
Pand_gesloopt 56%, ten_onrechte_opgevoerd 15%, sloopvergunning_verleend 15%,
niet_gerealiseerd 14%, in-aanbouw 0,3%.

**Drie mechanismen, op cijfers onderbouwd:**
1. **SD-lookup (basis, ~36% van het gat + alle voorraad).** Eén mmd-lookup per jaar i.p.v. live
   buuranalyse → lost de 595 GiB op én de buur-besmetting.
2. **Terugzoeken / backward-fill (~55%, de sloopgroep).** Rij zonder typering in zijn jaar krijgt
   de typering van het laatste eerdere jaar waarin het pand wél voorraad was — zelfde gebouw,
   schone buren. Correcties (Cmin/Cplus, nooit bestaan → ~8%) vinden ook achteruit niets en
   blijven terecht null.
3. **Filedatum-snapshot (de nieuwbouw-staart).** 2026-nieuwbouw wordt door `TyperingsJaar` naar
   1-1-2026 geklemd terwijl het pand er dan nog niet staat; terugzoeken helpt daar niet.
   Gemeten op de gemiste rijen: een filedatum-selectie met de **gewone voorraaddefinitie** vangt
   80% van de gemiste nieuwbouw (54k). VBO-status `verblijfsobject_gevormd` (IsInPlanvorming)
   voegt +1.993 toe en **subsumeert** de pandstatus-projectie `bouw_gestart`/`bouwvergunning_verleend`
   (die zakte van 1.329+642 → 70+64) — dus als er iets bij moet is het `gevormd`, niet de
   pandstatus-projectie. **Let op valkuil:** `gevormd`-panden komen zo wél in de selectie maar
   krijgen geen WP4 tenzij ook `functioneel_pand`/`count_vbos` (bag.dms) meetelt met gevormd-VBO's
   — anders count_vbos=0 → buiten buuranalyse → alsnog null. Filedatum-snapshot gebouwd met de
   **plain voorraaddefinitie** (geen gevormd, geen projectie): gemeten meerwaarde daarvan was
   +1.993 resp. +134 rijen op 2,3M, tegen extra aannames en een ingreep in de gedeelde SD-typering.

**Gebouwd en geverifieerd (2026-07-16, alle drie de mechanismen):**
- `PrepBAG.dms` `PandTypering_Mutaties`: `perJaar` omgeleid naar
  `/SourceData/Vastgoed/BAG/PerJaar/<jaar>/pand/WP4_rel[rlookup(MutTable/pand_bag_nr, .../pand/pand_bag_nr)]`;
  `perJaar_gevuld` = cumulatieve backward-fill (`MakeDefined(perJaar/<jaar>, gevuld/<vorig jaar>)`,
  eerste jaar = eigen jaar); `pand_type_op_filedatum` = zelfde lookup in `OpFileDatum/pand`;
  `pand_type = MakeDefined(merge(TyperingsJaar_idx, WP4, perJaar_gevuld/...), pand_type_op_filedatum)`.
  Diagnostiek ernaast: `pand_type_zonder_terugzoeken` (merge op kale `perJaar`).
- `SourceData/bag.dms`: `PerJaar_T` gegeneraliseerd met `PeilDatum` — JaarStr 'JJJJ' → 1 jan van dat
  jaar, 'JJJJMMDD' → die datum zelf; berekening in **int64** (beide ternary-takken worden geëvalueerd
  en JJJJMMDD×10000 overloopt int32). Nieuwe instantie `OpFileDatum := PerJaar_T(Parameters/BAG_file_date)`;
  de 15 jaar-instanties gedragen zich identiek. Cache krijgt vanzelf een eigen naam:
  `WP5/Voorraad_20260710_<area>.mmd` (11.240.179 panden op 10-7 vs 11.158.260 op 1-1 = +82k ✓).
- WP5-caches: 2012-2025 gegenereerd (Jip, per jaar ~2 min / piek ~33 GB), 2026 + filedatum (Claude).
  **Cache-map staat onder cloud-sync; de 2026-cache viel tijdens de sessie twee keer terug naar een
  oude stale versie → cryptische "CreateFileMapping ... Access is denied" (mmd zonder Range, GeoDMS
  #1154). Sync uit tijdens rekenen, of de WP5-map excluden.**

**Eindmeting (NL, BAG 20260710, 2.325.426 mutatierijen; `WP4_Eindresultaat`-scaffold):**
| variant | GEEN_TYPE | met WP4 |
|---|---|---|
| kale SD-lookup | 623.115 (26,80%) | 73,20% |
| + terugzoeken | 544.781 (23,43%) | 76,57% — redde 78.334 (sloopgroep) |
| + filedatum-vangnet | **459.839 (19,77%)** | **80,23%** — redde nog eens 84.942 |

**Pijplijn-test** (plus-mutaties geklemd op laatste jaar = nieuwbouw lopend jaar): **132.939 van
164.877 = 80,6% krijgt een WP4**, conform de vooraf gemeten 80%. De rest is overwegend terecht
null: niet-wonen nieuwbouw (hoort geen woonpandtype) en panden die op de filedatum nog niet
gebouwd zijn. Resterende GEEN_TYPE (19,77%) = niet-woonpanden + nooit-bestaande correcties +
nog-niet-gebouwd.

**Geheugen/looptijd**: volledige `pand_type` nu **~27 GB piek / ~2 min** (was 595,8 GiB → OS-kill,
factor ~22). NB: de mmd van `Write_FinalMutationTable` krijgt de `pand_type`-kolom pas bij een
verse volledige run van dat write-item.

## Paper — openstaande punten

- Results/conclusie leeg (wacht op R); Figuur 2 (study area) placeholder; cost-data-sectie onaf; `[SOURCE]` bij PBL/Fakton; bouwjaar-buckets "NEEDS A REF"; Table 3 descriptives stamt uit eerdere versie.
- **Inconsistenties met data-besluiten** (paper belooft gedropte variabelen): (1) "number of distinct owners on a site" als holdout-frictie → gedropt, herschrijven (alleen % owner-occupiers buurt blijft); (2) vogelaar/"designated deprived neighbourhood" als covariaat en in Table 3 → gedropt; (3) hedonic-beschrijving noemt "green areas within 100m" en "travel time to nearest railway station" → wijzigen bij #20/#18.

## Los van dit repo

- GeoDMS-engine-issue #1144 (ItemReadLock-assert bij Write_FinalMutationTable): engine-fix gebouwd en geverifieerd in `C:\Dev\GeoDMS_2026` (machine-specifiek, uncommitted op main). Openstaand daar: E = model-metainfo-fout in `PrepBAG/AfleidingPandtype` ("Unknown identifier 'F1'" bij `rectangles/R0_C0/neighbours/coded_pair`).
