DM 'output;clear;log;clear;';

/* Remote Sign-on Header */
%RSUBMIT(dir="/sastemp7/eh7");
ENDRSUBMIT;
%INCLUDE "E:\Dropbox\ssh\wrds_pass.sas";
%LET wrds=wrds.wharton.upenn.edu 4016;
options comamid=TCP remote=WRDS;
signon username="eddyhu" password="&wrds_pass";


/* Modified RSUBMIT command which makes sure directory is there */
/* Also clears the log*/
%MACRO RSUBMIT(dir=);
DM 'output;clear;log;clear;';
%syslput remote_dir=&dir;

RSUBMIT;

/* Check if directory exists on the remote server and if not create it and set the library */
%MACRO chk_dir(dir=) ;
	%LOCAL rc fileref ; 
	%LET rc = %SYSFUNC(filename(fileref,&remote_dir)) ; 
	%IF %SYSFUNC(fexist(&fileref))  %THEN 
		%PUT NOTE: The directory "&remote_dir" exists ; 
	%ELSE 
	%DO ; 
	%SYSEXEC mkdir   &remote_dir ; 
	%PUT %SYSFUNC(sysmsg()) The directory has been created. ; 
	%END ; 
	%LET rc=%SYSFUNC(filename(fileref)) ; 
	libname out &remote_dir;
%MEND chk_dir ; 	

%chk_dir(dir=&remote_dir);

%MEND RSUBMIT;

%RSUBMIT(dir="/sastemp7/eh7");

/* Year Range */
%LET FIRST = 1965;
%LET LAST = 2011;

/* CRSP Returns */
%LET crsp_rets = a.PERMNO, a.DATE, b.SICCD, b.EXCHCD, b.SHRCD, a.RET;
proc sql;
	create table out.crsp_rets as
	select &crsp_rets
	from crsp.msf as a
	inner join crsp.mseexchdates as b
	on a.PERMNO = b.PERMNO and a.DATE between b.NAMEDT and b.NAMEENDT
	and year(date) between &FIRST and &LAST
	where SICCD not between 6000 and 6999 and EXCHCD in (1,2,3) and SHRCD in (10,11)
	order by a.PERMNO, a.DATE;
	;
quit;

/* Make extract from CRSP delisting table for delisting returns */
data dlistreturn (keep=PERMNO DLRET);
	set crsp.mse;
	where (event = "DELIST" and dlstcd > 100);
	if dlret = .S or dlret = .T then dlret=-0.55;
run;

/* Merge CRSP returns info with delisting info; */
data out.crsp_rets (keep = PERMNO DATE SICCD EXCHCD SHRCD RET);
	merge out.crsp_rets (in=INKEEP) dlistreturn (in=INDLIST);
	by PERMNO;
	if INKEEP;
	if (last.PERMNO=1 and INDLIST=1 and DLRET > .Z  and RET > .Z) then RET = (1+RET)*(1+DLRET)-1;
	if (last.PERMNO=1 and INDLIST=1 and DLRET > .Z  and RET le .Z) then RET=DLRET;
run;

/* CRSP Characteristics */
%LET crsp_chars = PERMNO, DATE, RET, abs(PRC) as PRC, SHROUT, abs(PRC)*SHROUT/1000 as ME;
proc sql;
	create table out.crsp_chars as
	select &crsp_chars
	from crsp.msf
	where year(date) between &FIRST and &LAST
	order by PERMNO, DATE;
	;
quit;

ENDRSUBMIT;
%RSUBMIT(dir="/sastemp7/eh7");

/* Calculate momentum from CRSP extract */
proc expand data=out.crsp_chars(keep=permno date ret) out=out.mom;
	by permno;
	convert RET = MOM / transform = (+1 movprod 11 -1 trimleft 10);
run;

/* Calculate monthly volatilities from DSF */
proc expand data=crsp.dsf(keep=permno date ret) out=out.vol method = none;
	by permno;
	convert RET = VOL / transformout = (movstd 60 trimleft 59);
	id DATE;
run;

ENDRSUBMIT;

%RSUBMIT(dir="/sastemp7/eh7")

/* Merge volatility into characterstics */
proc sql;
	create table out.crsp_chars as
	select a.*, b.VOL 
	from out.crsp_chars as a
	left join out.vol as b
	on a.PERMNO = b.PERMNO 
	and a.DATE = b.DATE
	;
quit;

/* Merge in momentum */
proc sql;
	create table out.crsp_chars as
	select a.*, b.MOM 
	from out.crsp_chars as a
	left join out.mom as b
	on a.PERMNO = b.PERMNO 
	and intnx('month',a.DATE,0,'E') = intnx('month',b.DATE,1,'E')
	;
quit;

