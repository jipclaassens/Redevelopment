// Set directory Jip
cd "D:\OneDrive\OneDrive - Objectvision\VU\Projects\202008-RedevelopmentPaper"

ssc install outreg2 //install outreg2 voor het wegschrijven van regressie resultaten naar word/excel/etc.

global filedate = 20250328  // 20241211  20250226

import delimited Data\Analyse_PerWijk_${filedate}.csv, clear
// ==================================================== //
// ===============  DATA PREPERATION  ================= //
// ==================================================== //

local replaceNullList = "oad p_huurcorp modus_buildingyear_2012" 
foreach x of local replaceNullList{
	replace `x' = "" if `x' == "null"
	destring `x', replace
}

rename modus_buildingyear_2012 bouwjaar
rename mean_uai uai
rename total_area total_area
rename wegspoor wegspoor_area
rename water_ water_area
rename pandfootprint pandfootprint
rename opp_besch opp_beschermdestaddorpgezicht


///nieuwe version op basis van analyse verderop.
g construction_period_label = ""
replace construction_period_label = "Construction 1929 and earlier" if bouwjaar <= 1929 & bouwjaar != . 
replace construction_period_label = "Construction 1930-1957" if bouwjaar >= 1930 & bouwjaar <= 1957
replace construction_period_label = "Construction 1958-1968" if bouwjaar >= 1958 & bouwjaar <= 1968
replace construction_period_label = "Construction 1969-1975" if bouwjaar >= 1969 & bouwjaar <= 1975
replace construction_period_label = "Construction 1976-1985" if bouwjaar >= 1976 & bouwjaar <= 1985
replace construction_period_label = "Construction 1986-1995" if bouwjaar >= 1986 & bouwjaar <= 1995
replace construction_period_label = "Construction 1996-2008" if bouwjaar >= 1996 & bouwjaar <= 2008
replace construction_period_label = "Construction 2009 and later " if bouwjaar >= 2009 & bouwjaar != .
encode construction_period_label, generate(construction_period)


* Bouwperiode-labels en condities
local labels 1929_earlier 1930_1957 1958_1968 1969_1975 1976_1985 1986_1995 1996_2008 2009_later

local conds  bouwjaar<=1929 ///
             inrange(bouwjaar,1930,1957) ///
             inrange(bouwjaar,1958,1968) ///
             inrange(bouwjaar,1969,1975) ///
             inrange(bouwjaar,1976,1985) ///
             inrange(bouwjaar,1986,1995) ///
             inrange(bouwjaar,1996,2008) ///
             bouwjaar>=2009

local nice_labels "≤1929 1930–1957 1958–1968 1969–1975 1976–1985 1986–1995 1996–2008 ≥2009"
local n : word count `labels'

forvalues i = 1/`n' {
    local varname   : word `i' of `labels'
    local condition : word `i' of `conds'
    local labtxt    : word `i' of `nice_labels'

    gen bouwperiode_`varname' = `condition' if !missing(bouwjaar)
    label var bouwperiode_`varname' "Bouwperiode: `labtxt'"
}


g count_total_proces_pluschange = count_sn_nieuwbouw + count_nieuwbouw + count_toevoeging + count_transformatiep
// g count_total_proces_minchange  = count_sn_sloop + count_sn_sloop_nw + count_onttrekking + count_transformatiem + count_sloop

g land_area =  total_area - water_area
g land_area_ha = land_area * 100

g p_woninggroei = ((count_woon_y2024 - count_woon_y2012) / count_woon_y2024) * 100
g count_woninggroei   = count_woon_y2024 - count_woon_y2012
g count_woninggroei_ha   = count_woninggroei / land_area_ha

g count_woninggroei_ha_plus   = count_total_proces_pluschange / land_area_ha
g cnt_wgr_ha_snnb   = count_sn_nieuwbouw / land_area_ha
g cnt_wgr_ha_nb     = count_nieuwbouw / land_area_ha
g cnt_wgr_ha_toev   = count_toevoeging / land_area_ha
g cnt_wgr_ha_trfp   = count_transformatiep / land_area_ha

