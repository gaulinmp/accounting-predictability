capture program drop helm
program define helm
*
* This program will do Helmert transformation for a list of variables
* NOTE: must have data tsset or xtset   
* to use enter >> helm var1 var2...
* new variables will be names with h_ in front h_var1  and so on
*
qui while "`1'"~="" {
* Check if the dataset is tsset:
qui tsset
local panelvar "`r(panelvar)'"
local timevar  "`r(timevar)'"
gsort `panelvar' -`timevar'                /*sort years descending */
tempvar one sum n m w 
capture drop h_`1'         /* If the variable exist - it will remain and not generated again */
gen `one'=1 if `1'~=.             /*generate one if x is nonmissing */
qui by `panelvar': gen `sum'=sum(`1')-`1' /*running sum without current element */
qui by `panelvar': gen `n'=sum(`one')-1     /*number of obs included in the sum */
replace `n'=. if `n'<=0             /* n=0 for last observation and =-1 if
                                   last observation is missing*/
gen `m'=`sum'/`n'                 /* m is forward mean of variable x*/
gen `w'=sqrt(`n'/(`n'+1))         /* weight on mean difference */
capture gen h_`1'=`w'*(`1'-`m')             /* transformed variable */ 
sort `panelvar' `timevar'
mac shift
}
end