/* Merge in characterstics */
proc sql;
	create table out.crspx as
	select a.PERMNO, a.DATE, a.RET, b.PRC, b.SHROUT, b.ME, b.VOL, b.MOM
	from out.crsp_rets as a
	left join
	out.crsp_chars as b
	on a.PERMNO = b.PERMNO
	and intnx('month',a.DATE,0,'E') = intnx('month',b.DATE,1,'E')
	order by a.PERMNO, a.DATE
	;
quit;

ENDRSUBMIT;

%RSUBMIT(dir="/sastemp7/eh7");
/* Download n obs */
proc download data=out.crspx(obs=max) out=crspx;
run;
ENDRSUBMIT;

%RSUBMIT(dir="/sastemp7/eh7");
/* COMPUSTAT Variables */
%LET comp_vars = GVKEY INDFMT DATAFMT POPSRC CONSOL CSHPRI PRCC_F DVPSX_F SALE DATADATE SEQ CEQ 
	TXDITC TXDB PSTKRV PSTK PSTKL AT PPEGT PPENT NI CHE XOPR XINT LT DLTT DLC XRD XAD WCAP IB INVT GP REVT COGS;

/* First COMPUSTAT extract with beginning & end dates for fiscal years */
data out.compx(genmax=5);
	set comp.funda(keep=&comp_vars);
	if indfmt='INDL' and datafmt='STD' and popsrc='D' and consol='C';
	drop datafmt popsrc consol;  * Only used for the screening; 
	* create begin and end dates for fiscal year;
	endyr=datadate; format endyr date9.;
	begyr=intnx('month',endyr,-11,'beg'); format begyr date9.; 
	*intnx(interval, from, n, 'aligment');
run;

/* Merge COMPUSTAT extract with CRSP/COMP linking table */
proc sql;
	create table out.compx as 
	select
		distinct a.GVKEY, b.LPERMNO as PERMNO, a.DATADATE,
		(CSHPRI*PRCC_F) as ME,
		coalesce(PSTKRV,PSTKL,PSTK,0) as PS,
		coalesce(TXDITC, TXDB,0) as DEFTAX,
		case when SEQ is not null then SEQ 
		when CEQ is not null and PSTK is not null then CEQ + PSTK
		when AT is not null and LT is not null then AT-LT else -999 end as SHE,
		case when calculated SHE > -999 then calculated SHE + Calculated DEFTAX - calculated PS else -999 end as BE,
		*
	from out.compx as a, crsp.ccmxpf_linktable as b
	where a.gvkey = b.gvkey and
	b.LINKTYPE in ("LU","LC","LD","LF","LN","LO","LS","LX")and
	b.usedflag=1 and
	(b.LINKDT <= a.endyr or b.LINKDT = .B) and (a.endyr <= b.LINKENDDT or b.LINKENDDT = .E)
	group by b.LPERMNO, year(a.DATADATE)
    having max(a.DATADATE)=a.DATADATE
	;
quit;

/* Merge CRSP Header Info */
proc sql;
	create table out.compx as
	select a.GVKEY, a.PERMNO, a.DATADATE,
	coalesce(input(c.SIC, 11.),b.SICCD) as SICH,
	b.SHRCD, b.EXCHCD,
	*
	from out.compx as a left outer join crsp.mseexchdates as b 
	on a.PERMNO = b.PERMNO and a.DATADATE between b.NAMEDT and b.NAMEENDT
	left outer join comp.names as c ON a.GVKEY = c.GVKEY
	order by PERMNO, DATADATE;
quit;

proc expand data=out.compx out=out.compx;
	by permno;
	convert datadate = datadate_next / transform = (lead 1);
run;

proc sql;
	create table out.compx as
	select *, coalesce(intck('month',datadate,datadate_next),12) as month_diff from out.compx
	;
quit;

ENDRSUBMIT;

%RSUBMIT(dir="/sastemp7/eh7");
/* Download n obs */
proc download data=out.compx(obs=max) out=compx;
run;
ENDRSUBMIT;

/* Calculate inter-temporal variables */
proc expand data=risky.compx out=compx_f;
	by permno;
	convert PPEGT = DPPEGT / transform = (DIF);
	convert INVT = DINVT / transform = (DIF);
	convert AT = LAT / transform = (LAG 1);
run;

/* Everything is done locally from now on for speed */
/* Align Compustat variables and apply standard filters */
/* Wait = 6, financial data becomes available after 6 months */
/* Exclude financials SICH = 6000 and 6999 */
/* Keep only 3 primary exchanges 1-3 */
/* Only use common stock 10-11 */
%LET wait=6;
data compx_f2;
retain permno date date_wait;
set compx_f;
where sich not between 6000 and 6999 and exchcd in (1,2,3) and shrcd in (10,11);
if BE <=0 then delete;
do i = 1 to month_diff;
      date = intnx('month',datadate,i,'E');
	  date_wait = intnx('month',date,&wait,'E');
	  output;
