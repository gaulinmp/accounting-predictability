cd D:\Dropbox\Documents\School\Projects\Return_Predictability_of_Earnings
use data/02_accdata.dta,clear
drop if ret == .
xtset permno fyear

drop if in_vol_sample == 0


gen ce = cfo/at
gen ae = ta/at
gen ea = earn/at

label var ret "Returns"
label var roe "Profitability"
label var mtb "Market-to-Book"
label var ce "Cash Flows/Assets"
label var ae "Accruals/Assets"

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

gen L_ret = l.ret
gen L_roe = l.roe
gen L_mtb = l.mtb
label var L_ret "$ r_t $"
label var L_roe "$ e_t $"
label var L_mtb "$ mb_t $"

*** Naive OLS ***
sort permno fyear
estimates clear
eststo: qui cluster2 ret L_ret L_roe L_mtb  , fcluster(permno) tcluster(fyear)
eststo: qui cluster2 roe L_ret L_roe L_mtb , fcluster(permno) tcluster(fyear)
eststo: qui cluster2 mtb L_ret L_roe L_mtb , fcluster(permno) tcluster(fyear)

esttab, se(a2) star(* 0.10 ** 0.05 *** 0.01) stats(r2 N, fmt(a2 %18.0gc) labels("$ R^2 $" "Obs.")) /// 
append  compress nomtitles label ///
title("Pooled OLS Forecasting Regressions.")
