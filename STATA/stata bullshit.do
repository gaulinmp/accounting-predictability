use E:\Dropbox\Return_Predictability_of_Earnings\data\02_accdata.dta,clear
drop if ret == .
xtset permno fyear

drop if in_vol_sample == 0

global N = 6958

gen ce = cfo/at
gen ae = ta/at
gen ea = earn/at

label var ret "Returns"
label var roe "Profitability"
label var mtb "Market-to-Book"
label var ea "Earnings/Assets"
label var ce "Cash Flows/Assets"
label var ae "Accruals/Assets"

local myvars ret roe mtb

*bysort fyear: egen weight = pc(mve), prop
gen weight = 1

*** Time de-mean data ***
* these "untransformed" variables will be used as instruments in a System GMM *
foreach v of varlist `myvars' { 
egen mean_`v'=mean(`v') 
replace `v'=`v'-mean_`v' 
replace `v' = `v'*weight
drop mean_`v' 
}

bysort permno: center ce ae ea, standardize

*** Helmert transform, create duplicate forward-differenced copies ***
keep permno fyear `myvars'
helm `myvars'

*pvar `myvars' , gmm

*** Generate X and Z variables for MATLAB ***

foreach v of varlist `myvars' { 
gen x_`v'=l.h_`v'
local x_myvars = "`x_myvars' x_`v'"
gen z_`v'=l.`v' 
}

order permno fyear `myvars' h_* x_* z_*
*saveold "D:\pvar\test.dta",replace