g ln_cnt_wgr_ha_plus = ln(count_woninggroei_ha_plus)
g ln_cnt_wgr_ha_snnb = ln(cnt_wgr_ha_snnb)
g ln_cnt_wgr_ha_nb   = ln(cnt_wgr_ha_nb)
g ln_cnt_wgr_ha_toev = ln(cnt_wgr_ha_toev)
g ln_cnt_wgr_ha_trfp = ln(cnt_wgr_ha_trfp)



g p_sn_nb = (count_sn_nieuwbouw / count_total_proces_pluschange) * 100
g p_nb = (count_nieuwbouw / count_total_proces_pluschange) * 100
g p_toev = (count_toevoeging / count_total_proces_pluschange) * 100
g p_transf = (count_transformatiep / count_total_proces_pluschange) * 100

// replace area = area / 1000000

// g lnlandprice = ln(landprice)
// g lnOAD = ln(oad)
// g lnArea = ln(area)
g lnP_woninggroei = ln(p_woninggroei)

g p_beschermd = opp_besch / land_area * 100
replace p_beschermd = 100 if p_beschermd > 100
replace uai = uai * 100

g p_beschikbaar = ((land_area - wegspoor) / land_area) * 100
g p_onbebouwd   = ((land_area - wegspoor - pandfootprint) / land_area) * 100

//plus list
local types "sn_nieuwbouw nieuwbouw toevoeging transformatiep"
foreach t of local types{ 
	g P_`t' = (count_`t' / count_total_proces_pluschange) * 100
}

//minus list
// local types "sn_sloop sn_sloop_nw sloop onttrekking transformatiem"
// foreach t of local types{ 
// 	g P_`t' = (count_`t' / count_total_proces_minchange) * 100
// }

label var total_area "Opp van wijk in km2"
label var wegspoor_area "Opp van weg en spoor in wijk in km2"
label var water_area "Opp van water in wijk in km2"
label var land_area "Opp van land in wijk in km2"
label var land_area_ha "Opp van land in wijk in ha"
label var pandfootprint "Pandfootprint in wijk in km2"
label var oad "Gemiddelde omgevingsadressendichtheid in wijk"
label var p_huurcorp "Percentage huurcorporatie woningen in wijk"
// label var landprice "Gemiddelde residuele grondwaarde in 2007 in wijk"
label var bouwjaar "Gemiddelde bouwjaar in 2012 in wijk"
label var count_woon_y2012 "Aantal woningen in 2012 in wijk"
label var count_woon_y2024 "Aantal woningen in 2024 in wijk"
// label var count_sn_sloop "Aantal gesloopte woningen via sloop-nieuwbouw"
// label var count_sn_sloop_nw "Aantal gesloopte niet-woningen via sloop-nieuwbouw"
// label var count_sn_nieuwbouw "Aantal nieuw gebouwde woningen via sloop-nieuwbouw"
// label var count_toevoeging "Aantal toegevoegde woningen via toevoeging"
// label var count_onttrekking "Aantal onttrokken woningen via onttrekking"
// label var count_transformatiem "Aantal onttrokken woningen via transformatie"
// label var count_transformatiep "Aantal toegevoegde woningen via transformatie"
// label var count_nieuwbouw "Aantal nieuw gebouwde woningen zonder opvolgende sloop"
// label var count_sloop "Aantal gesloopte woningen zonder opvolgende nieuwbouw"
// label var count_onveranderd "Aantal onveranderde woningen"
label var construction_period "Gem. bouwjaar categorie"

