use E:\Dropbox\Research\Return_Predictability_of_Earnings\data\02_only_vuolteenaho.dta,clear
*use "E:\Dropbox\Research\Return_Predictability_of_Earnings\data\vout_1_vars.dta",clear
drop if ret == .
xtset permno fyear

drop if in_vol_sample == 0

global N = 6958
macro drop myvars h_myvars x_myvars z_myvars filters
global myvars ret roe mtb
global filters if fyear >= 1954 & fyear <= 2011

keep $filters

*gen ce = cfo/at
*gen ae = ta/at
*gen ea = earn/at

label var ret "Returns"
label var roe "Profitability"
label var mtb "Market-to-Book"
*label var ea "Earnings/Assets"
*label var ce "Cash Flows/Assets"
*label var ae "Accruals/Assets"

*bysort fyear: egen weight = pc(mve), prop
gen weight = 1

*** Time de-mean data ***
* these "untransformed" variables will be used as instruments in a System GMM *
foreach v of varlist $myvars { 
egen mean_`v'=mean(`v') 
replace `v'=`v'-mean_`v' 
replace `v' = `v'*weight
drop mean_`v' 
}

*bysort permno: center ce ae ea, standardize

*** Helmert transform, create duplicate forward-differenced copies ***
keep permno fyear $myvars
helm $myvars

pvar $myvars , gmm

*** Generate X and Z variables for MATLAB ***

foreach v of varlist $myvars { 
gen x_`v'=l.h_`v'
gen z_`v'=l.`v' 
global h_myvars "$h_myvars h_`v'"
global x_myvars "$x_myvars x_`v'"
global z_myvars "$z_myvars z_`v'"
}

order permno fyear $myvars $h_myvars $x_myvars $z_myvars
saveold "D:\pvar\test.dta",replace
outsheet * using E:\Dropbox\Research\Return_Predictability_of_Earnings\data\testnew.csv, comma replace
