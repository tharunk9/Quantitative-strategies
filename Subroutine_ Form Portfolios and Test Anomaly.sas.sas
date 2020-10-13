*********************************************************************************
 Program: Subroutine_ Form Portfolios and Test Anomaly.sas                                               
 Author : Tharun Polamarasetty, Arun, Jinhau, Jason                                               
 Date   : 05/05/2020                                                          
 Description: Standardized subroutine that forms portfolios and tests anomalies 
after the data has been organized in an earlier master program. This can be called
within a program that has already defined an anomaly and organized the portfolio formation
logic. Note, this program is fed the following macro variables: &bin, &holding_period &rankorder
                         
*********************************************************************************;

*********************Forming Portfolios and Testing Begins Here**************************************;

*******************************************************;
*Rank Stocks and Build Portfolios
*******************************************************;

*sort by date so that can rank by date;
proc sort data=formation;
by date;
run;

*proc ranks to organize stocks into bins by SORTVAR. Decide if you are ranking in descending or ascending order in portfolios;
*&rankorder is macro variable set above to determine descending/ascending;
proc rank data=formation out=formation  &rankorder ties=low groups=&bins;
 var SORTVAR;
 ranks bin ;
 by date;
run;


data formation (keep=permno portdate bin portfolio_weight SORTVAR);
set formation ;

*Fix bins because SAS goes starts at 0 instead of 1;
bin=bin+1;

label 
date="Portfolio Formation date"
bin="Portfolio bin at Formation Date"
;

*some renaming to make things easier;
rename
date=portdate
;
format bin bin_format.;
run;

*now merge formation (i.e., the july portfolios) with stock (i.e., full stock sample),
keeping all returns for next 12 months, since we are holding the stocks in our formation portfolios for 1 year

0 <= intck('month',a.portdate,b.date) <= 11 

means keep all months from 0 months (end of July) to 11 months from now (June t+1)
;
proc sql;
create table holding as
select a.*, b.date, b.ret, b.me, b.lme
from formation as a, stock as b
where a.permno=b.permno and 0 <= intck('month',a.portdate,b.date) <= %eval(&holding_period - 1);
quit;

proc sort data=holding;
by bin date;
run;

*Find average returns for each bin portfolio;
proc means data=holding noprint;
by bin date;
var ret SORTVAR;

weight portfolio_weight; * portfolio weight define above in formation (=1 for equal weighting, =LME for value weighting);

output out=portfolio mean=;
run;

*find average return of Long Short portfolio:

1) merge the bin data with itself, subsetting the top and bottom bins in the SQL statement
2) take difference of return as the portfolio return
3) create a new bin called 99 so that it can be added to the big bin group and treated as an extra but special group
;
proc sql;
create table longshort as
select long.date, long.ret - short.ret as ret, 99 as bin
from portfolio(where=(bin=1)) as long, portfolio(where=(bin=&bins)) as short
where long.date=short.date;
quit;

*stack together so you have all original bins plus one extra (Long/Short returns, with bin=99);
data portfolio;
set portfolio longshort;


month=month(date);
year=year(date);

run;


*******************************************************;
*Analyze Performance
*******************************************************;

*bring in the factors using Proc SQL;
proc sql;
create table portfolio as
select a.*, b.*
from portfolio as a, my.factors_monthly as b
where a.date=b.dateff
order by bin,a.date;
quit;

data portfolio;
set portfolio;

*define excess returns for each bin;
*the long short (bin 99) is already an "excess return" because it is zero net investment, so no adjustment needed;
if bin ne 99 then exret=ret-rf;
else exret=ret;

run;

*Cumulate monthly performance and make a graph;

*cumulate returns for each portfolio;
data portfolio_graph;
set portfolio;
by bin;
*for graphing total returns, convert long short to return by adding back risk free rate;
if bin=99 then ret=ret+rf;
if first.bin then cumret1=1;
if ret ne . then cumret1=cumret1*(1+ret);
else cumret1=cumret1;
cumret=cumret1-1;
retain cumret1;


format cumret1 dollar15.2 bin bin_format.; 
label cumret1="Value of Dollar Invested In Portfolio";

run;

*Graph Cumulative Performance with Log Scale;
proc sgplot data=portfolio_graph;
where bin in(1,&bins,99);

   title2 'Cumulative Performance (Returns)';
   footnote 'Log Scale. Note, Long/Short portfolios converted to Returns by adding back risk free rate';
   series x=date y=cumret1 / group=bin lineattrs=(thickness=2);
Xaxis type=time ;
Yaxis type=log logbase=10 logstyle=linear ; *log based scale;
     
run;

*turn off footnotes or they carry through;
footnote;
*******************************************************;
*What about risk? Sharpe Ratio
*******************************************************;

proc means data=portfolio noprint;
by bin;
var exret ;
output out=mean_std mean= std= /autoname autolabel;
run; 
*!EXAMINE THE RETURNS AND STANDARD DEVIATION;

data sharpe;
set mean_std;

sharpe_ratio=exret_mean/exret_StdDev;
label 
exret_mean="Mean Excess Return"
exret_StdDev="Standard Deviation of Excess Returns"
sharpe_ratio="Sharpe Ratio"
;

format exret_mean exret_StdDev percentn10.2 sharpe_ratio 10.2;
drop _type_ _freq_;


run;

proc print noobs label;
title2 "Sharpe Ratio by bin";
run;
*******************************************************;
*What about risk? Factor Model Adjustment
*******************************************************;

*CAPM regression;
proc reg data = portfolio outest = CAPM_out edf noprint tableout;
by bin;
model exret = mktrf;
quit;

*CAPM clean up regression output;
data CAPM_out;
set CAPM_out;
where  _TYPE_ in ('PARMS','T'); *just keep Coefficients (Parms) and T-statistics (T);

*rescale intercept to percentage but only the PARMS, not T (Cant use percentage format because it would change T-stat also);
IF _TYPE_ ='PARMS' THEN intercept=intercept*100;

label 
intercept="Alpha: CAPM"
mktrf="Market Beta: CAPM"
;

format intercept mktrf 10.2;

keep bin _type_ intercept mktrf;

rename
intercept=alpha_capm
mktrf=mktrf_capm
;
run;


*Fama French 3 Factor;
proc reg data = portfolio outest = FF3_out edf noprint tableout;
by bin;
model exret = mktrf smb hml;
quit;


*FAMA FRENCH ALPHA AND BETAS*;
data FF3_out;
set FF3_out;
where  _TYPE_ in ('PARMS','T');

*rescale intercept to percentage but only the PARMS, not T;
IF _TYPE_ ='PARMS' THEN intercept=intercept*100;

label 
intercept="Alpha: FF3"
mktrf="Market Beta: FF3"
smb="SMB Beta"
hml="HML Beta"
;

format intercept mktrf smb hml 10.2;

keep bin _type_ intercept mktrf smb hml;

rename 
intercept=alpha_ff3
mktrf=mktrf_ff3
;

run;

*MERGE TOGETHER FOR NICE TABLE;
data Nice_table ;
retain bin;
merge CAPM_out FF3_out;
by bin _type_;

format bin bin_format.;
run;

proc print;
title2 "Factor Regression Results";
run;
