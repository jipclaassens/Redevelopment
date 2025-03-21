// Set directory Jip
cd "D:\OneDrive\OneDrive - Objectvision\VU\Projects\202008-RedevelopmentPaper"

ssc install outreg2 //install outreg2 voor het wegschrijven van regressie resultaten naar word/excel/etc.

global filedate = 20250314  // 20241211  20250226

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

// g d_constr_unknown = 0
// replace d_constr_unknown = 1 if bouwjaar == .  
// g d_constrlt1920 = 0
// replace d_constrlt1920 = 1 if bouwjaar <= 1919 & bouwjaar != .  
// g d_constr19201944 = 0 
// replace d_constr19201944 = 1 if bouwjaar >= 1920 & bouwjaar <= 1944
// g d_constr19451959 = 0 
// replace d_constr19451959 = 1 if bouwjaar >= 1945 & bouwjaar <= 1959
// g d_constr19601973 = 0 
// replace d_constr19601973 = 1 if bouwjaar >= 1960 & bouwjaar <= 1973
// g d_constr19741990 = 0 
// replace d_constr19741990 = 1 if bouwjaar >= 1974 & bouwjaar <= 1990
// g d_constr19911997 = 0 
// replace d_constr19911997 = 1 if bouwjaar >= 1991 & bouwjaar <= 1997
// g d_constrgt1997 = 0 
// replace d_constrgt1997 = 1 if bouwjaar >= 1998 & bouwjaar != .

///standard version
// g construction_period_label = ""
// replace construction_period_label = "Construction before 1920" if bouwjaar <= 1919 & bouwjaar != . 
// replace construction_period_label = "Construction 1920-1944" if bouwjaar >= 1920 & bouwjaar <= 1944
// replace construction_period_label = "Construction 1945-1959" if bouwjaar >= 1945 & bouwjaar <= 1959
// replace construction_period_label = "Construction 1960-1973" if bouwjaar >= 1960 & bouwjaar <= 1973
// replace construction_period_label = "Construction 1974-1990" if bouwjaar >= 1974 & bouwjaar <= 1990
// replace construction_period_label = "Construction 1991-1997" if bouwjaar >= 1991 & bouwjaar <= 1997
// replace construction_period_label = "Construction 1998 and later " if bouwjaar >= 1998 & bouwjaar != .
// encode construction_period_label, generate(construction_period)

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

g p_woninggroei = ((count_woon_y2024 - count_woon_y2012) / count_woon_y2024) * 100

g count_total_proces_pluschange = count_sn_nieuwbouw + count_nieuwbouw + count_toevoeging + count_transformatiep
g count_total_proces_minchange  = count_sn_sloop + count_sn_sloop_nw + count_onttrekking + count_transformatiem + count_sloop

g p_sn_nb = (count_sn_nieuwbouw / count_total_proces_pluschange) * 100
g p_nb = (count_nieuwbouw / count_total_proces_pluschange) * 100
g p_toev = (count_toevoeging / count_total_proces_pluschange) * 100
g p_transf = (count_transformatiep / count_total_proces_pluschange) * 100

// replace area = area / 1000000

g lnlandprice = ln(landprice)
// g lnOAD = ln(oad)
// g lnArea = ln(area)
g lnP_woninggroei = ln(p_woninggroei)
g p_beschermd = share_besc * 100
replace p_beschermd = 100 if p_beschermd > 100
rename mean_uai uai
replace uai = uai * 100

//plus list
local types "sn_nieuwbouw nieuwbouw toevoeging transformatiep"
foreach t of local types{ 
	g P_`t' = (count_`t' / count_total_proces_pluschange) * 100
}

//minus list
local types "sn_sloop sn_sloop_nw sloop onttrekking transformatiem"
foreach t of local types{ 
	g P_`t' = (count_`t' / count_total_proces_minchange) * 100
}

// label var area "Opp van wijk in km2"
label var oad "Gemiddelde omgevingsadressendichtheid in wijk"
label var p_huurcorp "Percentage huurcorporatie woningen in wijk"
label var landprice "Gemiddelde residuele grondwaarde in 2007 in wijk"
label var bouwjaar "Gemiddelde bouwjaar in 2012 in wijk"
// label var count_woon_y2012 "Aantal woningen in 2012 in wijk"
// label var count_woon_y2024 "Aantal woningen in 2024 in wijk"
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
// label var d_constr_unknown "Gem. bouwjaar in 2012 onbekend"
// label var d_constrlt1920 "Gem. bouwjaar in 2012 voor 1920"
// label var d_constr19201944 "Gem. bouwjaar in 2012 tussen 1920-1944"
// label var d_constr19451959 "Gem. bouwjaar in 2012 tussen 1945-1959"
// label var d_constr19601973 "Gem. bouwjaar in 2012 tussen 1960-1973"
// label var d_constr19741990 "Gem. bouwjaar in 2012 tussen 1974-1990"
// label var d_constr19911997 "Gem. bouwjaar in 2012 tussen 1991-1997"
// label var d_constrgt1997 "Gem. bouwjaar in 2012 na 1997"

