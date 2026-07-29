# STATUS — sessie-overdracht densification-paper

*Laatst bijgewerkt: 2026-07-27. Bij nieuwe sessie: dit bestand + open GitHub-issues lezen, dan verder.*

## Context

Paper: **"The economic rationale of residential densification"** (Claassens, Koomen & Rouwendal, 2026). Docx op OneDrive: `VU/Projects/202604-RedevEconLogicaPaper/`. Twee beslissingen gemodelleerd: (1) type-keuze via conditional logit over k-means-clusters van gerealiseerde projecten (residual value per optie als verklarende variabele), (2) herontwikkelingsbeslissing via binomiale logit (inclusive value − verwervingskosten + fricties). GeoDMS levert object-level export (`PerObject_Export`, 1 rij per VBO incl. Onveranderd, mmd in `%LocalDataProjDir%/Temp/`); R doet aggregatie naar sites (op `site_id`), k-means, prijsreconstructie `exp(Constant + Σ coef·char)` per WP4, censoring, estimatie.

## Stand van zaken (2026-07-16 avond) — EXPORT DEFINITIEF + R-PIPELINE DRAAIT END-TO-END

**De keten GeoDMS → R werkt volledig**: verse `PerObject_Export_Nederland_20260710.mmd` (8.700.061 rijen, 54 kolommen, alle prijscomponenten definitief) → R-pipeline (`R/`) → sites → k-means. Issues #20 en het WOZ-gat van #13 zijn dicht; #16 stap 0–2 staat.

### #20-omhang (coëfficiënten + locatievariabelen), volledig geverifieerd

- `NVM_filedate = 20260711`; PrijsIndex leest het nieuwe R-format (`term;estimate;...`), naam-mapping vervallen; `HouseCharacteristics_src` = 42 termen 1-op-1 met de CSV (referentiecategorieën met coef 0 erin). Spec-keuze: **'redev'** (`Estimates_20260711_<type>.csv` in Vastgoed = identiek aan `_redev_`-bestanden op OneDrive). Transacties lopen t/m 2023 → het "2024/25-gat" bestaat niet meer; 2024–2026-objecten krijgen 2023-prijspeil (R).
- `PriceCoefficients_WP4_20260711.csv` (Temp) door GeoDMS gegenereerd via str-patroon; volle precisie geverifieerd.
- **Schalen byte-exact geverifieerd** (scaffold `VerifieerExportBronnen.dms`, puntprobes op 4 NVM-locaties): `loc_tt_500k_2024_min` (float-min, cap 120), `loc_tt_ovknoop_2026_min` (float-min, ongecapt) en `UAI_2012` identiek aan de schattingsinput. **UAI: tif is 0–1-genormaliseerd; de schatting zag tif×100 als float** — de ×100 zit in SourceData.dms (geen int-conversie). Omgeving-tifs zijn 100m-grids: gelezen op rdc_100m + rel naar 25m; de `min`-unit (uint32!) bewust vermeden.
- **Regiotifs waren integer geschreven** (d_maintgood/d_highrise als uint2 → 0/1, nrooms uint8): PriceIndices-ValueTypes → float32, alle 20 tifs hergenereerd (oude set in `_int_backup`); nu échte fracties (bv. d_maintgood-mean 0,80). `size` per WP4 nieuw in de export (`reg_<wp4>_size`, 4×) tbv fase-2 lnsize.

### WOZ niet-woon (laatste gat #13 fase 1) — gebouwd

`SourceData/woz.dms` herschreven (plan A): PBL 190215-CSV's (peiljaar 2017) uit `Vastgoed/WOZ/`, grid-route 25m, groep via dominante BBG-klasse 2017 per cel, fallback buurt→wijk→gemeente (CBS Y2017-domeinen; Gemeente kreeg `code`), plain mean (geen +sd). Kolom `loc_woz_nonres_eur_m2`; NL-mean ~€1813/m², max ~€10917.

### Verse NL-runs + twee gefixte blokkades

