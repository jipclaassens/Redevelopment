# Port from EconLogicPaper — bugfixes only (August 2026)

EconLogicPaper is the same repository, `6dcbfcb` further ahead: `git merge-base` between the two
returns this repo's HEAD, so every EconLogic commit is a descendant. That made it possible to
select individual commits rather than copy files (`redev_obv_hele_bag.dms` alone differs by 800
lines, almost all of it EconLogic export features).

The rule applied: port what corrects the **mutation typing**, leave everything that adds
EconLogic functionality. The paper is being revised on the current identification logic; the
larger EconLogic changes (new-construction identification, WP4 dwelling typing, price
components, `OnveranderdSites`) come later, together with newer data.

## Ported

| Commit | What | Why it is a fix |
|---|---|---|
| `0489602` | Four corrections to the CBS stock-mutation rules | Directional clearing (a leftover opposite-direction flag cancelled a real mutation in the second-instance clearing); `IDEN_N_3` building-year window `\|\|` → `&&` (the OR was a tautology); `WasObjectVoorraadBijStartBAG` now means "in stock **on** the start date"; `IDEN_Cmin_Restbakje` matches its own comment |
| `7d1d4d3` | One typing row per (vbo, reporting month) | Per CBS a dwelling carries at most one stock mutation per month; duplicate rows each carried the same typing and were **counted twice**. Amsterdam effect: Cplus −495, TMplus −25 |
| `bf18454` | Mutation typing conform CBS 86098 | 100-day demolition rule; `IDEN_N`/`IDEN_T` only on first entry into stock; `DirectInVoorraad` split with the new `IDEN_T_1b` branch; **the blind Cplus→T / Cmin→O mapping removed**; dwellings with only C± now count as unchanged. Changes ~1.9% of mutations |
| `05c5912` (part) | `ZonderCorrecties` moved out of the storage unit | As introduced by `bf18454` it sits inside a unit with a `StorageName`, where GeoDMS turns calculated subunits into storage placeholders (empty file in the mmd, `org_rel` parse errors on the read side). It is now `FinalMutationTable_ZonderCorrecties` beside the Write/Read switch |
| `bf18454` (part) | `Descr` on `pand_status/IsVoorraad` | Documents the deliberate deviation from CBS 86098 §4.4 (issue #25). Comment only |

`bf18454` needed two path translations, because EconLogic reorganised the source tree:
`/SourceData/Vastgoed/BAG/` → `/SourceData/BAG/` and
`/SourceData/grondgebruik/bestand_bodem_gebruik/` → `/SourceData/bestand_bodem_gebruik/`.

## Ported in the second pass (beyond the mutation typing)

The first pass only followed the files that feed the mutation typing. That was too narrow: the
BRT layer feeds `WegSpoor_area`, `Water_area` **and** the buffer clipping in the replacement
identification, so it reaches both `p_onbebouwd` and `land_area` (the PPML exposure).

| Source | What | Why it is a fix |
|---|---|---|
| `e1eb6b5` | `brt.dms`: `bg_overlay_polygon` → `geos_overlay_polygon`, `bp_union_polygon` → `geos_union_polygon`, `bp_difference` → `geos_difference`, for the tiles as well as `Wijken_x_WegSpoor` and `Wijken_x_Water` | The old route converted to `rdc_cm` before the union/difference, so geometries were rounded to centimetres and back. GEOS works directly in `rdc` and is the more robust implementation |
| `e1eb6b5` | `Redev_Types : nrofrows = 111` → `11` | Typo: the name list has 11 entries |
| `e1eb6b5` | `PrevDomain` special case for 2011 | For the first year `PrevYear` is 2011, for which no `Per1Jan` state exists (the register starts in 2012), so it referenced a non-existent domain |
| `e1eb6b5` | `geos_buffer_multi_polygon(..., 16b)` → `4b`, all five calls in `AdditionalOperations.dms` | Ported on Jip's instruction: he tested it and the output barely moves. Note for the methods section that the 10 m buffer is approximated with 4 segments per quarter circle |
| — | `regios.dms`: `x_BeschermdeStadDorpgezichten` from `bp_overlay_polygon(geometry[rdc_cm], ...)` to `geos_overlay_polygon(geometry, ...)`, dropping the now-redundant `geometry_rd` | **Not from EconLogic** — both configurations still had the old form. Applied on Jip's instruction, for consistency with the BRT migration: the wijk and townscape boundaries were rounded to centimetres before the overlay. Feeds `opp_BeschermdeStadDorpgezichten` and therefore `p_beschermd`. Only `area` and `first_rel` are used outside the unit, so removing `geometry_rd` is safe |

## Ported in the third pass (BAG selection, 19 August 2026)

| Commit | What | Why it is a fix |
|---|---|---|
| `432808e` | `VolledigeBAG/panden/pand`: added `&& IsStudyArea` to `pand_selection_condition`, with the flag itself declared next to the other `src` attributes | The pand selection only tested the bounding box, so it kept 1,721 buildings whose centroid falls outside the Netherlands. RSopen applies `IsStudyArea` on the same source table, so the two configurations produced different pand domains: 24,442,587 here against 24,440,866 there. That is what made the shared, positional WP5 files unusable between the projects, and GeoDMS accepts such a file without any error as long as it is longer than the domain (ObjectVision/GeoDMS#1187) |

One translation was needed, in the same spirit as the path translations above. This branch uses
`BAG_Selection_Area := 'NL'`, main uses `'Nederland'`, and the flags in the VolledigeTabel are
named `IsNederland`, `IsFriesland`, `IsUtrecht` and `IsNoord_Holland`. A literal port would have
resolved to `IsNL` and broken the configuration, so the expression maps `'NL'` to `IsNederland`
explicitly and keeps the generic `'Is'+<area>` branch for the other names. The `'AMS'` branch
still uses the ad hoc municipal boundary, because no flag exists for it.

Verified on this machine: `/SourceData/BAG/VolledigeBAG/panden/pand` now holds 24,440,866
records, exactly the 1,721 fewer that the flag removes, and identical to what RSopen selects
from the same table.

Note that the vbo side still differs from RSopen, which filters vbo's on the bounding box and on
`IsStudyArea` while this branch applies no filter for a nationwide run. That is 6,279 records on
25,948,762. Not ported: it would drop objects from the analysis, which is a choice for the paper
rather than a correction, and no shared cache depends on it today.

## Judgement calls — NOT ported, decide explicitly

| Source | What | Assessment |
|---|---|---|
| `e1eb6b5` | `unit<uint16> jaar` → `yr = BaseUnit('Yr', UInt16)` plus `jaar = BaseUnit('Yr', float32)`, and `<jaar>` → `<Yr>` across modules | Cross-cutting. It does fix a latent problem — `Avg_bouwjaar := mean(...)` currently lands in a uint16 unit, so an average building year is truncated — but that attribute does not reach `Analyse_PerWijk`. Port only together with a broader clean-up; it touches `Units.dms`, `VolledigeBAG.dms`, `PrepBAG.dms` and more |
| `f680f24` | `PandVanafMonumentaalJaar := 1920w`, replacing the hard-coded `bouwjaar <= 1900w` in `monumentale_panden` | **Not a fix, a different choice.** It moves the monument proxy from pre-1900 to pre-1920 and would shift the UAI, one of the four core regressors. Decided: keep 1900 |
| `e1eb6b5` | `StudyArea` default `'NL'` → `'AMS'` | Do not port; this paper is nationwide |
| `e1eb6b5` | Source paths `SourceData/BRT` → `SourceData/Grondgebruik/BRT`, `SourceData/BAG` → `SourceData/Vastgoed/BAG` | Tree reorganisation. Port only if you also reorganise, otherwise it just creates conflicts. All ported hunks were translated back |
| `e1eb6b5` | float64 extents in `AfleidingPandtype`, lowercase matching for the standplaats `status_rel` | Genuine robustness fixes, but in the dwelling-type derivation, which this paper does not use. Port with the WP4 work later |
| `7f61bf0` | "bouwjaar-proxy definitief (#26)" | STATUS.md only — a decision note, no configuration change. The building-year work in the configuration is the `Yr` standardisation above |

## Deliberately NOT ported

- `Verslagmaanden_additional` (from `bf18454`/`e4afbb5`). EconLogic runs to 2026-06; **this paper's
  window stays 2012-01 … 2025-10**. See the BAG note below.
- `OnveranderdSites` v2 (`022ae59`, `d3f848d`, `9fd1ec5`, `26888fe`, `99597b2`) — the site menu for
  the choice model.
- WP4 dwelling typing (`3fa1f05`, `225926d`, `c09bc1a`, `d4e7fd7`) and price/WOZ/estimates
  (`d397f23`) — inputs to the hedonic model.
- Site geometry (`821dbd2`), `is_sn_door_bbg` export column (`954ff6d`), `ValidatieTypering`,
  `VergelijkWP4`, `ExportMutatieVergelijking` — useful later, not needed now.
- `e4afbb5` deprecation fixes (`points2sequence` → `points2polygon`, `meter2` → `m2`) and
  `VolledigeBAG.dms` `bouwjaar[yr]` cast. The current configuration parses and exports without
  them; port them when GeoDMS starts warning.
- The two silent errors of `4798054` are in EconLogic's **R** pipeline, not in GeoDMS. One of them
  (the uint32 null sentinel of OAD counting as highly urban) was checked against our export:
  OAD max 9,106, zero sentinels, and the GeoDMS urbanity class matches a plain recomputation for
  all 2,621 neighbourhoods. Not an issue here.

## BAG update

`BAG_file_date` 20251009 → **20260711**.

The observation window is hard-coded in `AdditionalClassifications/Verslagmaanden`
(`Verslagmaanden0` = 2012-01 … 2024-12 plus `Verslagmaanden_additional` = 2025-01 … 2025-10) and
does **not** depend on `BAG_file_date`. A later extraction therefore covers the same period but
with registrations that arrived up to July 2026 — BAG mutations are recorded with a lag, so the
final years become more complete. That is exactly the limitation the paper already admits
("mutations that occur late in the observation period may not yet be followed by replacement").

Note for the methods section: the window ends **October 2025**, not December. "Between 2012 and
2025" is loose; say January 2012 to October 2025.

## What has to be re-run

0. **The BRT tile cache is now stale and will not notice.** `Write/Read_Relevant_Tiles_x_WegSpoor`
   caches to `Temp/BRT/TiledNonWegSpoor_<BRT_file_date>.fss`, and the filename does not change
   when the geometry operations do. Delete that file (and the two
   `Wijken_x_WegSpoor_<date>_Area.fss` / `Wijken_x_Water_<date>_Area.fss` files) before the run,
   or bump `BRT_file_date`. Otherwise the GEOS migration has no effect and you silently keep the
   old boost geometry. EconLogic sidesteps this by writing `.mmd`, which renames the file; that
   change was not ported because it cannot be verified here.
0b. **The pand domain shrank by 1,721 records**, so every cached file that runs positionally over
   the pand selection is now one element too long. GeoDMS reads such a file without complaining
   and silently ignores the surplus, which shifts every value after the first divergence. Delete
   the WP5 files under `Vastgoed/VolledigeTabel_<BAG_file_date>/WP5/` if this branch ever reads
   them, and rebuild the caches in point 1 below rather than reusing them.

1. `Parameters/Use_Ontkoppelde_FinalMutations` is `TRUE`, so the chain **reads** a cached
   `FinalMutationTable_NL_<BAG_file_date>.mmd`. With the new date that file does not exist yet,
   and the typing rules changed, so the cache must be rebuilt:
   set the parameter to `FALSE`, or run `MaakOntkoppeldeData/Write_FinalMutationTable` first.
   **Skipping this silently re-exports the old typing.**
2. Then `MaakOntkoppeldeData/PerObject_Export`, then `Analyse_PerWijk`.
3. Expect the counts to move. The typing changes concentrate on the C± (correction) rows, which
   feed `count_Toevoeging` — the "within-building changes" category, 21% of net additions in the
   published Table 1. Removing the blind Cplus→T mapping should **reduce** it. Check that first.
4. Re-run `R/run_all.R` afterwards. `R/04_validate.R` pins to export 20250602 and must keep
   passing: it validates the R port, not the GeoDMS output, so it is unaffected by this change and
   stays the reference point for the published tables.

## Open decision

`WK_centroide` is declared as `attribute<rdc>` and therefore never reaches the CSV: the GDAL CSV
driver treats a point attribute as the layer geometry and drops it. Either split it into two
scalar columns or set `GEOMETRY=AS_WKT`. Not blocking — `R/07_spatial.R` takes centroids from
`cbsgebiedsindelingen2012.gpkg` instead.
