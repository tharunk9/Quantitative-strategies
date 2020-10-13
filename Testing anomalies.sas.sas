
*********************************************************************************                                              
 Author : Tharun Polamarasetty, Arun, Jinhau, Jason                                               
 Date   : 05/05/2020                                                          
 Description: uses crspm_small dataset monthly returns from CRSP and 
 examines the value anomaly with sorts and graphs using
 the Subroutine_ Form Portfolios and Test Anomaly
                         
*********************************************************************************;



/* To clear log*/
	proc datasets library = work kill memtype=data nolist;
	  quit;



**Define your paths;

%let data_path=/courses/d0f4cb55ba27fe300/Anomalies;
%let program_path=/courses/d0f4cb55ba27fe300/Anomalies/programs;
%let output_path=/home/&sysuserid/sasuser.v94;


*Define Data library;
libname my "&data_path";


*Make temporary version;
data stock;
set my.crspm_small;
by permno;


*fix price variable because it is sometimes negative to reflect average of bid-ask spread;
price=abs(prc);
*get beginning of period price;
lag_price=lag(price);
if first.permno then lag_price=.;

if LME=. then delete; *require all stocks to have beginning of period market equity.;
if primary_security=1; *pick only the primary security as of that date (only applies to multiple share class stocks);

keep date permno ME ret LME lag_price;
*remove return label to make programming easier;
label ret=' ';

run;  

*Define book equity Fama French Style:


*Get Compustat Data ready; 
data account;
set my.comp_big;

*data is already sorted on WRDS so we can use by groups right away;
  by gvkey datadate;

*Calculate Stockholder's Equity;
  SE=coalesce(SEQ, CEQ+PSTK, AT - LT);

*Calculate Book value of Preferred Stock;
  PS = coalesce(PSTKRV,PSTKL,PSTK,0);
  
*Calculate balance sheet deferred taxes and investment tax credit;
  if missing(TXDITC) then TXDITC = 0 ;

*Define BOOK Equity according to Fama French Definition!;
  BE = SE + TXDITC - PS ;

*set Negative book equity to missing;
  if BE<0 then BE=.;

GPA = (REVT - COGS)/AT; 

label 
BE="Book Value of Equity Fama French"
GPA = "Gross Profits to Assets"
;

*require the stock to have a PERMNO (a match to CRSP);
if permno=. then delete;
*only keep the variables we need for later;
keep datadate permno BE GPA;

*keep datadate permno BE seq ceq pstk at lt TXDITC PS se;
run;


*Merge stock returns data from CRSP with book equity accounting data from Compustat;

proc sql;
create table formation as
select a.*, b.* , intck('month',b.datadate,a.date) as datadate_dist "Months from last datadate"

from stock a, account b
where a.permno=b.permno and 6 <= intck('month',b.datadate,a.date) <=18
order by a.permno,date,datadate_dist;
quit;

*select the closest accounting observation for each permno and date combo;
data formation;
set formation;
by permno date;
if first.date;

*Define Book to market ratio! 
-Use beginning of period market equity and BE from 6 to 18 months old)
-Unlike Fama French, we use recent Market Equity following Asness and Frazzini 2014 Devil in HML Details ;

BMR=BE/LME;

run;

*Get SIC industry code from header file in order to
remove stocks that are classified as financials because they have weird ratios (avoid sic between 6000-6999);
proc sql;
create table formation as
select a.*, b.siccd
from formation a ,my.msenames b
where a.permno=b.permno and (b.NAMEDT <= a.date <=b.NAMEENDT)
and not (6000<= b.siccd <=6999);
quit;

*******************************************************;
*Define your Anomaly (User Input required here)
*******************************************************;

*Define a Master Title that will correspond to Anomaly definition throughout output;
title1 "Gross Profit Effect";
*Start Output file;
ods pdf file="&output_path/Gross Profit Effect.pdf"; 

*Define the variable you want to sort on and define your subsample criteria
For instance, you may only want to form portfolios every July (once a year), so we would just keep 
those stocks to form our portfolios. If we build them every month we wouldn't need the restriction
;
data formation;
set formation;
by permno date;

***********************************************************************;
*Define the stock characteristics you want to sort on (SORTVAR);
***********************************************************************;
SORTVAR=GPA;
format SORTVAR 10.3;
label SORTVAR="Sort Variable: Gross Profit to Assets Ratio";

***********************************************************************;
*Define Rebalance Frequency;
***********************************************************************;
if month(date)=7; *Rebalance Annually in July;

***********************************************************************;
*Define subsample criteria
***********************************************************************;
if SORTVAR = . then delete; *must have non missing SORTVAR;
if year(date)>=1963 and year(date)<=2020; *Select Time period;
if lme>1; *market cap of at least 1 million to start from;
if lag_price<1 or lag_price=. then delete; *Remove penny stocks or stocks missing price;

***********************************************************************;
*Define portfolio_weighting technique;
***********************************************************************;
portfolio_weight=LME; *Portfolio weights: set=1 for equal weight, or set =LME for value weighted portfolio;

run;



*******************************************************;
*Define holding period, bin Order and Format
*******************************************************;
*Define Holding Period (number of months in between rebalancing dates (i.e., 1 year = 12 months);
%let holding_period = 12;

*Define number of bins;
%let bins=5;

*Define the bin ordering:;
*%let rankorder= ; 
%let rankorder=descending;


*Define a bin format for what the bin portfolios will correspond to for output;
proc format;
value bin_format 1="1. High GPA"
5="5. Low GPA"
99="Long/Short: High - Low"
;
run;

**********************Forming Portfolios and Testing Begins Here**************************************;
%include "&program_path/Subroutine_ Form Portfolios and Test Anomaly.sas";

ods pdf close;
