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
    
1)  The Persistence and Pricing of Earnings, Accruals, and Cash Flows When Firms Have Large Book-Tax Differences
    By Michelle Hanlon, TAR 2005
    EARN1 = Earnings per share (EPSPXq) 
            * Common shares to calculate EPS (CSHPRq)
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

3) Accruals, cash flows, and aggregate stock returns
    By David Hirshleifer, Kewei Hou,  Siew Hong Teoh, JFE 2009
    Variables same as Sloan 1996
*/
%WRDS("open");
RSUBMIT;
    PROC SQL;
        CREATE TABLE funda_1 AS
        SELECT f.gvkey, f.datadate AS date
            ,f.fyear, f.fyr AS FYE_MONTH
            ,nam.sic, nam.naics
            ,AT, LT
            ,COALESCE(CEQ, CEQL) AS BVE /* Book Value of Equity */
            ,DVP + DVC AS Dividends
            ,DLC, DLTT, PSTK /*
            EARN1 = Earnings per share (*/ ,EPSPX /*) 
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
        FROM comp.funda AS f
        LEFT JOIN comp.NAMES as nam 
            ON f.gvkey = nam.gvkey
        WHERE INDFMT= 'INDL' 
        AND DATAFMT='STD' 
        AND POPSRC='D'
        AND CONSOL='C'
        /*AND DATADATE >= '01JAN1960'd
        AND DATADATE <= '01JAN2012'd
        AND nam.sic NOT LIKE "6%"*/
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
    PROC SORT DATA=funda_2;BY gvkey fyear;RUN;
    PROC DOWNLOAD
        DATA= funda_2
        OUT= _funda;
    RUN;
	/* */
    PROC SQL;
        CREATE TABLE crsp AS
        SELECT DISTINCT t1.gvkey, msf.permno, msf.date
            ,ABS(msf.prc) AS price, msf.ret, msf.retx
            ,msf.shrout
        FROM (SELECT DISTINCT gvkey FROM funda_1) AS t1
        LEFT JOIN crsp.CCMXPF_LINKTABLE AS lnk 
            ON lnk.gvkey = t1.gvkey
        LEFT JOIN crsp.msf AS msf
            ON msf.permno = lnk.lpermno;
    QUIT;
    PROC DOWNLOAD
        DATA= crsp
        OUT= _msf;
    RUN; 
ENDRSUBMIT;
%WRDS("close");

OPTIONS NONOTES;
PROC EXPAND DATA=_funda OUT=fnda_1_interpolate 
        FROM=DAY METHOD=SPLINE;
    BY gvkey;
    ID fyear;
    CONVERT DLC DLTT PSTK;
    RUN;
    
PROC EXPAND DATA=fnda_1_interpolate OUT=fnda_2_fundadiffs 
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
    CONVERT date=ddate / TRANSFORMOUT=( LAG 1 );
    RUN;
    OPTIONS NOTES;

DATA fnda_3_vars; SET fnda_2_fundadiffs;
    EARN1 = EPSPX * CSHPRI;
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
    
    myear = YEAR(date) + (SIGN(MONTH(date)-&divide_month+.1)-1)/2;
    KEEP gvkey fyear date fye_month sic naics lifespan myear at lt
        earn1 cfo1 ta1 earn2 ta2 cfo2;
    RUN;
    PROC SORT DATA=fnda_3_vars;BY gvkey fyear;RUN;

PROC SORT DATA=_msf;BY gvkey permno date;RUN;

/* Use FUNDA to create range for yearly returns based on fyend 
 fyend_num_day_lag is the number of days after fyend to end the yearly return */
%LET fyend_num_month_lag = 4;
PROC EXPAND DATA=fnda_3_vars OUT=tmp_1(KEEP= gvkey fyear ldate date )
        FROM=DAY METHOD=NONE;
    BY gvkey;
    ID fyear;
    CONVERT date=ldate / TRANSFORMOUT=( LAG 1 );
    RUN;
DATA tmp_1;SET tmp_1;
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
    FROM _msf AS m
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
        ,EXP(SUM(LOG(1+RET)))-1 AS retx
        ,price,shrout, date, COUNT(*) AS nummonths
    FROM msf_1_fyear
    WHERE date ne . 
        AND ret > -9999
        AND fyear ne .
    GROUP BY permno,fyear
    HAVING date = MAX(date);
QUIT;

PROC SQL;
    CREATE TABLE dropfirms AS
    SELECT DISTINCT gvkey,permno
    FROM (SELECT DISTINCT gvkey,permno FROM msf_2_logrets)
    GROUP BY gvkey
    HAVING count(*)>1;

    CREATE TABLE msf_3_goodfirms AS
    SELECT DISTINCT *
    FROM msf_2_logrets
    WHERE gvkey NOT IN (SELECT DISTINCT gvkey FROM dropfirms);

    DROP TABLE dropfirms;
QUIT;

/*
Vuolteenaho Recreation:


Book Value of equity:
    1) CEQ: Item 60, Common/Ordinary Equity - Total
    2) CEQL: Item 235, Common Equity / Liquidation Value
Net Income (Vuolteenaho)
    1) NI: Item 172, Net Income (Loss)
    2) Change in BVE + Dividends (D.BVE + DVP/DVC) (Preferred/Common)
Book Debt:
    1) Current Liabilities(DLC/#34) + Total Long Term Debt(DLTT/#9) + Preferred Stock (PSTK/#130)
*/
PROC SQL;
    CREATE TABLE vout_1_vars AS
    SELECT gvkey,fyear,date
        ,COALESCE(CEQ,CEQL) AS BVE
        ,COALESCE(NI,dBVE + DVP + DVC) AS NI
        ,COALESCE(DLC,0) + COALESCE(DLTT,0) + COALESCE(PSTK,0) AS BVD
    FROM fnda_2_fundadiffs;
QUIT;