label var p_woninggroei "Percentage woninggroei tussen 2012-2024 in wijk"
label var p_sn_nb "Percentage sloop-nieuwbouw van totale positieve verandering"
label var p_nb "Percentage nieuwbouw van totale positieve verandering"
label var p_toev "Percentage toevoeging van totale positieve verandering"
label var p_transf "Percentage transformatie van totale positieve verandering"
label var lnP_woninggroei "log (Percentage woninggroei tussen 2012-2024 in wijk)"
label var lnlandprice "log (Gemiddelde residuele grondwaarde in 2007 in wijk)"
label var uai "Gemiddelde urban attractivity index in 2012 in wijk"
label var p_groei_woon "Percentage woninggroei tussen 2012-2024 in provincie"
label var p_beschermd "Percentage oppervlak beschermd stad- en dorpsgezicht in wijk"

drop wk_code areamegameter2 count_woon_y2012 count_woon_y2024 count_sn_sloop count_sn_sloop_nw count_sn_nieuwbouw count_nieuwbouw count_toevoeging count_onttrekking count_transformatiep count_transformatiem count_sloop count_onveranderd count_total_process provincie_rel opp_beschermdestaddorpgezichtenm share_beschermdestaddorpgezichte  count_total_proces_pluschange count_total_proces_minchange

//////////////////////////////////////////////////////////////////////
**# ////////////////////////// ANALYSES //////////////////////////////
//////////////////////////////////////////////////////////////////////

pwcorr lnP_woninggroei oad p_huurcorp lnlandprice p_beschermd uai
pwcorr p_woninggroei oad p_huurcorp landprice p_beschermd uai
pwcorr lnP_woninggroei p_huurcorp lnlandprice uai
pwcorr lnP_woninggroei oad p_huurcorp p_beschermd uai

fvset base 7 construction_period  //1 is oud, 7 in nieuwe opzet na 2009

// local types "sn_nieuwbouw nieuwbouw toevoeging transformatiep sn_sloop sn_sloop_nw sloop onttrekking transformatiem"
local types "sn_nieuwbouw nieuwbouw toevoeging transformatiep"
foreach t of local types{ 
    display ""
    display ""
    display "---------------------------------------------"
    display "---------------------------------------------"
    display "-- Regressing redev type = `t' --"
    display "---------------------------------------------"
    display "---------------------------------------------"
	reg  P_`t' lnP_woninggroei lnlandprice, r	
	outreg2 using output/PerWijk_${filedate}_nose_`t', excel cttop (`t') label dec(3) nose
	reg  P_`t' lnP_woninggroei p_huurcorp, r	
	outreg2 using output/PerWijk_${filedate}_nose_`t', excel cttop (`t') label dec(3) nose
	reg  P_`t' lnP_woninggroei uai, r	
	outreg2 using output/PerWijk_${filedate}_nose_`t', excel cttop (`t') label dec(3) nose
	reg  P_`t' lnP_woninggroei p_beschermd, r	
	outreg2 using output/PerWijk_${filedate}_nose_`t', excel cttop (`t') label dec(3) nose
	reg  P_`t' lnP_woninggroei i.construction_period, r	
	outreg2 using output/PerWijk_${filedate}_nose_`t', excel cttop (`t') label dec(3) nose
	
	reg  P_`t' lnP_woninggroei lnlandprice i.construction_period, r	
	outreg2 using output/PerWijk_${filedate}_nose_`t', excel cttop (`t') label dec(3) nose
	reg  P_`t' lnP_woninggroei p_huurcorp i.construction_period, r	
	outreg2 using output/PerWijk_${filedate}_nose_`t', excel cttop (`t') label dec(3) nose
	reg  P_`t' lnP_woninggroei uai i.construction_period, r	
	outreg2 using output/PerWijk_${filedate}_nose_`t', excel cttop (`t') label dec(3) nose
	reg  P_`t' lnP_woninggroei p_beschermd i.construction_period, r	
	outreg2 using output/PerWijk_${filedate}_nose_`t', excel cttop (`t') label dec(3) nose
	
	reg  P_`t' lnP_woninggroei lnlandprice uai i.construction_period, r	
	outreg2 using output/PerWijk_${filedate}_nose_`t', excel cttop (`t') label dec(3) nose
	reg  P_`t' lnP_woninggroei p_huurcorp lnlandprice uai i.construction_period, r	
	outreg2 using output/PerWijk_${filedate}_nose_`t', excel cttop (`t') label dec(3) nose
	reg  P_`t' lnP_woninggroei lnlandprice p_beschermd uai i.construction_period, r	
	outreg2 using output/PerWijk_${filedate}_nose_`t', excel cttop (`t') label dec(3) nose
	
	reg  P_`t' lnP_woninggroei p_huurcorp lnlandprice p_beschermd i.construction_period, r
	outreg2 using output/PerWijk_${filedate}_nose_`t', excel cttop (`t') label dec(3) nose
	reg  P_`t' lnP_woninggroei oad p_huurcorp lnlandprice p_beschermd uai i.construction_period, r
	outreg2 using output/PerWijk_${filedate}_nose_`t', excel cttop (`t') label dec(3) nose
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