label var p_woninggroei "Percentage woninggroei tussen 2012-2024 in wijk"
label var count_woninggroei "Aantal woningverandering tussen 2012-2024 in wijk"
label var count_woninggroei_ha "Aantal woningverandering per ha tussen 2012-2024 in wijk"
label var count_woninggroei_ha_plus "Aantal positieve woningverandering per ha tussen 2012-2024 in wijk"
label var p_sn_nb "Percentage sloop-nieuwbouw van totale positieve verandering"
label var p_nb "Percentage nieuwbouw van totale positieve verandering"
label var p_toev "Percentage toevoeging van totale positieve verandering"
label var p_transf "Percentage transformatie van totale positieve verandering"
label var lnP_woninggroei "log (Percentage woninggroei tussen 2012-2024 in wijk)"
// label var lnlandprice "log (Gemiddelde residuele grondwaarde in 2007 in wijk)"
label var uai "Gemiddelde urban attractivity index in 2012 in wijk"
// label var p_groei_woon "Percentage woninggroei tussen 2012-2024 in provincie"
label var p_beschermd "Percentage oppervlak beschermd stad- en dorpsgezicht in wijk"
label var p_beschikbaar "Percentage landoppervlak niet weg of spoor in wijk"
label var p_onbebouw "Percentage landoppervlak niet weg, spoor of pand in wijk"

drop wk_code count_woon_y2012 count_woon_y2024   count_sn_nieuwbouw count_nieuwbouw count_toevoeging  count_transformatiep     opp_beschermdestaddorpgezic  count_total_proces_pluschange 

//////////////////////////////////////////////////////////////////////
**# ////////////////////////// ANALYSES //////////////////////////////
//////////////////////////////////////////////////////////////////////

/// onderzoek van multicollineariteit
pwcorr oad p_huurcorp uai p_beschermd p_onbebouwd pandfootprint p_woninggroei bouwperiode_1929_earlier bouwperiode_1930_1957 bouwperiode_1958_1968 bouwperiode_1969_1975 bouwperiode_1976_1985 bouwperiode_1986_1995 bouwperiode_1996_2008
collin oad p_huurcorp uai p_beschermd p_onbebouwd pandfootprint p_woninggroei bouwperiode_1929_earlier bouwperiode_1930_1957 bouwperiode_1958_1968 bouwperiode_1969_1975 bouwperiode_1976_1985 bouwperiode_1986_1995 bouwperiode_1996_2008

**2025-03-28 
// De VIF's zijn allemaal acceptabel (hoogste is 7.19),
// De condition number is 55.5, wat wijst op matige multicollineariteit, maar geen paniekgebied,
// De determinant van de correlatiematrix is positief (0.0074), dus het model is identificeerbaar.
// De hoogste VIF is voor bouwperiode_1969_1975 (VIF = 7.19). Dat is niet verrassend:
// Deze dummy is negatief gecorreleerd met veel andere bouwperiodes (zoals uit je pwcorr blijkt),
// Maar waarschijnlijk komt die ook vaak voor in je data (denk: veel wijken gebouwd in die tijd),
// Hij overlapt dus statistisch sterk met de andere tijdvakken, vooral 1958–1968 en 1976–1985.
// Toch: een VIF tot 10 wordt vaak als acceptabel beschouwd, en jij zit op gemiddeld 3.32 → helemaal prima.

reg  count_woninggroei_ha_plus oad p_huurcorp uai p_beschermd p_onbebouwd b8.construction_period, r allbaselevels

// Modelkwaliteit
// R² = 0.6433 → zeer sterk verklarend vermogen
// F(14, 2543) = 57.57, p < 0.0000 → model als geheel is significant
// N = 2.558 → goede robuustheid
//
// Je model laat helder zien dat compacte, aantrekkelijke stedelijke wijken, vooral met recente bebouwing, het meeste toevoegen qua woningen per hectare.
// De rol van bouwperiode is sterk: naarmate de wijk ouder is, neemt de groeidynamiek af.
// Pandfootprint en open ruimte zijn beperkende factoren — logisch, want weinig fysieke ruimte = minder mogelijkheden.

pca oad p_huurcorp uai p_beschermd p_onbebouwd pandfootprint ///
bouwperiode_1929_earlier ///
bouwperiode_1930_1957 ///
bouwperiode_1958_1968 ///
bouwperiode_1969_1975 ///
bouwperiode_1976_1985 ///
bouwperiode_1986_1995 ///
bouwperiode_1996_2008

predict pca_stedelijk pca_sociaal pca_bouwtijd
label var pca_stedelijk "PCA component 1: stedelijke structuur"
label var pca_sociaal "PCA component 2: sociaal-historisch profiel"
label var pca_bouwtijd "PCA component 3: dominante bouwtijd"

