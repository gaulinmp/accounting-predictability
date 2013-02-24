libname y 'F:\SAS\Programs\Mac\SizeBM';
libname main 'f:\SAS\Programs\Work';

%WRDS("open");
rsubmit;

/* change to another sastemp if you borrow my code */
libname out '/sastemp7/riceacc'; 

/*Get things from Compustat - I will not merge until much later.  Do not merge with CRSP if you don't need CRSP*/
/*Im not sure this is the best SIC from Compustat, if anyone can verify let me know and I'll change it*/

proc sql;
  	create table CompY1 as 
  	select a.gvkey, a.datadate,
	/*Optional stuff here*/
	a.SICH, input(b.Sic, 11.) as sic, /*a.Tic, a.CUSIP,*/
	/*Put Variables in here*/
	CEQ, TXDITC, PSTKRV, PSTKL, PSTK, SEQ,
	AT
	from comp.FUNDA (where=(INDFMT= 'INDL' and DATAFMT='STD' and POPSRC='D' and CONSOL='C')) as a
	left outer join comp.Names as b on a.gvkey = b.gvkey
	left outer join COMP.ADSPRATE as c on a.gvkey = c.gvkey
	and a.datadate = c.datadate
	;
quit;

proc download data=Compy1 out=y.compy1;
run;

endrsubmit;
%WRDS("close");

proc sort data=y.compy1; by gvkey datadate;
run;

/*Define Fundamental Variables, and keep whatever variables would need to be combined in the future with CRSP if combining*/

/*Create lags and leads - it creates a lead of datadate to do a process of expanding the yearly data into monthly*/
PROC EXPAND data=y.compy1 OUT=compy2 METHOD=NONE; 
BY Gvkey;
CONVERT Datadate=DatadateNext/ transformin=(setmiss -999) transformout = ( Lead 1 set (-999 .));
ID Datadate;
run;

/*Define Variables using regular and lagged/lead ones - I will also clean the dataset of stuff I dont need
First line of the keep statement I use for variables that already exists, second line for the ones I am creating.
MonthDiff is a variable that will be created to construct the monthly expansion.  Also keep Assets to deal with a later problem*/
Data Compy;
set Compy2;
BE= . ;
if SEQ > . then BE = SEQ + coalesce(TXDITC,0) - coalesce(PSTKRV,PSTKL,PSTK,0);
if CEQ > . and SEQ = . then BE=CEQ + coalesce(PSTK,0) + coalesce(TXDITC,0) - coalesce(PSTKRV,PSTKL,PSTK,0); 
if CEQ = . and AT > 0 and LT > . then BE=AT-LT + coalesce(TXDITC,0) - coalesce(PSTKRV,PSTKL,PSTK,0);
*if ATt_1 > 0  then GPASUE=(GPA-GPAt_1)/ATt_1;
monthdiff=coalesce(intck('month',datadate,datadatenext),12);
keep GVkey Datadate sich SIC monthdiff AT
BE ;
run;

/*Download CRSP stuff*/

%WRDS("open");
rsubmit;

libname out '/sastemp4'; 

proc download data=crsp.CCMXPF_LINKTABLE (where=(LinkTYPE in ("LU", "LC", "LD", "LF", "LN", "LO", "LS", "LX"))) out=_CCMXPF_LINKTABLE;
run;

proc download data=crsp.msenames out=_msenames;
run;

endrsubmit;
%WRDS("close");


/*Define Macro Variables for convenience*/

%let DSName = Compy;
%let DateName = Datadate;



/*We will use the link table from CRSP to assign permnos to our already built compustat dataset
Also I want to identify linking codes so I can address an issue for duplicates that arise from Permnos and GVkeys
having more than one linking code for the same period of time.  Furthermore, we need the shareclass to deal with Dual Class shares.
I change blank share classes to ZZ so when I order them, class A comes before blank.  If there is only one type
of share it won't matter*/
PROC SQL;
	CREATE TABLE CCM1 AS
	SELECT lpermno AS permno, a.*,
        CASE b.LINKTYPE 
            WHEN 'LC' THEN 1
            WHEN 'LU' THEN 2
            WHEN 'LX' THEN 3
            WHEN 'LS' THEN 4
            WHEN 'LN' THEN 5
            WHEN 'LD' THEN 6
            WHEN 'LO' THEN 7 
            WHEN 'LF' THEN 8 
            ELSE 99 
        END AS lnum
        ,CASE 
            WHEN d.SHRCLS IS NULL THEN 'ZZ' 
            ELSE d.SHRCLS 
        END AS SHRCLS
	FROM &DSName AS a 
    INNER JOIN _CCMXPF_LINKTABLE AS b
        ON a.GVKEY = b.GVKEY
        AND (LINKDT <= a.DATADATE OR LINKDT = .B) 
        AND (a.DATADATE <= LINKENDDT OR LINKENDDT = .E)
    LEFT OUTER JOIN _msenames AS d 
        on b.lpermno = d.permno
        AND a.datadate BETWEEN d.namedt AND d.nameendt;
QUIT;


/*DUPLICATE HANDLING*/
/*First Step - Remove duplicate links keeping the 'best' one and if one permno is duplicated.
This problem seems to be caused by permnos being linked to gvkeys by two different linking codes
during the same period.  Apparently there are not two GVkeys to one Permno, but this would
address that issue as well.

If you look at problem1 the first time around, you get a list of the duplicated firms,
then the second time I run it you can see that there are no problems*/
proc sort data=CCM1; By Permno &DateName lnum GVkey;
run;
Data problem1fix1;
Set CCM1;
RowID=_N_;
run;

