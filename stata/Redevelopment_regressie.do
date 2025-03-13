// Set directory Jip
cd "D:\OneDrive\OneDrive - Objectvision\VU\Projects\202008-RedevelopmentPaper"

ssc install outreg2 //install outreg2 voor het wegschrijven van regressie resultaten naar word/excel/etc.

global filedate = 20250226  // 20241211  20250226

import delimited Data\Analyse_PerWijk_${filedate}.csv, clear
// ==================================================== //
// ===============  DATA PREPERATION  ================= //
// ==================================================== //

local replaceNullList = "oad p_huurcorp landprice modus_buildingyear_2012" 
foreach x of local replaceNullList{
	replace `x' = "" if `x' == "null"
	destring `x', replace
}

rename modus_buildingyear_2012 bouwjaar

g d_constr_unknown = 0
replace d_constr_unknown = 1 if bouwjaar == .  
g d_constrlt1920 = 0
replace d_constrlt1920 = 1 if bouwjaar <= 1919 & bouwjaar != .  
g d_constr19201944 = 0 
replace d_constr19201944 = 1 if bouwjaar >= 1920 & bouwjaar <= 1944
g d_constr19451959 = 0 
replace d_constr19451959 = 1 if bouwjaar >= 1945 & bouwjaar <= 1959
g d_constr19601973 = 0 
replace d_constr19601973 = 1 if bouwjaar >= 1960 & bouwjaar <= 1973
g d_constr19741990 = 0 
replace d_constr19741990 = 1 if bouwjaar >= 1974 & bouwjaar <= 1990
g d_constr19911997 = 0 
replace d_constr19911997 = 1 if bouwjaar >= 1991 & bouwjaar <= 1997
g d_constrgt1997 = 0 
replace d_constrgt1997 = 1 if bouwjaar >= 1998 & bouwjaar != .

g construction_period_label = ""
replace construction_period_label = "Construction before 1920" if d_constrlt1920 == 1
replace construction_period_label = "Construction between 1920 and 1944" if d_constr19201944 == 1
replace construction_period_label = "Construction between 1945 and 1959" if d_constr19451959 == 1
replace construction_period_label = "Construction between 1960 and 1973" if d_constr19601973 == 1
replace construction_period_label = "Construction between 1974 and 1990" if d_constr19741990 == 1
replace construction_period_label = "Construction between 1991 and 1997" if d_constr19911997 == 1
replace construction_period_label = "Construction after 1998" if d_constrgt1997 == 1
replace construction_period_label = "Construction unknown" if d_constr_unknown == 1
encode construction_period_label, generate(construction_period)

// drop d_c*

label var area "Opp van wijk in km2"
label var oad "Gemiddelde omgevingsadressendichtheid in wijk"
label var p_huurcorp "Percentage huurcorporatie woningen in wijk"
label var landprice "Gemiddelde residuele grondwaarde in 2007 in wijk"
label var bouwjaar "Gemiddelde bouwjaar in 2012 in wijk"
label var count_woon_y2012 "Aantal woningen in 2012 in wijk"
label var count_woon_y2024 "Aantal woningen in 2024 in wijk"
label var count_sn_sloop "Aantal gesloopte woningen via sloop-nieuwbouw"
label var count_sn_sloop_nw "Aantal gesloopte niet-woningen via sloop-nieuwbouw"
label var count_sn_nieuwbouw "Aantal nieuw gebouwde woningen via sloop-nieuwbouw"
label var count_toevoeging "Aantal toegevoegde woningen via toevoeging"
label var count_onttrekking "Aantal onttrokken woningen via onttrekking"
label var count_transformatiem "Aantal onttrokken woningen via transformatie"
label var count_transformatiep "Aantal toegevoegde woningen via transformatie"
label var count_nieuwbouw "Aantal nieuw gebouwde woningen zonder opvolgende sloop"
label var count_sloop "Aantal gesloopte woningen zonder opvolgende nieuwbouw"
label var count_onveranderd "Aantal onveranderde woningen"
label var d_constr_unknown "Gem. bouwjaar in 2012 onbekend"
label var d_constrlt1920 "Gem. bouwjaar in 2012 voor 1920"
label var d_constr19201944 "Gem. bouwjaar in 2012 tussen 1920-1944"
label var d_constr19451959 "Gem. bouwjaar in 2012 tussen 1945-1959"
label var d_constr19601973 "Gem. bouwjaar in 2012 tussen 1960-1973"
label var d_constr19741990 "Gem. bouwjaar in 2012 tussen 1974-1990"
label var d_constr19911997 "Gem. bouwjaar in 2012 tussen 1991-1997"
label var d_constrgt1997 "Gem. bouwjaar in 2012 na 1997"

g p_growth = ((count_woon_y2024 - count_woon_y2012) / count_woon_y2024) * 100

g count_total_proces_pluschange = count_sn_nieuwbouw + count_nieuwbouw + count_toevoeging + count_transformatiep
g count_total_proces_minchange  = count_sn_sloop + count_sn_sloop_nw + count_onttrekking + count_transformatiem + count_sloop

g p_sn_nb = (count_sn_nieuwbouw / count_total_proces_pluschange) * 100
g p_nb = (count_nieuwbouw / count_total_proces_pluschange) * 100
g p_toev = (count_toevoeging / count_total_proces_pluschange) * 100
g p_transf = (count_transformatiep / count_total_proces_pluschange) * 100

replace area = area / 1000000

g lnlandprice = ln(landprice)
g lnOAD = ln(oad)
g lnArea = ln(area)
g lnGrowth = ln(p_growth)

label var p_growth "Percentage woninggroei tussen 2012-2024"
label var p_sn_nb "Percentage sloop-nieuwbouw van totale positieve verandering"
label var p_nb "Percentage nieuwbouw van totale positieve verandering"
label var p_toev "Percentage toevoeging van totale positieve verandering"
label var p_transf "Percentage transformatie van totale positieve verandering"

//////////////////////////////////////////////////////////////////////
**# ////////////////////////// ANALYSES //////////////////////////////
//////////////////////////////////////////////////////////////////////


fvset base 1 construction_period

local types "sn_nieuwbouw nieuwbouw toevoeging transformatiep"
foreach t of local types{ 
    display "Regressing redev type = `t'"
	g p = (count_`t' / count_total_proces_pluschange) * 100
	reg  p lnGrowth oad p_huurcorp lnlandprice p_groei_woon opp_besc mean_uai, r

// 	outreg2 using output/PerWijk_${filedate}, excel cttop (`t') label dec(3)
	drop p
}

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