reg count_woninggroei_ha_plus pca_stedelijk pca_sociaal pca_bouwtijd, r

// R²	0.530	Verklaart 53% van de variantie in woninggroei/ha
// F(3, 2554)	197.65	Model is significant als geheel
// Root MSE	1.967	Standaardfout van de voorspelling
// N	2.558	Robuust aantal waarnemingen
// Voor slechts 3 variabelen is dit een krachtig en parsimonieus model.

// pca_stedelijk	+1.24	Zeer sterk positief effect: compacte, goed-gefaciliteerde wijken groeien hard
// pca_sociaal	–0.15	Significante negatieve relatie: sociale huur/naoorlogs erfgoed beperkt groei
// pca_bouwtijd	≈ 0 (n.s.)	Niet significant → geen onafhankelijk effect van dominante bouwperiode
// pca_bouwtijd: dit betekent: in dit model draagt deze component statistisch niets bij aan de voorspelling, gegeven dat pca_stedelijk en pca_sociaal al in het model zitten.
// Conclusie: Ja — dit is bewijs dat je pca_bouwtijd veilig kunt weglaten uit dit regressiemodel, in de huidige vorm.

reg  count_woninggroei_ha_plus pca_stedelijk pca_sociaal ib8.construction_period, r allbaselevels

// R²	0.547	54,7% verklaarde variantie (zeer goed!)
// F(9, 2548)	68.76	Model is sterk significant als geheel
// Root MSE	1.935	Standaardfout van voorspelling
// Categorische bouwperiode voor het expliciet vangen van beleids-/historische effecten
// pca_stedelijk	+1.30	Sterk positief: compacte, goed ontsloten wijken groeien meer
// pca_sociaal	–0.23	Negatief: wijken met sociaal profiel / beschermd karakter groeien minder

*check interactie tussen stedelijk/bouwjaarcats
reg  count_woninggroei_ha_plus ib8.construction_period##c.pca_stedelijk pca_sociaal ib8.construction_period, r allbaselevels

*"De positieve relatie tussen stedelijke structuur en woninggroei per hectare is significant in recent gebouwde wijken (2009+), maar zwakt af in oudere wijken. In bouwperiodes vóór 2000 is het effect kleiner en niet meer significant. Dit duidt op ruimtelijke en beleidsmatige beperkingen voor verdichting in oudere structuren."

*FINAL
reg  count_woninggroei_ha_plus pca_stedelijk pca_sociaal ib8.construction_period, r allbaselevels




**# ZONDER PCA
pwcorr p_huurcorp uai p_beschermd p_onbebouwd p_beschikbaar p_woninggroei bouwperiode_1929_earlier bouwperiode_1930_1957 bouwperiode_1958_1968 bouwperiode_1969_1975 bouwperiode_1976_1985 bouwperiode_1986_1995 bouwperiode_1996_2008
collin p_huurcorp uai p_beschermd p_onbebouwd p_beschikbaar p_woninggroei bouwperiode_1929_earlier bouwperiode_1930_1957 bouwperiode_1958_1968 bouwperiode_1969_1975 bouwperiode_1976_1985 bouwperiode_1986_1995 bouwperiode_1996_2008

reg  count_woninggroei_ha_plus p_huurcorp uai p_beschermd p_onbebouwd p_woninggroei ib8.construction_period, r allbaselevels


// R² = 0.60 → verklaart 60% van de variantie in count_woninggroei_ha_plus
// Alle kernvariabelen (behalve p_beschermd) zijn significant
// Geen serieuze multicollineariteit (VIF's allemaal < 7.2, mean VIF = 3.37)
// 📌 Conclusie: Je hebt een goed functionerend model met losse variabelen, zonder noodzaak tot PCA.
//
// p_huurcorp	+0.026	Corporatiewijken groeien juist sterker (verrassend maar consistent in jouw data)
// uai	+0.31	Aantrekkelijke wijken (voorzieningen) groeien meer
// p_onbebouwd	–0.11	Meer open ruimte correleert met minder woninggroei/ha (logisch)
// p_woninggroei	+0.042	Sterke samenhang: waar meer groeit in totaal, is ook de dichtheidsgroei hoger
// p_beschermd	Niet sig.	→ geen consistent zelfstandig effect