proc rank data=problem1fix1 out=problem1fix2;
Var RowID;
By Permno &DateName;
Ranks d;
run;

proc sql;
	create table problem1 as
	select *
	from problem1fix2
	Group By permno, &DateName
	Having max(d) > 1
	Order by Permno, &DateName, d;
quit;

Data CCM2 (drop=lprev);
Set problem1fix2;
By Permno;
retain lprev;
if first.permno then lprev = .;
if &DateName = lprev then delete;
lprev=&DateName;
run;

proc sql;
	create table problem1 as
	select *
	from CCM2
	Group By permno, &DateName
	Having max(d) > 1
	Order by Permno, &DateName, d;
quit;

/*Second Step - If One GVkey has 2 permnos keep the class A if available, if not I choose the lowest permno
I still need to figure out what is the best way to deal with dual shares*/
proc sort data=CCM2; By GVkey &DateName lnum SHRCLS Permno;
run;

Data problem2fix1;
Set CCM2 (drop= rowid d);
RowID=_N_;
run;

proc rank data=problem2fix1 out=problem2fix2;
Var RowID;
By GVkey &DateName;
Ranks d;
run;

proc sql;
	create table problem2 as
	select *
	from problem2fix2
	Group By GVkey, &DateName
	Having max(d) > 1
	Order by GVKey, &DateName, d;
quit;

Data CCM3 (drop=lprev);
Set problem2fix2;
By GVkey;
retain lprev;
if first.GVkey then lprev = .;
if &DateName = lprev then delete;
lprev=&DateName;
run;

proc sql;
	create table problem2 as
	select *
	from CCM3
	Group By GVKey, &DateName
	Having max(d) > 1
	Order by GVkey, &DateName, d;
quit;

/*Drop stuff I no longer need, comment if you want to keep and see*/
Data CCM3;
retain permno gvkey &DateName ;
set CCM3;
drop lnum SHRCLS rowID d;
run;

proc sort data=ccm3; By permno gvkey &DateName;
run;

/*This is most recent*/
%LET wait=6;
data CCM4 (drop=date1 i);
retain GVkey DateAvail;
set CCM3 ;
do i = 1 to monthdiff;
	date1 = intnx('month',datadate,i,'E');
	DateAvail = intnx('month',date1,&wait,'E');
	output;
end;
format date1 dateavail mmddyy10.;
run;


/*And yet again we end up with dups on permno gvkey combinations.  I think these might be mergers.  The previous code didnt clean it because there is overlap
between fiscal year of these firms.  Time for more row chop chop.  I'll choose the one with biggest assets, I welcome other suggestions*/

/*Show dup rows*/
proc sql;
	create table dups as
	select *
	from ccm4
	group by permno, dateavail
	Having count (*) > 1;
quit;

proc sort data=CCM4; By Permno DateAvail Descending Datadate Descending AT GVkey;
run;

Data CCM5 (drop=lprev);
Set CCM4;
By Permno;
retain lprev;
if first.permno then lprev = .;
if DateAvail = lprev then delete;
lprev=DateAvail;
run;

/*Check dup rows, problem solved*/
proc sql;
	create table dups as
	select *
	from ccm5
	group by permno, dateavail
	Having count (*) > 1;
quit;

/*For yearly - I'll take July Value for each year, and the June value for monthly*/
proc sql;
	create table y1 as
	select SIC as SICC, SICCD, b.SHRCD, b.EXCHCD, b.ME, b.PRC, a.*, c.ME as MEDec
	from CCM5 (where=(month(DateAvail)=7)) as a left outer join main.CrspRet (where=(month(Date)=6)) as b
	on a.Permno = b.permno and intnx('month',a.DateAvail, 0,'E') = intnx('month',b.Date, 1,'E')
	left outer join main.CrspRet (where=(month(Date)=12) keep=permno date ME) as c
	on a.Permno = c.permno and intnx('month',a.DateAvail, 0,'E') = intnx('month',c.Date, 7,'E')
	Order By Permno, &DateName;
quit;
Data y2;
set y1;
/* First, use historical Compustat SIC Code */
if sich>0 then SIC=sich;
/* Then, if missing, use historical CRSP SIC Code */
else if siccd>0 then sic=siccd;
/* and adjust some SIC code to fit F&F 48 ind delineation */
if SIC in (3990,9995,9997) and siccd>0 and siccd ne SIC then SIC = siccd;
if SIC in (3990,3999) then SIC = 3991;
/*if sic is missing as a last resort force compustat overall SIC*/
if SIC = . then SIC = SICC;
drop SICC SICH SICCD;
run;

Data y.CCY;
Retain Permno DateAvail Datadate;
set y2;
BM = . ; if MEDec > 0 then BM = BE/MEDec;
drop  MEDec;
run;

/*Clean dataset*/
Data c1;
set y.CCY;
where EXCHCD in (1,2,3) and SHRCD in (10,11) and SIC not between 6000 and 6999
and BM > 0; 
run;

%include "F:\SAS\Programs\Play\MacroBuckets.sas" / lrecl=3000;

/* Buckets */
%PortYM(ME, c1, 20, DateAvail, %str(1));
%PortYM(BM, c1, 20, DateAvail, %str(1));

/*Convert into Montly observations given Datadate date*/
data c2;
set c1;
do i = 0 to 11;
	Date = intnx('month',DateAvail,i,'E');
	output;
end;
format Date mmddyy10.;
drop i;
keep permno date PercentileME PercentileBM;
run;
