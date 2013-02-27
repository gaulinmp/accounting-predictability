
/* Macro */
%macro PortYM(Var, Dataset, Groups, ByVar, EXCHCD);
	proc sort data=&Dataset; By &ByVar;
	run;

	PROC RANK data=&Dataset (WHERE=(EXCHCD in (&EXCHCD))) GROUPS=&Groups OUT=Port&Var(keep=Permno &ByVar &Var Port&Var);
	BY &ByVar;
	VAR &Var;
	RANKS Port&Var;
	run;

	/*Gets Max per group, final group gets a very high value (999999)*/
	proc sql;
		create table PortLimits&Var as
		select &ByVar, Max(Case when (Port&Var = %eval(&Groups-1)) and (Port&Var < 999999) then 999999 else &Var end) as &Var.UB,
		(Port&Var + 1) * %eval(100/&Groups) as Percentile&Var
		from Port&Var
		where Port&Var is not null
		Group By &ByVar, Port&Var;
	quit;

	/*Set min Value per Group per group, first group gets a very low value (-999999)*/
	proc expand data=PortLimits&Var out=PortLimits&Var METHOD=NONE;
	CONVERT &Var.UB=&Var.LB/ transformin=(setmiss -999999) transformout = (Lag 1) ;
	By &ByVar;
	ID Percentile&Var;
	run;

	proc sql;
		create table &Dataset as
		select a.*, b.Percentile&Var
		from &Dataset as a left outer join PortLimits&Var as b ON a.&ByVar = b.&ByVar
		and a.&Var > b.&Var.LB and a.&Var <= b.&Var.UB;
	quit;

	/* Drop middle datasets
	proc datasets nolist;
	delete Port&Var PortLimits&Var;
	run;
	quit;
	*/
%mend PortYM;