reg  count_woninggroei_ha_plus p_huurcorp uai p_beschermd p_onbebouwd p_woninggroei ib8.construction_period, r allbaselevels
outreg2 using output/PerWijk_${filedate}_nose, excel label dec(3) nose
reg  ln_cnt_wgr_ha_plus p_huurcorp uai p_beschermd p_onbebouwd p_woninggroei ib8.construction_period, r allbaselevels
outreg2 using output/PerWijk_${filedate}_nose, excel label dec(3) nose


//====== per type
reg  ln_cnt_wgr_ha_snnb p_huurcorp uai p_beschermd p_onbebouwd p_woninggroei ib8.construction_period, r allbaselevels


// local types "sn_nieuwbouw nieuwbouw toevoeging transformatiep sn_sloop sn_sloop_nw sloop onttrekking transformatiem"
// local types "sn_nieuwbouw nieuwbouw toevoeging transformatiep"
local types "snnb nb toev trfp"
// local types "snnb"
foreach t of local types{ 
    display ""
    display ""
    display "---------------------------------------------"
    display "---------------------------------------------"
    display "-- Regressing redev type = `t' --"
    display "---------------------------------------------"
    display "---------------------------------------------"
// 	reg  ln_cnt_wgr_ha_`t' p_woninggroei, r	
// 	outreg2 using output/PerWijk_${filedate}_cnt_nose_`t', excel cttop (`t') label dec(3) nose
// 	reg  ln_cnt_wgr_ha_`t' p_huurcorp, r	
// 	outreg2 using output/PerWijk_${filedate}_cnt_nose_`t', excel cttop (`t') label dec(3) nose
// 	reg  ln_cnt_wgr_ha_`t' uai, r	
// 	outreg2 using output/PerWijk_${filedate}_cnt_nose_`t', excel cttop (`t') label dec(3) nose
// 	reg  ln_cnt_wgr_ha_`t' p_beschermd, r	
// 	outreg2 using output/PerWijk_${filedate}_cnt_nose_`t', excel cttop (`t') label dec(3) nose
// 	reg  ln_cnt_wgr_ha_`t' p_onbebouwd, r	
// 	outreg2 using output/PerWijk_${filedate}_cnt_nose_`t', excel cttop (`t') label dec(3) nose
// 	reg  ln_cnt_wgr_ha_`t' ib8.construction_period, r	
// 	outreg2 using output/PerWijk_${filedate}_cnt_nose_`t', excel cttop (`t') label dec(3) nose
//	
// 	reg  ln_cnt_wgr_ha_`t' p_woninggroei p_onbebouwd p_huurcorp ib8.construction_period, r	
// 	outreg2 using output/PerWijk_${filedate}_cnt_nose_`t', excel cttop (`t') label dec(3) nose
// 	reg  ln_cnt_wgr_ha_`t' p_woninggroei p_onbebouwd uai ib8.construction_period, r	
// 	outreg2 using output/PerWijk_${filedate}_cnt_nose_`t', excel cttop (`t') label dec(3) nose
// 	reg  ln_cnt_wgr_ha_`t' p_woninggroei p_onbebouwd p_beschermd ib8.construction_period, r	
// 	outreg2 using output/PerWijk_${filedate}_cnt_nose_`t', excel cttop (`t') label dec(3) nose
//	
// 	reg  ln_cnt_wgr_ha_`t' p_woninggroei p_onbebouwd p_huurcorp uai ib8.construction_period, r	
// 	outreg2 using output/PerWijk_${filedate}_cnt_nose_`t', excel cttop (`t') label dec(3) nose
// 	reg  ln_cnt_wgr_ha_`t' p_woninggroei p_onbebouwd p_beschermd uai ib8.construction_period, r	
// 	outreg2 using output/PerWijk_${filedate}_cnt_nose_`t', excel cttop (`t') label dec(3) nose
//	
// 	reg  ln_cnt_wgr_ha_`t' p_woninggroei p_onbebouwd p_huurcorp p_beschermd ib8.construction_period, r
// 	outreg2 using output/PerWijk_${filedate}_cnt_nose_`t', excel cttop (`t') label dec(3) nose
// 	reg  ln_cnt_wgr_ha_`t' p_woninggroei p_onbebouwd p_huurcorp p_beschermd uai ib8.construction_period, r
// 	outreg2 using output/PerWijk_${filedate}_cnt_nose_`t', excel cttop (`t') label dec(3) nose
	
	reg  ln_cnt_wgr_ha_`t' p_huurcorp uai p_beschermd p_onbebouwd p_woninggroei ib8.construction_period, r allbaselevels
	outreg2 using output/PerWijk_${filedate}_cnt_nose, excel cttop (`t') label dec(3) nose

}




