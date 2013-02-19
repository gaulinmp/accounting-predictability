%let data_dir = D:/SAS/return_predictability;
%let code_dir = D:/Dropbox/Documents/School/Projects/Return_Predictability_of_Earnings;
libname USER "&data_dir";
%INCLUDE "D:/Dropbox/Documents/School/MACROS.SAS";

/*
Variables taken from:

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
        CREATE TABLE fundq AS
        SELECT f.gvkey, f.datadate AS date
            ,f.fyearq, f.fqtr, f.fyr AS FYE_MONTH
            ,nam.sic, nam.naics
			,ATq AS AT, LTq AS LT /*
            EARN1 = Earnings per share (*/ ,EPSPXq AS EPSPX /*) 
                     * Common shares to calculate EPS (*/ ,CSHPRq AS CSHPRI /*)
            CFO1 = Operating Activities / Net CF (*/ ,OANCFy AS OANCF /*) [Post 1987]
            CFO1 =  Funds from Operations (*/ ,FOPTy AS FOPT /* ) [Pre 1987] 
                    - Change in Current Assets(*/ ,ACTq AS ACT /*)
                    - Change in Debt in Current Liabilities (*/ ,DLCq AS DLC /*)
                    + Change in Current Liabilities (*/ ,LCTq AS LCT /*)
                    + Change in Cash (*/ ,CHq AS CH /*)
            TA1 = Net Income (*/ ,NIq AS NI /*) 
                + Depreciation (*/ ,DPq AS DP /*)
                - Cash Flow from Operations ( CFO1)
            EARN2 = Operating income after depreciation (*/ ,OIADPq AS OAIDP/*)
            TA2 = Change in current assets (ACTq)
                    - Change in cash/equivalents (*/ ,CHEq AS CHE /*)
                    - Change in current liabilities (LCTq)
                    + Change in debt inculuded in current liabilties (DLCq)
                    + Change in income tax payable (*/ ,TXPq AS TXP /*)
                    - Depreciation and amortization expense (DPq)*/
        FROM comp.fundq AS f
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

		CREATE TABLE funda AS
        SELECT f.gvkey, f.datadate AS date
            ,f.fyear, f.fyr AS FYE_MONTH
            ,nam.sic, nam.naics
			,AT, LT /*
            EARN1 = Earnings per share (*/ ,EPSPX /*) 
                     * Common shares to calculate EPS (*/ ,CSHPRI /*)
            CFO1 = Operating Activities / Net Cash Flow (*/ ,OANCF /*) [Post 1987]
            CFO1 =  Funds from Operations (*/ ,FOPT /* ) [Pre 1987] 
                    - Change in Current Assets(*/ ,ACT /*)
                    - Change in Debt in Current Liabilities (*/ ,DLC /*)
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
		
		*CREATE TABLE crsp AS
		SELECT DISTINCT t1.gvkey, dsf.permno, dsf.date
            ,ABS(dsf.prc) AS price, dsf.ret, dsf.retx
		FROM (SELECT DISTINCT gvkey FROM
				(SELECT DISTINCT gvkey FROM funda 
				UNION SELECT DISTINCT gvkey FROM fundq)) AS t1
        LEFT JOIN crsp.CCMXPF_LINKTABLE AS lnk 
            ON lnk.gvkey = t1.gvkey
        LEFT JOIN crsp.dsf AS dsf
            ON dsf.permno = lnk.lpermno;
    QUIT;
    PROC DOWNLOAD
        DATA= fundq
        OUT= fundq;
    RUN;
    PROC DOWNLOAD
        DATA= funda
        OUT= funda;
    RUN;
    *PROC DOWNLOAD
        DATA= crsp
        OUT= crsp_sauce;
    RUN;
ENDRSUBMIT;
%WRDS("close");

PROC SORT DATA=fundq;BY gvkey fyearq fqtr;RUN;
PROC SQL;
	CREATE TABLE tmp AS
	SELECT *, count(*) AS goramultiples, MAX(fye_month)-MIN(fye_month) AS poo
	FROM fundq 
	GROUP BY gvkey,fyearq, fqtr
	HAVING goramultiples > 1;

	CREATE TABLE tmp2 AS
	SELECT * FROM fundq 
	WHERE gvkey IN (SELECT UNIQUE gvkey FROM tmp WHERE poo>=9);
QUIT;


PROC SQL;
	*CREATE TABLE tmp_q AS
	SELECT gvkey, date, fyearq AS fyear, fye_month,sic,naics
		,EPSPXq * CSHPRq AS earn1
		,OANCFy AS CFO1_a
		,FFOq-ACTq-DLCq+LCTq+CHq AS CFO1
		,COALESCE(FFOq,0)-COALESCE(ACTq,0)
			-COALESCE(DLCq,0)+COALESCE(LCTq,0)
			+COALESCE(CHq,0) AS CFO1_collapsed
		,NIq+DPq-CALCULATED CFO1_collapsed AS ta1
		,OAIDPq AS earn2
	FROM fundq;
QUIT;