end;
format date date_wait mmddyy10.;
run;

DM 'output;clear;log;clear;';
/* Merge CRSP and COMPUSTAT */
/* Push CRSP dates forward one month to avoid survivorship bias */
proc sql;
	create table mydata as select *
	from risky.crspx as a left join compx_f2 as b
	on a.PERMNO = b.PERMNO 
	and intnx('month',a.DATE,0,'E') = b.DATE_WAIT
	;
quit;

/* Yamil's filter which requires 37 days of returns data on a rolling window basis */
proc expand data=mydata out=mydata2(where=(RET37>.));
	by permno;
	convert RET=RET37 / transform = (+1 NOMISS MOVPROD 37 -1);
run;

DM 'output;clear;log;clear;';
/* Merged Variables */
%LET merged_vars = PERMNO, DATE, 
	RET, RET as RET_WIN,
	log(VOL) as VOL LABEL='Log Volatility', 
	log(1+MOM) as MOM LABEL='Log Momentum',
	DVPSX_F/PRC as DY LABEL='Dividend Yield',
	ME LABEL='Market Equity', 
	log(ME) as log_ME LABEL='Log Market Equity', 
	log(BE/ME) as BMR LABEL='Book to Market', 
	(SALE-COGS)/AT as ROA LABEL='Gross Profits to Assets', 
	(DPPEGT+DINVT)/LAT as IA LABEL='Investment to Assets', 
	DLTT/AT as LTDA LABEL='Long-Term Debt to Assets', 
	DLC/AT as STDA LABEL='Short-Term Debt to Assets';

/* Extract only relevant variables from the merged set */
proc sql;
	create table mydata2 as
	select &merged_vars, exchcd as HEXCD
	from mydata2
	;
quit;

proc sql;
	create table mydata2 as
	select * from mydata2
	where RET > .
	and VOL > .
	and MOM > .
	and DY > .
	and log_ME > .
	and BMR > .
	and ROA > .
	and IA > .
	and LTDA > .
	and STDA > .;
quit;

/* Truncate by NYSE 20% Market cap by month */
%INCLUDE "E:\Dropbox\Research\STOCK CODE\nyse20.sas";
%Truncate(dsetin = mydata2, dsetout = mydata2, byvar = DATE, vars = ME,pctl = 20, nyse = y);
run;quit;

proc sql;
	create table mydata2 as
	select * from mydata2
	where ME NE .T
	;
quit;

/* Winsorize by month */
%INCLUDE "E:\Dropbox\Research\STOCK CODE\WINSORIZE_TRUNCATE.sas";
%Winsorize_Truncate(dsetin = mydata2, dsetout = risky.mydata, byvar = none, vars = ret_win vol mom me log_me dy bmr roa ia ltda stda, type = W, pctl = 1 99) 

/* Run Stat Transfer now */

************************************************************************************************************;

proc sql;
	create table risky.yamildata as
	select permno, date, ret, ret as ret_win, logme as log_me, me, logmom11 as mom, logvol as vol, logbm as bmr, gpa as roa, ia, DY, DLT as ltda, DST as stda
	from risky.samplebig
	;
quit;

proc sql;
	select count(*) from mydata3
	where RET > .
	and VOL > .
	and MOM > .
	and DY > .
	and log_ME > .
	and BMR > .
	and ROA > .
	and IA > .
	and LTDA > .
	and STDA > .;
quit;

proc sql;
	select count(*) from mydata3
	where ME = .T;
quit;



/* Standardized Variables */
%LET std_vars = PERMNO, DATE, 
	(RET - mean(RET))/std(RET) as RET LABEL='Returns', 
	(VOL - mean(VOL))/std(VOL) as VOL LABEL='Volatility', 
	(MOM - mean(MOM))/std(MOM) as MOM LABEL='Momentum', 
	(DY - mean(DY))/std(DY) as DY LABEL='Dividend Yield', 
	(log_ME - mean(log_ME))/std(log_ME) as log_ME LABEL='Log Market Equity', 
	(BMR - mean(BMR))/std(BMR) as BMR LABEL='Book to Market', 
	(ROA - mean(ROA))/std(ROA) as ROA LABEL='Gross Profits to Assets', 
	(IA - mean(IA))/std(IA) as IA LABEL='Change in Investment to Assets', 
	(LTDA - mean(LTDA))/std(LTDA) as LTDA LABEL='Change in Long-Term Debt to Assets', 
	(STDA - mean(STDA))/std(STDA) as STDA LABEL='Change in Short-Term Debt to Assets';

/* Standardize variables */
proc sql;
	create table mydata_std as
	select &std_vars
	from mydata;
quit;

data risky.mydata;
set mydata;
run;

proc sql;
	select count(*)
	from risky.mydata
	where exp(BMR) < 0;
quit;
