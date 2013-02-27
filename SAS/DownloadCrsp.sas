libname negwatch 'F:\SAS\Programs\Ioannis\NegWatch';

%WRDS("open");
rsubmit;

/*change to another sastemp if you borrow my code*/
libname out '/sastemp4'; 

/*Pull data from CRSP, including the SIC, Exchange, and Sharecodes for */
proc sql;
	create table crspX0 as
	select Distinct a.Permno, a.date, b.SICCD, b.EXCHCD, b.SHRCD, a.CUSIP,
	a.RET, abs(a.PRC) as PRC, a.SHROUT, abs(a.PRC)*a.SHROUT/1000 as ME, a.Vol
	from crsp.msf as a inner join crsp.mseexchdates as b
	on a.permno = b.permno and a.DATE between b.namedt and b.nameendt
	Order by a.Permno, a.Date;
quit;
/*Start of Code from Gustato Grullon*/
* Make extract from CRSP delisting table for delisting returns;
data dlistreturn (keep=permno dlret);
set crsp.mse;
where (event = "DELIST" and dlstcd > 100);
if dlret = .S or dlret = .T then dlret=-0.55;

* Merges CRSP returns info with delisting info;
data crspX1 (Keep = permno date SICCD EXCHCD SHRCD ret PRC SHROUT ME Vol CUSIP);
merge crspX0 (in=inkeep) dlistreturn (in=indlist);
by permno;
if inkeep;
if (last.permno=1 and indlist=1 and dlret > .Z  and ret > .Z) then ret = (1+ret)*(1+dlret)-1;
if (last.permno=1 and indlist=1 and dlret > .Z  and ret le .Z) then ret =dlret;
run;
/*End of code of Gustavo Grullon*/

/*Creates MEt_1 and stuff for convenience when calculating value weighted returns*/
data CrspRet;
Set crspX1;
*where PRC >.Z ;
by Permno Date;
MEt_1=lag(ME);
PRCt_1=lag(PRC);
SHROUTt_1=lag(SHROUT);
*if ret le .Z then delete;
*if first.permno then delete;
run;
proc download data=CrspRet out=negwatch.CrspRet;
run;

endrsubmit;
%WRDS("close");
