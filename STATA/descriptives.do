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