//descriptives
estpost sum count_woninggroei_ha_plus cnt_wgr_ha_snnb cnt_wgr_ha_nb cnt_wgr_ha_toev cnt_wgr_ha_trfp p_huurcorp uai p_beschermd p_onbebouwd p_woninggroei bouwperiode_*  
esttab using output/sum_PerWijk_${filedate}.rtf, cells("count(fmt(0)) mean(fmt(2)) sd(fmt(2)) min(fmt(0)) max(fmt(0))") label nomtitle nonumber replace





* --------------------------------------------------------
* PCA via factoranalyse met varimax-rotatie
* Toepassing op wijkniveau met 5 ruimtelijke variabelen
* --------------------------------------------------------

* Stap 1: Factoranalyse uitvoeren met 2 factoren
factor oad p_huurcorp uai p_beschermd p_onbebouwd bouwperiode_*, factors(2)

* Stap 2: Rotatie toepassen (varimax) voor betere interpretatie
rotate, varimax

* (Optioneel) Stap 3: Bekijk geroteerde loadings
* Geeft inzicht in welke variabelen het sterkst laden op elke factor
mat load = e(L)
matlist load, format(%6.3f)

* Stap 4: Genereer scores (componentwaarden) per observatie (wijk)
* Deze nieuwe variabelen zijn lineaire combinaties van de originele variabelen
predict f1 f2

* (Optioneel) Hernoemen voor duidelijkere interpretatie
rename f1 stedelijkheid
rename f2 sociaal_profiel

* Stap 5: Regressie met gegenereerde componenten
* Hier met voorbeeld-variabele 'lnP_woninggroei' als afhankelijke variabele
regress lnP_woninggroei stedelijkheid sociaal_profiel

* (Alternatief) Regressie met woninggroei per hectare
regress count_woninggroei_ha stedelijkheid sociaal_profiel

* (Optioneel) Componentenscores visualiseren
scatter sociaal_profiel stedelijkheid, mlabel(wk_code) title("Typologie van wijken op basis van ruimtelijke dimensies")

* Einde van script
* --------------------------------------------------------











//////////////////////////////////////////////////////////////////////
**# //////////////////////// DESCRIPTIVES ////////////////////////////
//////////////////////////////////////////////////////////////////////

//descriptives
estpost sum count_* bouwjaar area oad p_huurcorp landprice d_c* p_sn_nb p_nb p_toev p_transf	
esttab using output/PerWijk_Descr_${filedate}.rtf, cells("count(fmt(0)) mean(fmt(3)) sd(fmt(3)) min(fmt(0)) max(fmt(0))") label nomtitle nonumber replace




////// PER OBJECT
global filedate = 20250226 // 20241211   20250226
import delimited Data\PerObject_Export_${filedate}.csv, clear

