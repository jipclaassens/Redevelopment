// Set directory Jip
cd "D:\OneDrive\OneDrive - Objectvision\VU\Projects\202008-RedevelopmentPaper"

ssc install outreg2 //install outreg2 voor het wegschrijven van regressie resultaten naar word/excel/etc.

**# Bookmark #1
import delimited Data\Redevelopment_Objecten_20231215.csv, clear

capture mkdir Temp
save Temp/RedevData_raw.dta, replace

// ==================================================== //
// ===============  DATA PREPERATION  ================= //
// ==================================================== //

use Temp/RedevData_raw.dta, clear

// drop geometry 

// local replaceTrueFalseList = "mutatiemaand urbanisationk_rel"
// foreach x of local replaceTrueFalseList{
// 	replace `x' = "1" if `x' == "TRUE" | `x' == "True" | `x' == "'TRUE'" | `x' == "'True'"
// 	replace `x' = "0" if `x' == "FALSE" | `x' == "" | `x' == "False" | `x' == "'FALSE'" | `x' == "'False'"
// 	destring `x', replace
// }

local replaceNullList = "mutatiemaand urbanisationk_rel " 
foreach x of local replaceNullList{
	replace `x' = "" if `x' == "null"
	destring `x', replace
}

// encode aggl_name, generate(aggl_rel)

// rename n_count_vbo_woon_voorraa n_cnt_vbow_voorr_in_pand
// rename n_count_vbo_niet_woon_voorraad_i n_cnt_vbonw_voorr_in_pand

// label define aggl_rel_label 1 "No Aggl" 2 "Amersfoort" 3 "Amsterdam"  4 "Apeldoorn" 5 "Arnhem" 6 "Breda" 7 "Den Bosch" 8 "Den Haag" 9 "Dordrecht" 10 "Eindhoven" 11 "Enschede" 12 "Groningen" 13 "Haarlem" 14 "Heerlen" 15 "Leeuwarden" 16 "Leiden" 17 "Maastricht" 18 "Nijmegen" 19 "Rotterdam" 20 "Sittard Geleen" 21 "Tilburg" 22 "Utrecht" 23 "Zwolle"
// label values aggl_rel aggl_rel_label

label define type_class_label 0 "SN_Sloop" 1 "SN_Nieuwbouw" 2 "Toevoeging" 3 "Transformatie" 4 "Onttrekking" 5 "Onveranderd" 6 "Nieuwbouw_OpBebouwd" 7 "Nieuwbouw_OpOnbebouwd" 
label values type_class site_type_class_label

label define urbanisationk_label 0 "Urban" 1 "PeriUrban" 2 "Peripheral"
label values urbanisationk_rel urbanisationk_label

save Temp/RedevData_clean.dta, replace

// ==================================================== //
// =================== PER PROCESS ==================== //
// ==================================================== //

use Temp/RedevData_clean.dta, clear

tab type_class
keep if site_type_class==0 // == SN woon-woon

bysort site_id: egen vbo_nieuw=mode(vbo_mutatiejaar), minmode missing
label var site_modus_mutatiejaar "Modus mutatie jaar van site"


tab

