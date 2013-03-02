cd D:\Dropbox\Documents\School\Projects\Return_Predictability_of_Earnings
use data/04_accdata.dta,clear
drop if ret == .
xtset permno fyear

gen ce = cfo_bs/at
gen ae = ta_bs/at
gen ea = e_bs/at

drop if in_vol_sample == 0


*bysort fyear: egen weight = pc(mve), prop
gen weight = 1

*** Time de-mean data ***
* these "untransformed" variables will be used as instruments in a System GMM *
foreach v of varlist ret mtb roe ce ae ea { 
egen mean_`v'=mean(`v') 
replace `v'=`v'-mean_`v' 
replace `v' = `v'*weight
drop mean_`v' 
}

bysort permno: center ce ae ea, standardize

*** Helmert transform, create duplicate forward-differenced copies ***
helm roe mtb ret ce ae ea

*pvar ret roe mtb , gmm

*** Generate X and Z variables for MATLAB ***
foreach v of varlist ret mtb roe ce ae { 
gen x_`v'=l.h_`v' 
gen z_`v'=l.`v' 
}

keep permno fyear ret roe mtb h_ret h_roe h_mtb h_ce h_ae x_ret x_roe x_mtb x_ce x_ae z_ret z_roe z_mtb z_ce z_ae
order permno fyear ret roe mtb h_ret h_roe h_mtb h_ce h_ae x_ret x_roe x_mtb x_ce x_ae z_ret z_roe z_mtb z_ce z_ae
*saveold "D:\pvar\test.dta",replace
outsheet * using D:/SAS/testnew.csv, comma replace