- `FinalMutationTable_Nederland_20260710.mmd`: 2.325.426 rijen mét `pand_type` (~6 min, warme cache).
- `PerObject_Export_Nederland_20260710.mmd`: 8,7M rijen (~48 min). Typeverdeling: Onveranderd 7.086.763; SN_Nieuwbouw 472.196; Nieuwbouw 454.561; Toevoeging 306.577; SN_Sloop 127.504; Onttrekking 106.591; TM+ 50.547; Sloop 40.503; TM− 31.658; SN_Sloop_nw 23.161.
- Fix 1: `Onveranderd/uq/wp4_rel` hing nog aan de live Per1Jan-buuranalyse (kapot door lokale AfleidingPandtype-fout #1144-E, plus buur-besmetting) → **SD-lookup op de OpFileDatum-stand** (zelfde patroon als `pand_type_op_filedatum`).
- Fix 2 (GeoDMS-les): **subunits binnen een unit mét StorageName worden storage-placeholders** (lege file in de mmd; org_rel-parse-fouten op de read-kant). `ZonderCorrecties` (#22) staat nu als `FinalMutationTable_ZonderCorrecties` op PrepBAG-niveau naast de Write/Read-switch.

### R-pipeline (`R/`, stijl PriceIndices) — #16 stap 0–2 GEREED en gedraaid op NL

- `01_read_mmd.R`: generieke mmd-reader. Formaat gedocumenteerd/ontcijferd: per attribuut plat little-endian bestand; strings = indexparen (2×uint64 [begin,eind), tile-lokaal, null=2⁶⁴−1) + `.seq` met header van 3 uint64 per tile **(start, used, alloc)** — segmenten staan in wíllekeurige volgorde (multithreaded writes); tiles = 65536 rijen; bools bit-packed.
- `02`: labels, null-sentinels, 2012-flag (#26: 10.353 rijen gevlagd), prijsreconstructie. **Mediaan €379k (2023-peil); per WP4: vrijstaand €686k > 2^1kap €427k > rijtjes €373k > appartement €330k; dekking 98,9% woon / 98,4% niet-woon (mediaan €177k).** Missend vooral WP4-loos (74k).
- `03`: 7,27M incumbent-sites; 470.335 replacement-sites. `04`: elbow (PRE vlakt af rond K=6–8); K=6 geeft direct interpreteerbare clusters (2^1kap-projecten / vrijstaand-groot / vrijstaand / rijtjes 85·ha⁻¹ / appartement-laagdicht 221k / appartement-hoogdicht 120·ha⁻¹ FAR 0,85). Outputs in `%LocalDataDir%/Redevelopment/R_werk/`.
- R 4.6.1 + data.table/bit64 nu ook op OVSRV08 (user-library).

### Validatie typering (checklist 14-07, punten 1–2) — GEDAAN, alles klopt

Scaffold `ValidatieTypering.dms` (SteekproefKetens + Diagnose100Dagen):
- **Steekproef (2.929 verschuivingen, AMS)**: cat 1 sloopwinst-100d **52/52** ✓ (intrekking + 100d-conditie in keten); cat 2 N-herkoppeling **202/202** ✓ (allemaal eerder in voorraad); cat 3 T-eenmaligheid **65/65** ✓ (54 met eerdere voorraadperiode + 11 correcte eerste-keer-T's binnen de mutatiemaand); cat 4 DirectInVoorraad→T **2590/2595** ✓; 5 borderline-gevallen (bouwjaar=mutatiejaar; pand vermoedelijk al in BAG via andere VBO's — desgewenst GUI-check: `SteekproefKetens_Nederland_20260710.csv`).
- **100-dagen-diagnose NL** (`Diagnose100Dagen_Nederland_20260710.csv`): S 168.215 en S_nw 76.154 voldoen per constructie 100% aan de conditie; **logies-/studentenfilters winnen in slechts 2.346 gevallen (Rest_S_rest, ~1%)** — filters blijven marginale correctie, geen structurele wegvang. "Filters winnen by design" blijft dus verdedigbaar.

### Avondsessie 16-07 (vervolg): #13 dicht, kostenkant + #17 ingebouwd

- **#13 gesloten** (slotcomment met bewuste spec-afwijkingen). **#28 aangemaakt**: alle paper-edits (hedoon-specificatie, NVM t/m 2023, isolatie gedropt, clustervariabelen incl. unitgrootte, n_owners/vogelaar, Table 3, PBL/Fakton-bron).
- **Kostenkant (#16 stap 2)**: grondproductiekosten-grids eenmalig uit RSopen_NL2120 gegenereerd → `Vastgoed/Grondproductiekosten_2023/{Nominaal_High,Low_Low,High_High}.tif` (25m, Eur/ha, 2023-peil = Model_StartYear NL2120, consistent met ons prijspeil). Het tijdelijke export-item is op verzoek weer uit NL2120 teruggedraaid (17-07); het snippet staat als naslag in `analysis/data/ExportRedevKosten_NL2120_snippet.dms.txt`. In de export: `loc_grondprod_eur_ha[_low|_high]` + `landsdeel` (tbv CBS-bouwkosten-kentallen). R/00_config.R heeft de kentallen (bouwkosten 83673NED per landsdeel 2023, sloopkosten ×1,29, vormfactoren PBL).
- **#17 ingebouwd**: `OnveranderdSites.dms` clustert de onveranderde woonvoorraad tot potentiële sites met exact de SN-buffer-machinerie; Onveranderd-objecten krijgen `OnvS_<id>`-site_id (fallback eigen pand); `VergelijkGrootte_Export` schrijft de groottedistributie potentieel-vs-SN voor de validatie/cap-beslissing.
- **Run gestart** (avond): verse PerObject_Export NL met alles erin + VergelijkGrootte-CSV — geos-clustering over ~4M panden, duurt uren. Daarna: R-herrun (03_sites pakt de kostencomponenten al mee), distributie-analyse #17, en dán R stap 2 (alternatieventabel + residual value).

### 18-07: OnveranderdSites DEFINITIEF (v2d) — #17-clustering werkt, gevalideerd

Na drie iteraties (v1 landelijke split-union: >14u single-threaded merge, gekilld; v2b `polygon_rel` bleek TILE-LOKAAL → 99% singletons; v2c deel×deel-self-overlay: memory-fail na 6u) is **v2d** de definitieve route: explode → deel×pand-overlay → eigen-deel via bevat-criterium (≥50% pandoppervlak) → **adjacency rechtstreeks uit de deel×pand-paren** (pand p verbindt met elk pand q dat p's eigen-deel raakt; gap < 10m i.p.v. SN's < 20m — gedocumenteerde parameterkeuze) → union-find → gepartitioneerde site-unions. Alle stappen getiled/parallel; OnveranderdSites-fase ≈ 1,5 uur.

**Resultaat (NL, 18-07):** 5.079.585 voorraadpanden → **893.435 potentiële sites** (gem. 5,7 panden/site). **Distributie vrijwel gelijk aan de gerealiseerde SN-sites**: mediaan 1.407 vs 1.477 m², p25 972/1.000, p75 2.483/2.722; alleen de staart is bij SN dikker (p99 10.292 vs 18.844 m²). Slechts 1,95% van de potentiële sites > SN-p95 en 2 stuks > SN-max — **mega-site-cap lijkt onnodig**. CSV: `OnveranderdSites_grootte_Nederland_20260710.csv`; tellingen: `OnveranderdSites_DiagnoseTellingen.csv`.

Verse `PerObject_Export_Nederland_20260710.mmd` (8,7M rijen, 58 kolommen) met OnvS-site-ids + kostencomponenten; R-pipeline erover gedraaid: 1.074.235 incumbent-sites, 470.335 replacement-sites. **NB prijscorrectie**: de reconstructie-cijfers van 17-07 (mediaan €379k) stonden op een mmd waarvan de reg_*-kolommen uit een stale cache op de oude integer-tifs kwamen; de verse 18-07-mmd heeft echte fracties (reg-check: d_maintgood mean 0,826, ~nooit exact 0/1). **Correcte medianen (2023-peil): vrijstaand €629k > 2^1kap €395k > rijtjes €354k > appartement €306k; totaal €356k** — bronnen opnieuw byte-exact geverifieerd tegen de schattingsinput. GeoDMS-lessen vastgelegd in de configcomments: subunits in storage-units worden placeholders; `polygon_rel` van geos_split_polygon is tile-lokaal; polygon_connectivity is boundary/partitie-georiënteerd en paget op miljoenen overlappende polygonen; deel×deel-self-overlays exploderen in intersectiegeometrieën.

### 27-07: stap 2a–2c gebouwd en gedraaid (05_alternatieven.R) — issue #16 herschreven

Issue #16-body herschreven (stap 2 → 2a/2b/2c, vinkjes eerlijk, vogelaar/eigenaren/hoogte/paperklassen eruit). `R/05_alternatieven.R` nieuw + `03_sites.R` uitgebreid (reg_* naar site_attrs; `sloop_cost_eur` per incumbent-site: kental per WP4/kantoor × vloeroppervlak) + defaults in `00_config.R` (`bouwkosten_kolom='koop_eur_m2'`, `alt_d_maintgood=1`, `vormfactor_wp4`).

**Gedraaid (NL, 18-07-mmd): long-tabel 9.086.010 rijen (1.514.335 sites × K=6), 0,11% RV=NA.** Mediane RV per alternatief €0,34–2,5M; 99,9% RV>0 — verwacht, want verwerving zit pas in stage 2. Bevindingen:
- **Argmax-RV = cluster 6 (appartement-hoogdicht) op 91,4%** van de sites → stage 1 heeft alternative-specific constants nodig; RV-niveaus alleen dragen de keuze niet (match gekozen=argmax: 13%).
- **Van de 470k gerealiseerde sites hebben er maar 30.235 een incumbent** (echte herontwikkeling); de rest is pure nieuwbouw/uitleg die massaal cluster 5 kiest (laagste RV). Herontwikkelingssites kiezen 57% cluster 3-vrijstaand (teardown-patroon). → **Beslispunt: stage-1-sample = herontwikkeling-only vs alles** (zie issue #16).
- **Aandachtspunt**: ruwe surplus-preview (RV_max − verwerving, alleen incumbent-sites) ligt hóger bij Onveranderd (mediaan €1,64M, 95% positief) dan bij herontwikkelde sites (€0,29M, 66%) — tegengesteld aan de theorie; uitzoeken in estimatiefase (universum-afbakening, site_size-vergelijkbaarheid SN (20m-gap) vs Onveranderd (10m), verwervingswaarde niet-woon, censoring).
- Cluster 2-centroïde heeft unitgrootte 636 m² → prijs-predictie extrapoleert buiten de NVM-steun; meenemen bij de K-beslissing.

NB R-omgeving: data.table/bit64 staan in de door de Claude-app gesandboxte user-lib (`AppData\Local\Packages\Claude_...\LocalCache\Local\R\win-library\4.6`) — Rscript vanuit een eigen terminal ziet die niet; dan eenmalig `install.packages(c("data.table","bit64"))` in de echte user-lib.

### 28-07: stage-1-sample = SN; menu opnieuw geclusterd; site-vormingsvragen beantwoord

Vragen Jip (10/20m, Stikstof-docnummer, cleanen gekke FAR's) onderzocht met twee config-verkenningen + probes, en de sample-schakelaar gebouwd (`cfg$stage1_sample = 'sn'|'sn_tr'|'alle'`, bestandssuffix `_sn`):

- **K-means op 41.902 SN-sites** (`clusters_sn_*.rds`): elbow bevestigt K=6 (PRE 0,27→0,12 na K=6). Menu nu interpretabel, singleton-artefacten weg: 1 vrijstaand-teardown 47% (FAR 0,18; 10,7/ha; 182 m²), 2 app-hoogdicht (FAR 0,99; 135/ha; 79 m²), 3 twee-onder-1-kap, 4 app-middeldicht (52/ha; 95 m²), 5 rijtjes (36/ha; 120 m²), 6 vrijstaand-groot (435 m²). `alternatieven_sn_*.rds` opnieuw gebouwd (long-tabel blijft álle 1,51M sites; ca/menu SN-only). Match gekozen=argmax-RV 5,3% → ASC's in stap 3 essentieel (zoning zit niet in RV).
- **Site-id-vorming verklaard** (config-verkenning): T-sites krijgen GÉÉN clustering — elke Toevoeging-VBO een eigen `T_<rij>`-id met de geometrie van het HELE pand (vandaar 4× site_size 87.087 m² met n_units=1; het 50k-m²-geometriefilter geldt alleen voor NB). TMplus/TMmin hebben gescheiden id-ruimtes zonder enige koppeling → TR-verwerving vergt een eigen (ruimtelijke/pand-)koppeling in GeoDMS. SN: split_union verbindt bij bufferoverlap = pandafstand < 2×10m; Onveranderd v2d verbindt bij < 10m (gedocumenteerd verschil; 20m-adjacency-variant is bouwbaar als robuustheid: inflate 20m alleen voor de adjacency-overlay, geometrie op 10m houden).
- **Stikstof-methode** (verkenning C:\ProjDir\Stikstof): cluster_rel = join_near_values 100m + vergunningsmaand ±6 (integer-YYYYMM; NB jaargrens-bug) → connected_parts; sinds commit 3ec8bd3 (18-06-2026) voor nieuwbouw vervangen door **documentnummer als project-id**; sloop wordt daar niet geclusterd. Hier niet als primaire site-definitie bruikbaar: de onveranderde voorraad (stage-2-nullen) hééft geen documentnummer/datum → asymmetrie. Wel als flags/cleaning: **75,8% van de SN-sites heeft 1 docnummer, 77,3% tijdspreiding 0 mnd; 7,1% heeft >2 docs én >24 mnd spreiding** (kandidaat "meerdere projecten samengeklonterd" → flag + robuustheidsexclusie; `pand_docnum`/`vbo_docnum` zitten in de export).
- **12k SN-sites zonder slooprijen — OPGELOST (by design)**: dit is Jips eigen BBG-route (AdditionalOperations.dms:181–262): nieuwbouw op BBG-2000-woongebied kwalificeert als SN óók zonder waargenomen sloop ("anders onterecht 'slechts' nieuwbouw"); attribuut `IsSN_door_BBG` bestaat al (r.297) — **aanbeveling: als exportkolom meenemen bij de volgende verse run**. Verhoogde 2012–14-percentages (63→31%) = sloop wél in BAG maar vóór het venster. Consequentie: verwerving voor deze sites niet reconstrueerbaar → flag; prima voor stage 1, uitsluiten/imputeren in stage 2.
- **T/O/TM-clustering**: niet nodig voor T (pand is de eenheid; T's zitten niet in menu of uitkomst) en O/S (alleen identificatie tbv pijplijn-censoring stage 2); TM wél clusteren áls het TR-model doorgaat (TMplus+TMmin samen, à la #17, plus niet-woon-onveranderd-universum) — beslissing TR in dit paper of future research.

### 28-07 (vervolg): stap 3+4 gedraaid — RV-coëfficiënt positief ✓

`06_stage1_logit.R` (stap 3+4): conditional logit via survival::clogit (1 gekozen alternatief per stratum = exact McFadden). 41.592 SN-sites × 6 alternatieven (310 afgevallen op incomplete RV): **b_RV = +0,066 per €1M (z = 38,5)** — het theorie-cruciale positieve teken staat. Robuustheid zonder 2.980 multi-projectsites: **+0,108** (cleaning verscherpt; attenuatie door samengeklonterde projecten). ASC's t.o.v. teardown-referentie allemaal negatief (hoogdicht-app −2,75: bestemmingsplan/haalbaarheid drukt hoogdicht ondanks hoogste RV). Concordance 0,74. Inclusive value voor álle 1,51M sites in `stage1_sn_*.rds`; mediaan gerealiseerd 0,774 vs onveranderd-universum 0,756 — goede richting, de echte toets is stage 2. Openstaand voor stap 5: universum/uitkomst-definitie, verwerving BBG-SN-sites, prijsvolatiliteit (NVM), evt. covariaat×ASC-interacties in stage 1.

**Besluiten Jip + uitvoering (28-07, middag):**
- **Transformatie buiten de analyse** (lastig te identificeren; CBS gebruikt er aanvullende databases voor) — afbakening op sloop-nieuwbouw; paper-edits als comment in #28, stap-5-beslispunt in #16 bijgewerkt. TMplus/TMmin blijven getypeerd in de export maar doen niet mee; TM-clustering en niet-woon-universum vervallen daarmee als taken.
- **`is_sn_door_bbg` als exportkolom** in PerObject_Export (4da00f3): site-level `IsSN_door_BBG` via site_id-rjoin, niet-SN → FALSE; parse-check 20.8.0.m OK. Zit pas in de mmd bij de volgende verse run — tot die tijd leidt R de flag af (heeft_sn zonder incumbent-rijen). Zo min mogelijk weggooien: sites blijven in stage 1; alleen de stage-2-estimatie sluit ze uit (verwerving onbekend).
- **Prijsvolatiliteit gebouwd** (PriceIndices `R/06_volatility.R`, geregistreerd als stap 6 in run_all): hedonisch residu-index per regio×jaar (model per WP4 zónder jaar-/locatietermen — trend en lokaal niveau horen in de index), vol = sd van Δindex 2000–2023; drempels 25 trans/regiojaar en ≥10 groeijaren. Korrels: gemeente-2024 (334 regio's, mediaan 0,063), pc4 (1.656, 0,071), **grid5km (730 cellen, 0,067; vintage-vrij koppelbaar via `x/y_coord %/% 5000`)**. CSV's: `NVM Prijsindex/Output/Volatility_20260711_*.csv`; Redevelopment-cfg: `cfg$file_vol(korrel)`, `cfg$vol_cel_m`. Koppeling + fallback-keuze (grid5km-dekking is stedelijk; gemeente-codes zijn 2024-vintage vs onze 2012-indeling!) bij de bouw van `07_stage2_logit.R`.

### 28-07 (slot): stap 5 gedraaid — two-stage-model end-to-end, kerntekens conform theorie

`07_stage2_logit.R` (stap 5): binomiale logit op 905.328 sites (y=1: 29.520 SN = 3,26%; universum = SN- + OnvS-incumbent-sites; O/S = pijplijn eruit, TMmin buiten scope, BBG-SN-sites vallen automatisch af door ontbrekende verwerving; 18.364 missings). Volatiliteit gekoppeld: grid5km 76,8% → met gemeente-fallback 99,5%.

| verklaarder | coef | z | verwacht | ✓? |
|---|---|---|---|---|
| inclusive value | +9,36 | 102 | + | ✓ |
| verwerving (M€) | −0,47 | −98 | − | ✓ |
| eigenaar-bewoners (pp) | −0,0086 | −23 | − | ✓ |
| beschermd gezicht | +0,23 | 6,6 | − | ✗ (selectie binnensteden?) |
| Natura 2000 | +0,63 | 3,2 | − | ✗ (klein/zeldzaam) |
| prijsvolatiliteit | +0,61 | 1,3 | − | n.s. |

McFadden 0,084. Met ln(site_ha)-control blijft iv +6,84 / acq −0,54 (comparability-zorg site-vorming drukt iv niet weg). Pijplijn-robuustheid (S/O als y=1): iv +5,8, acq −0,88, vol −7,3 (z=−27!) — volatiliteit remt vooral het *starten* (sloop/onttrekking), interessant real-options-resultaat. glm-warnings "fitted 0 or 1": extreme acq/iv-staarten (mega-sites) — winsorize-robuustheid nog doen.

**Openstaande verfijningen stage 2** (geen blokkade, wel voor het paper): (1) afbakening op de **22 agglomeraties** (paper-scope; nu heel NL — kolom `agglomeratie` zit in de data), (2) heritage-teken duiden (selectie oude binnensteden; evt. bouwjaar-incumbent als control), (3) winsorize acq/iv + geclusterde SE's (gemeente), (4) BBG-SN-imputatie als robuustheid, (5) K-bevestiging stage-1-menu blijft open (elbow zei 6). → alle behalve (4)/(5) opgepakt in de avondronde hieronder.

### 28-07 (avond): stage-2-upgrade — OAD-scope, bouwjaar-control, geclusterde SE's, 8 specs

Besluiten Jip: afbakening via **OAD** i.p.v. de 22 agglomeraties (zoals vorige paper; `cfg$oad_min = 1000`, sensitiviteit 1500/heel-NL); bouwjaar-control toevoegen; geclusterde SE's. Uitgevoerd in 06 (OAD-filter estimatiesample; NB: maar 13.207 van 41.592 SN-sites heeft OAD≥1000 — 68% van sloop-nieuwbouw is dorps/landelijk! b_RV daar +0,037, robuust +0,065; rijtjes-ASC wordt positief in de stad) en 07 (volledig herschreven: `fixest::feglm`, **SE geclusterd op gemeente** — iv-z ging van 102 naar 7,2, i.i.d.-SE's waren dus zwaar geflatteerd; bouwperiode-incumbent-control met ref va2002; specs basis/kaal/urban1500/nl/size/winsor/vol_gem/sloopstart; AME's; export `stage2_specs_sn_*.csv`).

**Hoofdresultaat (basis: OAD≥1000, 301.471 sites, y=2,8%, McFadden 0,149):** iv +10,02 (z 7,2), verwerving −0,28/M€ (z −5,6), eigenaar-bewoners −0,015/pp (z −6,2), corporatie-aandeel −0,007 (z −3,0), **beschermd gezicht −0,28 (z −2,6) — teken nu goed**, Natura 2000 n.s., volatiliteit n.s. Bouwperiode-gradient = afschrijvingsverhaal: tm1925 +1,06 > 1926-50 +0,76 > 1951-65 +0,69 > 1966-73 ≈ 0 > … > 1992-2001 −1,14 (ref va2002). AME's: +1 IV → +24,6pp; +1M€ verwerving → −0,70pp; +10pp eigenaar-bewoners → −0,36pp.
- **Heritage-verhaal rond**: zónder bouwjaar-control (kaal) +0,20 (z 1,8), mét −0,28 — het eerdere plusteken was pure selectie (beschermde gezichten = oude voorraad); in het paper als illustratie rapporteren.
- iv/acq robuust over alle 8 specs (iv +7,4…+15,4; acq −0,19…−0,50, alle |z|>5).
- **Separatie-lessen**: bp_onbekend-dummy (147 sites, ~0 events) uit de estimatie; pijplijn-variant met Onttrekking (78k O-sites) gaf een vlakke likelihood → vervangen door **sloopstart** (alleen S = sloop-zonder-vervolg als extra y=1; conceptueel ook zuiverder): iv +8,2, acq −0,25, heritage −0,28, vol +3,8 (n.s.) — convergeert.
- **Volatiliteit: nergens robuust significant** (z −1,3…+1,8 over de specs; de eerdere "sterke" pijplijn-z=−27 was een i.i.d.-SE-artefact). Eerlijke conclusie: met een cross-sectionele volatiliteitsmaat geen bewijs voor het real-options-kanaal; nette identificatie zou tijdvariërende vol op het beslismoment vergen (discrete-time hazard, site×jaar) — als extensie bespreken.

Resterende robuustheids-agenda: BBG-SN-imputatie; K-bevestiging (elbow-knik bij 6 ook in SN-sample); 2012-flag-sensitiviteit (#26, flag zit in de data); 20m-adjacency-variant Onveranderd (alleen als reviewers om site-vorming vragen); paper-tabellen (etable) genereren zodra specs definitief. → alles opgepakt in het slot hieronder.

### 28-07 (slot 2): K bevestigd, #26-sensitiviteit, BBG-imputatie, papertabellen — R-pipeline COMPLEET (02–08)

- **K=6 formeel bevestigd**: PRE-knik ná 6 (0,27 bij K=6 → 0,12/0,07 bij 7/8); seed-stabiliteit ARI = 1,000 voor K=5–7 (3 seeds, nstart 25) — stabiliteit discrimineert niet, de PRE-knik + interpreteerbaarheid wel. Vastgelegd in scratch `kbevestiging.R`-uitvoer; cfg$kmeans_k_final = 6 definitief.
- **2012-flag (#26) gerepareerd in 03**: de flag zat in de incumbent-aggregatie (telde altijd 0 — plus-rijen zijn geen incumbent); nu `n_flag_2012` op de plus-kant (sites_nieuw). Spec `excl2012`: slechts 54 verdachte y=1-sites in het stedelijke sample; resultaat onveranderd (iv +9,97 vs +10,02) — **#26 is immaterieel voor stage 2**.
- **BBG-imputatie-spec** (`bbg_imput`): 4.831 BBG-SN-sites binnen de OAD-scope erbij als y=1, verwerving geïmputeerd als mediaan-acq/ha van waargenomen SN-sites (5,98 M€/ha) × site_ha, zonder bouwperiode-control (incumbent onbekend): iv +13,7 (z 8,0), acq −0,46 (z −6,7) — conclusies robuust. NB: heritage flipt daar naar +0,38, net als in `kaal` (+0,20) — beide specs zonder bouwjaar-control, dus een nette bevestiging van het selectieverhaal (beschermde gezichten = oude voorraad).
- **08_tabellen.R**: papertabellen (markdown; stage 1, 2×5 stage-2-specs met sterren + geclusterde SE's, AME's) → `R_werk/paper_tabellen_sn_Nederland_20260710.md`. `run_all.R` draait nu 02–08 end-to-end.
- Volatiliteitsbesluit vastgelegd in #28: rapporteren als n.s. met real-options-duiding; discrete-time hazard = future research; de oude pijplijn-z=−27 niet gebruiken (i.i.d.-artefact).

**Wat nog rest voor de paper-cijfers**: verse GeoDMS-run t.z.t. (levert `is_sn_door_bbg` exact + eventuele NVM-2024-update); pushen (Jip); paper-tekst (#28-lijst). De analytische keten is af.

### 28-07 (verse run + hazard): export herdraaid, alles reproduceert exact; hazard-model gedraaid

- **PerObject_Export vers** (1u42; `Onv_`-prefix uit de naamgevingsronde + `is_sn_door_bbg`): typeverdeling, prijzen en sitecounts byte-gelijk aan de 18-07-mmd; stage-1/2-resultaten en papertabellen identiek — volledige reproduceerbaarheid bevestigd.
- **`is_sn_door_bbg` geverifieerd**: 97.537 rijen op exact de 12.000 sites van de R-afleiding (heeft_sn zonder incumbent; 0 verschillen, alle rijen SN_Nieuwbouw) — beide routes valideren elkaar. 07 blijft op de afleiding draaien en herkent beide prefixen (Onv/OnvS), dus oude én nieuwe mmd's werken.
- **09 hazard gedraaid**: 4.459.369 site-jaren (302.063 sites, 8.400 events = 0,19%/jaar), vol_roll-dekking 99,8%. Resultaat: iv +2,71 (z 7,3), verwerving −0,099/M€ (z −6,0), eigenaar-bewoners −0,015, corporatie −0,008, heritage −0,40 (z −3,7 — nog sterker dan cross-sectioneel); **vol_roll +1,27 (z 1,0, n.s.)** — óók met tijdvariërende volatiliteit geen real-options-bewijs. NB identificatie: na jaar-FE resteert de regionale afwijking van de nationale volatiliteitscyclus; de #28-lijn (rapporteren als geen bewijs) blijft dus staan, nu extra onderbouwd.
- Fixes: 07 prefixfilter Onv/OnvS; 09 `m_kaal` kreeg een expliciete formule (update() op een tweedelige fixest-formule mangelt het FE-deel).

### 29-07 (middag): R-pipeline naar het Engels + wiki-herstructurering

- **Alle 11 R-scripts vertaald** (comments, messages, identifiers; BAG-/domeintermen blijven Nederlands; datalabels, kolomnamen uit de export en bestandsnamen op schijf ongewijzigd). Bestandsnamen: `05_alternatieven.R`→`05_alternatives.R`, `08_tabellen.R`→`08_tables.R`. Spec-labels nu Engels (basis→base, kaal→no_bp, vol_gem→vol_muni, sloopstart→demol_start); papertabel-labels in het Engels (papertaal). Kernrenames: maak_/schat_-functies → build_/estimate_, heeft_→has_, aandeel_→share_, sloop_cost→demolition_cost, s$nieuw→s$new, pijplijn→pipeline, hazard-kolom jaar→year; cfg: prijspeil_jaar→price_level_year, bouwkosten→construction_costs, sloopkosten→demolition_costs, multiproj_mnd→multiproj_months. **Volledige verificatierun: alle resultaten exact identiek** (b_RV 0,037405; 10 stage-2-specs; H1–H4).
- **Wiki geherstructureerd** (repo `_Tools/Redevelopment.wiki`, commit 8ca71ff): nieuwe Home met secties, overleggen in een uitklapblok; nieuwe pagina's Site-vorming, PerObject-export, R-pipeline, Two-stage-model (met actuele resultaten). Pushen: Jip.

### 29-07: real-options v2 (H1–H4) + mmd-reader-polyfix

- **site_geometry-raadsel opgelost**: de mmd-dictionary geeft polygoonkolommen hetzelfde waardetype als punten (`/geography/rdc`; de `(.,poly)`-markering werd niet geparsed) én het polygonen-INDEXbestand is toevallig ook 16 bytes/rij — de reader las dus indexverwijzingen als coördinaten (waarden ~1e-317, full-length onzin; `geometry` als punt was altijd goed). Fix: `01_read_mmd` parset nu de poly-vlag en skipt die kolommen; de huidige perobject-rds bevat tot de volgende 02-run nog twee ongebruikte onzinkolommen (site_geometry_x/_y).
- **Real-options-batterij 09 (H1–H4)**, met twee nieuwe ingrediënten uit PriceIndices 06: rolling **groeiverwachting** `g_roll5` (Capozza & Li: groei én onzekerheid verhogen de optiewaarde van wachten — zonder groei-control is vol vertekend) en een **nationale reeks** (regio 'NL'):
  - H1 (jaar-FE, regionale vol): +1,27 (z 1,0) n.s. — als eerder.
  - H2 (+ regionale groei): vol +1,19 (z 0,9), groei +0,67 (z 0,5) — geen verandering.
  - H3 (gemeente-korrel primair, minder meetruis): vol +2,31 (z 1,5) — nog steeds n.s.
  - **H4 (géén jaar-FE; regionale + nationale vol/groei + lineaire trend): vol_nl = −10,77 (z −5,2)** — de nationale volatiliteit remt herontwikkelingsstarts sterk; regionale vol blijft n.s. (+1,75, z 1,4), nationale groei n.s.
  - iv/acq/fricties in alle vier stabiel (iv +2,7; acq −0,10; heritage −0,40).
- **Interpretatielijn voor het paper**: het real-options-mechanisme manifesteert zich op macroniveau — in hoogonzekere jaren (crisisperiode) storten de starts in, conditioneel op trend en groeiverwachting — maar zónder jaar-FE vangt vol_nl elke gecorreleerde macroschok mee (krediet, rente, beleid). Rapporteren als "consistent met real options op nationaal niveau; in regionale variatie (wél zuiver geïdentificeerd) geen bewijs". Mogelijke verscherping t.z.t.: rente/kredietvoorwaarden als expliciete controls in H4.

### 17-07 (historie): OnveranderdSites v2 (opgedeeld) klaargezet voor de vólgende run

De v1-route (SN-identiek: landelijke `geos_split_union_polygon`) bleek op voorraadschaal een **single-threaded cross-tile-merge van >12 uur** te hebben (per-tile-fase 83 tiles was in ~6 uur klaar; de stille mergefase draaide daarna nog uren op 1 core). De lopende run is bewust uitgedraaid (resultaat blijft bruikbaar), maar `OnveranderdSites.dms` is herschreven naar **v2 zonder enige landelijke union**: bufferdelen per pand geknipt op weg/spoor en gefilterd op het eigen blok → `polygon_connectivity` (getilde adjacency, geen intersectiegeometrieën) → `connected_parts` (union-find) → site-geometrie via gepartitioneerde `geos_union_polygon` per site. Semantisch equivalent (zelfde 10m/weg-spoor-logica); VBO→site loopt nu via pand-rel i.p.v. point_in_polygon. **Parse-checked maar nog niet gedraaid** — de eerstvolgende verse run gebruikt v2 en zou de OnveranderdSites-fase tot ~1-2 uur moeten terugbrengen; vergelijk dan sitecounts/distributies even met de v1-uitkomst van 16/17-07.

### Openstaand na deze sessie

1. **R-modelkeuzes (#16 stap 2–5)**: alternatieventabel + residual value, conditional logit, inclusive value, stage-2 logit. Universe-afbakening stage 2 (#13) en clustering Onveranderd (#17) open. Cluster-K bevestigen (elbow.csv); cluster 5 (appartement-laagdicht, FAR 0,14) verdient een blik op de site_size-definitie bij pure nieuwbouw-sites.
2. **d_hoogte_onbekend**: geen regiogemiddelde in de export → staat op 0 in de reconstructie; desgewenst regiotif toevoegen in PriceIndices.
3. ~~Mapping 10 Redev_ObjectTypes → paperklassen~~ — **vervallen (27-07)**: de 10 Redev_ObjectTypes uit de GeoDMS-code zíjn de klassen. Wat rest is de uitkomst-definitie voor stage 2 (welke typen tellen als "herontwikkeld"; sloop-nieuwbouw vs transformatie apart) — staat als beslispunt in #16 stap 5.
4. **Push** van alle commits (Redevelopment + PriceIndices) — niet gedaan, zoals afgesproken doe je dat zelf.
5. Legacy rode items PriceComponents (Verwervingskosten/Grondproductiekosten) blijven bewust staan; de nieuwe `HouseCharacteristics_src`-namen maken er een paar extra rood — allemaal achterhaald door de componenten→R-aanpak.

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

1. ~~Steekproef in GUI~~ — GEDAAN 16-07 via `ValidatieTypering/SteekproefKetens` (systematische ketencheck, alle categorieën ✓; zie sectie 16-07 hierboven).
2. ~~**NL-run** + diagnose 100-dagenregel × filters~~ — GEDAAN 16-07 (`Diagnose100Dagen_Nederland_20260710.csv`: filters winnen in ~1% van de S-kandidaten).
3. ~~**Beide mmd's regenereren**~~ — GEDAAN 16-07 (FinalMutationTable + PerObject_Export, Nederland/20260710, incl. pand_type en alle nieuwe exportkolommen).
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

- Kolommen aanwezig: identifiers (site_id, vbo/pand_bag_nr, docnums, x/y), outcomes (was_redeveloped, redev_type [10 Redev_ObjectTypes; dit zijn de definitieve klassen — aparte paperklassen vervallen 27-07], redev_yearmonth), incumbent (site_size, site_sum_footprint, obj_building_year, obj_floor_area_res_m2, obj_housetype [WP4], obj_is_woonfunctie), prijscomponenten (loc_tt_500k_min, loc_tt_station2006_min [placeholder #18], 16× reg_*, UAI_2012 [#19]), regio (gemeente/wijk/buurt_code, agglomeratie), buurt/wijk (p_owner_occupier_buurt, p_socialhousing_buurt, wijk_p_woningcorporatie, OAD, UrbanisationK), planning (IsProtectHeritageArea, is_natura2000).
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