local replaceNullList = "pand_bouwjaar urbanisationk_rel" 
foreach x of local replaceNullList{
	replace `x' = "" if `x' == "null"
	destring `x', replace
}

save Temp/PerObject_${filedate}_raw.dta, replace

use Temp/PerObject_${filedate}_raw.dta, clear

label define type_class_label 0 "SN_Sloop" 1 "SN_Sloop_nw" 2 "SN_Nieuwbouw" 3 "Nieuwbouw" 4 "Toevoeging" 5 "Onttrekking" 6 "Transformatie_Plus"  7 "Transformatie_Min" 8 "Sloop" 9 "Onveranderd" 
label values type_class type_class_label

label define urbanisationk_label 0 "Urban" 1 "PeriUrban" 2 "Peripheral"
label values urbanisationk_rel urbanisationk_label


*** BEPAAL BOUWJAAR KLASSEN PER REDEV TYPE ***

**# STAP 1

* Maak een lege variabele voor de percentiel-klassen
g bouwjaar_klasse = .  

* Haal alle unieke waarden van type_class op
levelsof type_class, local(types)

* Loop door elke unieke type_class en bereken de percentiel-klassen
foreach t of local types {
    display "Processing type_class = `t'"
    
    * Percentiel-klassen berekenen voor deze type_class
    xtile temp_klasse = pand_bouwjaar if type_class == `t', nq(10)
    
    * Kopieer de klassen naar de definitieve variabele
    replace bouwjaar_klasse = temp_klasse if type_class == `t'
    
    * Verwijder de tijdelijke variabele om errors te voorkomen
    drop temp_klasse
}

display "Bouwjaar-klassen per type_class succesvol gegenereerd!"


**# STAP 2: Bouwjaar-grenzen per `type_class` en `bouwjaar_klasse` bepalen

* Zoek het laagste bouwjaar per combinatie van type_class en bouwjaar_klasse
bysort type_class bouwjaar_klasse (pand_bouwjaar): generate min_bouwjaar = pand_bouwjaar if _n == 1

* Zoek het hoogste bouwjaar per combinatie van type_class en bouwjaar_klasse
egen max_bouwjaar = max(pand_bouwjaar), by(type_class bouwjaar_klasse)

* Tel het aantal gebouwen per combinatie van type_class en bouwjaar_klasse
egen count = count(pand_bouwjaar), by(type_class bouwjaar_klasse)

* Toon de resultaten in een overzichtelijke lijst
list type_class bouwjaar_klasse min_bouwjaar max_bouwjaar count if min_bouwjaar != ., noobs label


**# STEP 3: Summarize and Export Only the Resulting Table to Excel

* Create a new dataset with only one row per type_class and bouwjaar_klasse
preserve  // Temporarily save the original dataset

collapse (min) min_bouwjaar=pand_bouwjaar (max) max_bouwjaar=pand_bouwjaar ///
         (count) count=pand_bouwjaar, by(type_class bouwjaar_klasse)

* Convert type_class from numeric values to string labels (if necessary)
decode type_class, gen(type_class_label)

* Export only the summarized table to an Excel file
export excel type_class_label bouwjaar_klasse min_bouwjaar max_bouwjaar count ///
    using bouwjaar_data.xlsx, replace firstrow(variables)

* Restore the original dataset (undo collapse)
restore  

* Display confirmation message
display "Summary table successfully exported to bouwjaar_data.xlsx!"





*** BEPAAL BOUWJAAR KLASSEN VOOR ALLE WAARNEMINGEN ***

**# STAP 1: Bouwjaar-klassen berekenen (8 gelijke groepen) **
xtile bouwjaar_klasse = pand_bouwjaar, nq(8)

display "Bouwjaar-klassen succesvol gegenereerd!"

**# STAP 2: Min en Max bouwjaar per klasse bepalen **

* Zoek het laagste bouwjaar per bouwjaar_klasse
egen min_bouwjaar = min(pand_bouwjaar), by(bouwjaar_klasse)

* Zoek het hoogste bouwjaar per bouwjaar_klasse
egen max_bouwjaar = max(pand_bouwjaar), by(bouwjaar_klasse)

* Tel het aantal gebouwen per bouwjaar_klasse
egen count = count(pand_bouwjaar), by(bouwjaar_klasse)

**# STAP 3: Opslaan in Excel **
preserve  
collapse (min) min_bouwjaar (max) max_bouwjaar (count) count, by(bouwjaar_klasse)

export excel bouwjaar_klasse min_bouwjaar max_bouwjaar count using bouwjaar_data_alleobs.xlsx, replace firstrow(variables)

restore  

display "Summary table successfully exported to bouwjaar_data_alleobs.xlsx!"
