use E:\Dropbox\Return_Predictability_of_Earnings\data\02_accdata.dta,clear
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

estimates clear
quietly: estpost summ ret roe mtb ce ae,det
esttab, cells("count(fmt(%9.0fc) label(N)) mean(fmt(a2) label(Mean)) sd(fmt(a2) label(SD)) min(fmt(a2) label(Min)) p50(fmt(a2) label(Med.)) max(fmt(a2) label(Max))") ///
	nomtitle nonumber noobs booktabs label ///
	title(Summary Statistics.)

quietly: corr ret roe mtb ce ae
mat R = r(C)
mata
L = lowertriangle(st_matrix("R"))
r = rows(L)
c = cols(L)
U = uppertriangle(J(r,c,.))
A = L + U
st_replacematrix("R",A)
end

local nrows = rowsof(R)
forvalues i = 1/`nrows' {
	local pvar = "`: word `i' of `: rownames R''"
	quietly: corr `pvar' l.`pvar'
	matrix R[`i',`i'] = r(rho)
}

esttab matrix(R, fmt(a2)), nomtitle compress  booktabs ///
	title(Correlations.)

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
eststo: qui cluster2 ret L_ret L_roe L_mtb  ,nocons fcluster(permno) tcluster(fyear)
eststo: qui cluster2 roe L_ret L_roe L_mtb ,nocons fcluster(permno) tcluster(fyear)
eststo: qui cluster2 mtb L_ret L_roe L_mtb ,nocons fcluster(permno) tcluster(fyear)

esttab, se(a2) star(* 0.10 ** 0.05 *** 0.01) stats(r2 N, fmt(a2 %18.0gc) labels("$ R^2 $" "Obs.")) /// 
append  compress nomtitles label booktabs  ///
title("Pooled OLS Forecasting Regressions.")

*** Helmert transform, create duplicate forward-differenced copies ***
helm roe mtb ret ce ae ea

pvar ret roe mtb ce ae , gmm gr_imp

*** Generate X and Z variables for MATLAB ***
foreach v of varlist ret mtb roe ce ae { 
gen x_`v'=l.h_`v' 
gen z_`v'=l.`v' 
}

keep permno fyear ret roe mtb h_ret h_roe h_mtb h_ce h_ae x_ret x_roe x_mtb x_ce x_ae z_ret z_roe z_mtb z_ce z_ae
order permno fyear ret roe mtb h_ret h_roe h_mtb h_ce h_ae x_ret x_roe x_mtb x_ce x_ae z_ret z_roe z_mtb z_ce z_ae
saveold "D:\pvar\test.dta",replace
