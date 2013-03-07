PROC SQL NOPRINT;
SELECT SCAN(TRANWRD(xpath,'\','/'),-1,'/') INTO :progname FROM sashelp.vextfl
    WHERE UPCASE(xpath) LIKE '%.SAS';
SELECT xpath INTO :progdir FROM sashelp.vextfl 
    WHERE UPCASE(xpath) LIKE '%.SAS';
QUIT;
%PUT ;
%PUT &progname;
%PUT ;
%PUT &progdir;
%PUT ;
%LET pwd = %SUBSTR(&progdir,1,%EVAL(%LENGTH(&progdir) - %LENGTH(&progname)-1));
%PUT &pwd;

%INCLUDE "&pwd/preamble.sas";
libname USER '/scratch/macneddy/old';

%LET divide_month = 8;

%MACRO DEBUG_already_run();
%MEND DEBUG_already_run;
/*
Variables taken from:

Book Value of equity:
    1) CEQ: Item 60, Common/Ordinary Equity - Total
    2) CEQL: Item 235, Common Equity / Liquidation Value
Net Income (Vuolteenaho)
    1) NI: Item 172, Net Income (Loss)
    2) Change in BVE + Dividends (D.BVE + DVP/DVC) (Preferred/Common)
Book Debt:
    1) Current Liabilities(DLC/#34) + Total Long Term Debt(DLTT/#9) + Preferred Stock (PSTK/#130)
    
    EARN = Earnings per share (EPSPXq) 
            * Common shares to calculate EPS (CSHPRq)

1)  The Persistence and Pricing of Earnings, Accruals, and Cash Flows When Firms Have Large Book-Tax Differences
    By Michelle Hanlon, TAR 2005
    EARN1 = Net Income (NIq) 
            + Depreciation (DPq)
    CFO1 = Operating Activities / Net Cash Flow (OANCFy) [Post 1987]
    CFO1 = Funds from Operations (FOPTy) [Pre 1987]
             - Change in Current Assets(ACTq)
             - Change in Debt in Current Liabilities (DLCq)
             + Change in Current Liabilities (LCTq)
             + Change in Cash (CHq)
    TA1 = Net Income (NIq) 
            + Depreciation (DPq)
            - Cash Flow from Operations (CFO1)

 2)  Do Stock Prices Fully Reflect Information in Accruals and Cash Flows about Future Earnings?
    By Richard G. Sloan, TAR 1996
    EARN2 = Operating income after depreciation (OIADPq)
    CFO2 = Earnings - Accruals (EARN2 - TA2)
    TA2 = Change in current assets (ACTq)
            - Change in cash/equivalents (CHEq)
            - Change in current liabilities (LCTq)
            + Change in debt inculuded in current liabilties (DLCq)
            + Change in income tax payable (TXPq)
            - Depreciation and amortization expense (DPq)
*/

PROC SQL;
    CREATE TABLE funda_1 AS
    SELECT f.gvkey, f.datadate AS date
        ,f.fyear, f.fyr AS FYE_MONTH
        ,nam.sic, nam.naics, f.conm AS firmname
        ,AT, LT
        ,COALESCE(CEQ, CEQL) AS BVE /* Book Value of Equity */
        ,COALESCE(DVP,0) + COALESCE(DVC,0) AS Dividends
        ,DLC, DLTT, PSTK /*
        EARN = Earnings per share (*/ ,EPSPX /*) 
                 * Common shares to calculate EPS (*/ ,CSHPRI /*)
        CFO1 = Operating Activities / Net Cash Flow (*/ ,OANCF /*) [Post 1987]
        CFO1 =  Funds from Operations (*/ ,FOPT /* ) [Pre 1987] 
                - Change in Current Assets(*/ ,ACT /*)
                - Change in Debt in Current Liabilities ( DLC )
                + Change in Current Liabilities (*/ ,LCT /*)
                + Change in Cash (*/ ,CH /*)
        TA1 = Net Income (*/ ,NI /*) 
            + Depreciation (*/ ,DP /*)
            - Cash Flow from Operations ( CFO1)
        EARN2 = Operating income after depreciation (*/ ,OIADP /*)
        TA2 = Change in current assets (ACT)
                - Change in cash/equivalents (*/ ,CHE /*)
                - Change in current liabilities (LCT)
                + Change in debt inculuded in current liabilties (DLC)
                + Change in income tax payable (*/ ,TXP /*)
                - Depreciation and amortization expense (DP)*/
    FROM raw.funda AS f
    LEFT JOIN raw.NAMES as nam 
        ON f.gvkey = nam.gvkey
    WHERE INDFMT= 'INDL' 
    AND DATAFMT='STD' 
    AND POPSRC='D'
    AND CONSOL='C'
    ORDER BY gvkey, date;
    
    /* Drop firms with one observation and no Book Value of Equity */
    CREATE TABLE dropfirms1 AS
    SELECT UNIQUE count(*) AS drop,gvkey
    FROM funda_1
    WHERE fyear NE .
    GROUP BY gvkey,fyear
    HAVING drop > 1;
    
    CREATE TABLE dropfirms2 AS
    SELECT UNIQUE SUM(BVE) as drop, gvkey
    FROM funda_1
    GROUP BY gvkey
    HAVING drop eq .;

    CREATE TABLE funda_2 AS
    SELECT *,count(*) AS lifespan 
    FROM funda_1
    WHERE fyear ne . 
        AND gvkey NOT IN (SELECT gvkey FROM dropfirms1)
        AND gvkey NOT IN (SELECT gvkey FROM dropfirms2)
    GROUP BY gvkey
    ORDER BY gvkey,fyear;

    DELETE FROM funda_2
    WHERE lifespan < 2;

    DROP TABLE dropfirms1,dropfirms2;	
QUIT;
DATA _funda;SET funda_2;
    RUN;
/*
OPTIONS NONOTES;
PROC EXPAND DATA=funda_2 OUT=funda_3 
        FROM=DAY METHOD=NONE;
    BY gvkey;
    ID fyear;
    CONVERT act=dact / TRANSFORMOUT=( DIF 1 );
    CONVERT lct=dlct / TRANSFORMOUT=( DIF 1 );
    CONVERT dlc=ddlc / TRANSFORMOUT=( DIF 1 );
    CONVERT che=dche / TRANSFORMOUT=( DIF 1 );
    CONVERT txp=dtxp / TRANSFORMOUT=( DIF 1 );
    CONVERT bve=dbve / TRANSFORMOUT=( DIF 1 );
    CONVERT at =lat  / TRANSFORMOUT=( LAG 1 );
    RUN;
    OPTIONS NOTES;

DATA _funda;SET funda_3;
    *NI = COALESCE(NI,dbve+Dividends);
    TA_BS = dact - dlct - dche + ddlc + dtxp - dp;
    CFO_BS = e_bs - ta_bs;
    DROP dact dlct ddlc dche dtxp dbve;
    RUN;
PROC SORT DATA=_funda;BY gvkey fyear;RUN;
*/

PROC SQL;
    CREATE TABLE m1 AS
    SELECT permno,date
        ,COALESCE(ABS(prc),ABS(ALTPRC)) AS prc
        ,vol,ret,retx,shrout
        ,ABS(prc)*shrout/1000 AS MVE
        ,CASE WHEN vol > 0 THEN 1 ELSE 0 END AS traded
    FROM raw.msf
    ORDER BY permno, date;
QUIT;

* Applying Vuolteneehos filtering restrictions;
PROC EXPAND DATA=m1 OUT=m2 FROM=month METHOD=NONE;
    BY permno;
    ID date;
    CONVERT traded = traded_prev_year
         / TRANSFORMOUT=( MOVSUM 12 );
    CONVERT traded = traded_prev_month
         / TRANSFORMOUT=( LAG 1 );
    RUN;
    
PROC EXPAND DATA=m2 OUT=m2 FROM=month METHOD=NONE;
    BY permno;
    ID date;
    CONVERT mve = mve_prev_1_year / TRANSFORMOUT=( LAG 12 );
    CONVERT mve = mve_prev_2_year / TRANSFORMOUT=( LAG 24 );
    CONVERT mve = mve_prev_3_year / TRANSFORMOUT=( LAG 36 );
    CONVERT traded_prev_year = traded_prev_2_year
         / TRANSFORMOUT=( LAG 12 );
    CONVERT traded_prev_year = traded_prev_3_year
         / TRANSFORMOUT=( LAG 24 );
    CONVERT traded_prev_year = traded_prev_4_year
         / TRANSFORMOUT=( LAG 36 );
    CONVERT traded_prev_year = traded_prev_5_year
         / TRANSFORMOUT=( LAG 48 );
    RUN;

DATA m2;SET m2;
    traded_last_5_years = SIGN(traded_prev_year*
        traded_prev_2_year*traded_prev_3_year*
        traded_prev_4_year*traded_prev_5_year);
    past_3_years_mve = SIGN(mve_prev_1_year*
        mve_prev_2_year*mve_prev_3_year);
    mve_gt_10M = FLOOR((SIGN(mve-10)+1)/2);
    
    IF traded_last_5_years eq . THEN traded_last_5_years = 0;
    IF traded_prev_month eq . THEN traded_prev_month = 0;
    IF past_3_years_mve eq . THEN past_3_years_mve = 0;
    IF mve_gt_10M eq . THEN mve_gt_10M = 0;
    vs_eq = traded_last_5_years * traded_prev_month
            * past_3_years_mve * mve_gt_10M;
    DROP traded traded_prev_year
        traded_prev_2_year traded_prev_3_year
        traded_prev_4_year traded_prev_5_year
        mve_prev_1_year mve_prev_2_year mve_prev_3_year;
    RUN;
    
PROC SQL;
    CREATE TABLE crsp1 AS
    SELECT DISTINCT lnk.gvkey, msf.*
    ,CASE lnk.linktype 
            WHEN 'LC' THEN 1
            WHEN 'LU' THEN 2
            WHEN 'LX' THEN 3
            WHEN 'LS' THEN 4
            WHEN 'LN' THEN 5
            WHEN 'LD' THEN 6
            WHEN 'LO' THEN 7 
            WHEN 'LF' THEN 8 
            ELSE 99 
        END AS linknum
    FROM m2 AS msf
    LEFT JOIN (SELECT * FROM raw.CCMXPF_LINKTABLE 
            WHERE linktype in ("LU","LC","LD","LF","LN","LO","LS","LX"))AS lnk 
        ON msf.permno = lnk.lpermno
        AND (linkdt <= msf.date OR linkdt = .B) 
        AND (msf.date <= linkenddt OR linkenddt = .E)
    ORDER BY gvkey,permno,date;
    
    CREATE TABLE dropfirms1 AS
    SELECT DISTINCT gvkey,1 AS dropfirm
    FROM (SELECT DISTINCT gvkey,permno FROM crsp1 WHERE gvkey ne "")
    GROUP BY gvkey
    HAVING count(*)>1
    ORDER BY gvkey;
    
    CREATE TABLE dropfirms2 AS
    SELECT DISTINCT gvkey,1 AS dropfirm
    FROM (SELECT DISTINCT gvkey,permno FROM crsp1 WHERE gvkey ne "")
    GROUP BY permno
    HAVING count(*)>1
    ORDER BY gvkey;
    
    CREATE TABLE _msf_linked AS
    SELECT c.*
        ,COALESCE(d1.dropfirm,d2.dropfirm,0) AS dropfirm
    FROM crsp1 AS c
    LEFT JOIN dropfirms1 AS d1
        ON c.gvkey = d1.gvkey
    LEFT JOIN dropfirms2 AS d2
        ON c.gvkey = d2.gvkey
    ORDER BY gvkey,permno,date;
QUIT;



/*  Create restrictions on FUNDA */

OPTIONS NONOTES;
PROC EXPAND DATA=_funda OUT=fnda_1_interpolate 
        FROM=DAY METHOD=SPLINE;
    BY gvkey;
    ID fyear;
    CONVERT DLC PSTK ;*DLTT;
    RUN;

PROC EXPAND DATA=fnda_1_interpolate OUT=fnda_1_interpolate 
        FROM=DAY METHOD=NONE;
    BY gvkey;
    ID fyear;
    CONVERT act=dact / TRANSFORMOUT=( DIF 1 );
    CONVERT dlc=ddlc / TRANSFORMOUT=( DIF 1 );
    CONVERT lct=dlct / TRANSFORMOUT=( DIF 1 );
    CONVERT ch =dch  / TRANSFORMOUT=( DIF 1 );
    CONVERT che=dche / TRANSFORMOUT=( DIF 1 );
    CONVERT txp=dtxp / TRANSFORMOUT=( DIF 1 );
    CONVERT bve=dbve / TRANSFORMOUT=( DIF 1 );
    CONVERT date=ldate / TRANSFORMOUT=( LAG 1 );
    CONVERT bve =l1bve / TRANSFORMOUT=( LAG 1 );
    CONVERT bve =l2bve / TRANSFORMOUT=( LAG 2 );
    CONVERT bve =l3bve / TRANSFORMOUT=( LAG 3 );
    CONVERT ni  =lni   / TRANSFORMOUT=( LAG 1 );
    CONVERT ni  =l2ni  / TRANSFORMOUT=( LAG 2 );
    CONVERT dltt=ldltt / TRANSFORMOUT=( LAG 1 );
    CONVERT dltt=l2dltt/ TRANSFORMOUT=( LAG 2 );
    RUN;
    OPTIONS NOTES;

DATA fnda_2_fundadiffs;SET fnda_1_interpolate;
    roe_ge_neg1 = 0;
        IF COALESCE(NI,dBVE + Dividends)>(dBVE-BVE)
            THEN roe_ge_neg1 = 1;
    dec_fye = 0; 
        IF fye_month eq 12 
            THEN dec_fye = 1;
    past_3_years_bve = 0; 
        IF l1bve*l2bve*l3bve > 0 AND ABS(l1bve) eq l1bve AND ABS(l2bve) eq l2bve
            THEN past_3_years_bve = 1;
    past_2_years_nidltt = 0; 
        IF lni*l2ni ne . AND ldltt*l2dltt ne .
            THEN past_2_years_nidltt = 1;
    vs_acc = dec_fye * past_3_years_bve * past_2_years_nidltt * roe_ge_neg1;
    DROP l1bve l2bve l3bve lni l2ni ldltt l2dltt;
    RUN;

DATA fnda_3_vars; SET fnda_2_fundadiffs;
    EARN = EPSPX * CSHPRI;
    EARN1 = NI + DP;
    CFO1_Pre1989 = FOPT-dACT-dDLC+dLCT+dCH;
    CFO1_Pre1989_coalesced = FOPT
            -COALESCE(dACT,0)
            -COALESCE(dDLC,0)
            +COALESCE(dLCT,0)
            +COALESCE(dCH ,0);
    CFO1 = COALESCE(OANCF,CFO1_Pre1989);
    CFO1_coalesced = COALESCE(CFO1,CFO1_Pre1989_coalesced);
    TA1 = NI+DP-CFO1;
    TA1_coalesced = NI+DP-CFO1_coalesced;
    
    EARN2 = OIADP;
    TA2 = dACT - dCHE - dLCT + dDLC + dTXP - DP;
    CFO2 = EARN2 - TA2;
    
    ROE = .; IF (BVE-dBVE) > 0 THEN
        ROE = COALESCE(NI,dBVE + Dividends)/(BVE-dBVE);
    KEEP gvkey fyear date fye_month sic naics lifespan at lt
        earn earn1 cfo1 ta1 earn2 ta2 cfo2 bve roe vs_acc firmname;
    RUN;
    PROC SORT DATA=fnda_3_vars;BY gvkey fyear;RUN;

    
    
    
/* Use FUNDA to create range for yearly returns based on fyend 
 fyend_num_day_lag is the number of days after fyend to end the yearly return */
%LET fyend_num_month_lag = 4;
%LET msf = _msf_gvkey;
DATA &msf;SET _msf_linked;
    IF gvkey ne .;
    IF dropfirm eq 0;
    DROP dropfirm;
    RUN;
    
DATA tmp_1;SET fnda_2_fundadiffs(KEEP= gvkey fyear ldate date );
    BY gvkey;
    deleteme = 0;
    datedif = date - ldate;
    /* The first lag_date is always blank. If it's not the first, there's a filing gap. Drop it. */
    IF NOT FIRST.gvkey THEN DO; 
        IF ldate eq . THEN deleteme = 1;
    END;
    /* return window end date is 'fyend_num_month_lag' months after fyend */
    ret_end = INTNX('month',date,&fyend_num_month_lag);
    FORMAT ret_end date9.;
    /* return window beginning date is 12 months before the end date */
    ret_beg = INTNX('month',ret_end,-11);
    FORMAT ret_beg date9.;
    /* If the beginning date is before last years fyend, drop it */
    IF ret_beg < ldate THEN  deleteme = 1;
    RUN;

PROC SQL;
    /* Drop dates from above */
    CREATE TABLE tmp_2 AS
    SELECT * FROM tmp_1
    GROUP BY gvkey
    HAVING max(deleteme) = 0
    ORDER BY gvkey,fyear;
    
    /* Use return beginning and end range to join fyear to DSF */
    CREATE TABLE msf_1_fyear AS
    SELECT m.*,f.fyear
    FROM (SELECT gvkey, permno, date, prc,shrout,ret,mve,vol,vs_eq FROM &msf) AS m
    LEFT JOIN tmp_2 AS f
        ON m.gvkey = f.gvkey
        AND m.date ge f.ret_beg 
        AND m.date le f.ret_end;
    
    DROP TABLE tmp_1, tmp_2;
QUIT;

PROC SQL;
    CREATE TABLE msf_2_logrets AS
    SELECT DISTINCT gvkey,permno,fyear
        ,EXP(SUM(LOG(1+RET)))-1 AS ret
        ,prc,shrout,vol,date,mve,vs_eq, COUNT(*) AS nummonths
    FROM msf_1_fyear
    WHERE date ne . 
        AND ret > -9999
        AND fyear ne .
    GROUP BY permno,fyear
    HAVING date = MAX(date);
QUIT;






/* Create output datasets by merging msf and funda datasets. */
PROC SQL;
    CREATE TABLE vout_1_vars AS
    SELECT UNIQUE f.gvkey,f.fyear,f.date,m.permno
        ,f.sic,bve,mve,at
        ,log(1+roe) AS ROE
        ,log(mve/bve) AS MtB
        ,log(1+ret) AS ret
        ,earn, cfo1 AS cfo, ta1 AS ta
        /*,e_bs,e_cf,cfo_bs,cfo_cf,ta_bs,ta_cf */
        ,ranuni(bve*1000) AS randomnum
        ,LENGTH(firmname) AS namelen
        ,CASE
                WHEN mve/bve > 1/100 AND mve/bve  < 100 THEN vs_acc*vs_eq
                ELSE 0
            END AS in_vol_sample
    FROM fnda_3_vars AS f
    LEFT JOIN msf_2_logrets AS m
        ON f.gvkey = m.gvkey
        AND f.fyear = m.fyear;

    CREATE TABLE vout_2_nonempty AS
    SELECT * 
    FROM vout_1_vars
    WHERE roe NE . 
        AND mtb NE . 
        AND ret NE .;
QUIT;

%EXPORT_STATA(db_in=vout_1_vars(WHERE=(in_vol_sample=1)), filename = "&data_dir/07_old_vuolteenaho.dta");
%EXPORT_STATA(db_in=vout_2_nonempty,filename="&data_dir/08_old_accdata.dta");

ENDSAS;
