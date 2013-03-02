%% Set up paths
% close all; clear all; path(pathdef); clc;

% cd 'E:\Dropbox\Return_Predictability_of_Earnings\code'

%% Import data, set global variables
% load('D:\SAS\test1.mat');
% 
% addpath(genpath('E:\Applications\Matlab\packages\gmm'))
% addpath(genpath('E:\Applications\Matlab\packages\minz'))
% addpath(genpath('E:\Applications\Matlab\packages\jplv7-metrics\util'))

data = dataset('File','D:/SAS/testnew.csv','ReadVarNames',true,'ReadObsNames',false,'Delimiter',',');
data = double(data);
acc_vars = 3;

% Data indices/groups
[IDX(:,1),NG]=grp2idx(data(:,1));
[IDX(:,2),TG]=grp2idx(data(:,2));

disp('Done loading data!')

%% Construct Matrices

rho = 0.967;
Y = data(:,6:10);
X = data(:,11:15);
Z = data(:,16:20);

nlags=1; % number of lags
neq = size(Y,2);

% Accumulate matrices for each equation
% Same independent variables and instruments for each equation
X(isnan(X)) = 0;
Z(isnan(Z)) = 0;
Y(isnan(Y)) = 0;

ZX = Z'*X;

% Concatenate equations columnwise
ZY = arrayfun(@(x) Z'*Y(:,x),1:neq,'uniformOutput',false);

% System GMM
ZY_s = cat(1, ZY{:});
ZX_s = kron(eye(neq),ZX);
ZZ_s = kron(eye(neq),Z'*Z);

% Pre-allocate residuals matrix e
b1 = reshape(inv(ZX_s'*inv(ZZ_s)*ZX_s)*ZX_s'*inv(ZZ_s)*ZY_s,neq,neq)';

disp('Done constructing Matricies');

%% GMM Estimation
% GMM options
% NaN values correspond to the parameters to be estimated
% Coefficient matrix must be vectorized
% gmmopt.infoz.parms = [repmat([0 0 NaN NaN NaN],3,1); [NaN NaN NaN NaN NaN; NaN NaN NaN NaN NaN]];
gmmopt.infoz.parms = nan(5,5);
gmmopt.infoz.momt='pvar_mom';
gmmopt.infoz.nlags=nlags;
gmmopt.gmmit = 1;
gmmopt.lags = 0;
% gmmopt.null = zeros(numnan(gmmopt.infoz.parms),1);
gmmopt.null = zeros(25,1);
gmmopt.plot = 0;
gmmopt.prt = 1;

% Set initial values to null
b0 = gmmopt.null;

out = gmm(b0,gmmopt,Y,X,Z);
[m e] = pvar_mom(b1,gmmopt.infoz,[],data(:,6:10),data(:,11:15),data(:,16:20));

e(isnan(e)) = 0;

% Sandwich form weighting matrix
W = inv(1/length(NG)*Z'*e*e'*Z);

b_gmm = inv(ZX_s'*kron(eye(neq),W)*ZX_s)*ZX_s'*kron(eye(neq),W)*ZY_s;

% 2nd stage variance matrix
V = length(NG)*inv(ZX_s'*kron(eye(neq),W)*ZX_s);
std = diag(V).^0.5;

tstat = b_gmm./std;
t = reshape(out.t,neq,neq)

k = rows(b1);
parms = NaN(k,1);
parms(isnan(vec(gmmopt.infoz.parms))) = b1;
parms(~isnan(vec(gmmopt.infoz.parms))) = vec(gmmopt.infoz.parms(~isnan(vec(gmmopt.infoz.parms))));
b = reshape(parms,size(gmmopt.infoz.parms))

disp('Done running GMM');

%% Pretty Output
badzmtb = data(:,18);
zmtb = badzmtb(~isnan(badzmtb));
nzmtb = data(~isnan(badzmtb),5);
phi = (zmtb'*zmtb)\zmtb'*nzmtb;

str = '';
lrKs = 2.^linspace(0,6,7);
lrBs = zeros(length(lrKs),4);
for lrN = drange(1:length(lrKs))
    lrBs(lrN,3) = rho^lrKs(lrN)*phi^lrKs(lrN);
    lrBs(lrN,1:2) = [b1(1,3)*(1-lrBs(lrN,3))/(1-phi*rho),b1(2,3)*(1-lrBs(lrN,3))/(1-phi*rho)];
    lrBs(lrN,4)=sum(abs(lrBs(lrN,1:3)));
    str = [str sprintf('%d & %0.2f & %0.2f & %0.2f & %0.2f \\\\\n',[lrKs(lrN),lrBs(lrN,:)])];
end
disp(str)

% print out full pvar table
str = '';
for row = drange(1:length(b))
    strb = '';
    strt = '';
    for col = drange(1:length(b(row,:)))
        sig = '';
        if abs(t(row,col)) >= 3.1
            sig = '***';
        elseif abs(t(row,col)) >= 2.6
            sig = '**';
        elseif abs(t(row,col)) >= 1.96
            sig = '*';
        end
        strb = [strb sprintf('& %0.3f\\\\sym{%s} ',b(row,col),sig)];
        strt = [strt sprintf('& (%0.2f) ',t(row,col))];
    end
    str = [str '%s ' strb sprintf('\\\\\\\\\n  ') strt sprintf('\\\\\\\\\n')];
end
disp(sprintf(str,'$r_{t+1}$','$e_{t+1}$','$mb_{t+1}$','$c_{t+1}$' ,'$a_{t+1}$'))
% ,'$c_{t+1}$','$a_{t+1}$'

%% Impulse Responses
s.e = [0 1 0 0 0 0]; % shock 1 (e shock)
s.mb = [-rho 0 1 0 0 0]; % shock 2 (mtb or E[r] shock)
s.c = [0 0 0 0 1 0]; % shock 2 (cashflow shock)
s.a = [0 0 0 0 0 1]; % shock 2 (accruals shock)

T_irf = 10; 

irf1 = pvar_irf(out,s.e,T_irf,gmmopt.infoz);
irf2 = pvar_irf(out,s.mb,T_irf,gmmopt.infoz);
irf3 = pvar_irf(out,s.c,T_irf,gmmopt.infoz);
irf4 = pvar_irf(out,s.a,T_irf,gmmopt.infoz);

% Replace dp with p
% \delta p_{t} = p_{t+1} - p_{t} = -(d_{t+1} - p_{t+1}) + (d_{t} -
% p_{t}) + \delta d_{t+1}
irf1(2:end,3) = irf1(2:end,3) - irf1(1:end-1,3) ;
irf2(2:end,3) = irf2(2:end,3) - irf2(1:end-1,3) ;
irf3(2:end,3) = irf3(2:end,3) - irf3(1:end-1,3) ;
irf4(2:end,3) = irf4(2:end,3) - irf4(1:end-1,3) ;

crf1 = cumsum(irf1);
crf2 = cumsum(irf2);
crf3 = cumsum(irf3);
crf4 = cumsum(irf4);

popts.big.linewidth = 4;
popts.big.MarkerSize = 2;
popts.small.linewidth = 4;
popts.small.MarkerSize = 1;
popts.r = '-k';
popts.e = '-.kd';
popts.mb = '--k';
popts.c = '-.k';
popts.a = '-k';

% Plot impulse responses


% Impulse response to Profitability (e)
fg1 = figure(1);
clf(fg1);
% subplot(4,2,1);
% hold on;grid off;
% plot(0:T_irf, irf1(:,1),popts.r,popts.small);% r
% % plot(0:T_irf, irf1(:,2),popts.e,popts.big);% e
% plot(0:T_irf, irf1(:,3),popts.mb,popts.small);% mb
% % plot(0:T_irf, irf1(:,4),popts.c,popts.small);% c
% % plot(0:T_irf, irf1(:,5),popts.a,popts.small);% a
% %     axis([0 T_irf -0.1 1.0]); 
% % legend('r','mb','Location','NorthEast'); 
% title('Response to Profitability (e) shock'); 
% hold off;
% 
% % Impulse response to Price/Returns (\rhomb, r)
% subplot(4,2,3);
% hold on;grid off; 
% plot(0:T_irf, irf2(:,1),popts.r,popts.small);% r
% plot(0:T_irf, irf2(:,2),popts.e,popts.big);% e
% plot(0:T_irf, irf2(:,3),popts.mb,popts.small);% mb
% % plot(0:T_irf, irf2(:,4),popts.c,popts.small);% c
% % plot(0:T_irf, irf2(:,5),popts.a,popts.small);% a
% %     axis([0 T_irf -0.2 .5]); 
% % legend('r','e','mb','Location','NorthEast'); 
% title('Response to Price (mb) shock'); 
% hold off;

% Impulse response to Cash Flows (c)
subplot(2,2,1);
hold on;grid off; 
plot(0:T_irf, irf3(:,1),popts.r,popts.small);% r
plot(0:T_irf, irf3(:,2),popts.e,popts.big);% e
% plot(0:T_irf, irf3(:,3),popts.mb,popts.small);% mb
% plot(0:T_irf, irf3(:,4),popts.c,popts.small);% c
% plot(0:T_irf, irf3(:,5),popts.a,popts.small);% a
% legend('r','e','mb','Location','NorthEast'); 
title('Response to Cash Flows (c) shock'); 
hold off;

% Impulse response to Accruals (a)
subplot(2,2,3);
hold on;grid off; 
plot(0:T_irf, irf4(:,1),popts.r,popts.small);% r
plot(0:T_irf, irf4(:,2),popts.e,popts.big);% e
plot(0:T_irf, irf4(:,3)-100,popts.mb,popts.small);% mb
% plot(0:T_irf, irf4(:,4),popts.c,popts.small);% c
% plot(0:T_irf, irf4(:,5),popts.a,popts.small);% a
    axis([0 T_irf -0.4 .2]); 
legend('Return (r)','Profitability (e)','Market-to-Book (mb)','Location','East','Orientation','horizontal'); 
title('Response to Accruals (a) shock'); 
hold off;


% Cumulative Responses

% Cumulative response to Profitability (e)
% subplot(4,2,2);
% hold on;grid off; 
% plot(0:T_irf, crf1(:,1),popts.r,popts.small);% r
% % plot(0:T_irf, crf1(:,2),popts.e,popts.big);% e
% plot(0:T_irf, crf1(:,3),popts.mb,popts.small);% mb
% % plot(0:T_irf, crf1(:,4),popts.c,popts.small);% c
% % plot(0:T_irf, crf1(:,5),popts.a,popts.small);% a
% %     axis([0 T_irf -0.1 1.5]); 
% % legend('r','mb','Location','East'); 
% title('Cumulative response to Profitability (e) shock');
% hold off;
% 
% % Cumulative response to Price/Returns (rho*mb, r)
% subplot(4,2,4);
% hold on;grid off; 
% % plot(0:T_irf, crf2(:,1),popts.r,popts.small);% r
% plot(0:T_irf, crf2(:,2),popts.e,popts.big);% e
% plot(0:T_irf, crf2(:,3),popts.mb,popts.small);% mb
% % plot(0:T_irf, crf2(:,4),popts.c,popts.small);% c
% % plot(0:T_irf, crf2(:,5),popts.a,popts.small);% a
% % legend('r','e','Location','East'); 
% title('Cumulative response to Price (mb) shock'); 
% hold off;

% Cumulative response to Cash Flows (c) and Accruals (a)
subplot(2,2,[2 4]);
hold on;grid on;
h(1)=plot(0:T_irf, crf3(:,1),popts.r,popts.small);% r
h(2)=plot(0:T_irf, crf3(:,2),popts.e,popts.big);% e
h(3)=plot(0:T_irf, crf3(:,3),popts.mb,popts.small);% mb
h(4)=plot(0:T_irf, crf4(:,1),popts.r,popts.small);% r
h(5)=plot(0:T_irf, crf4(:,2),popts.e,popts.big);% e
h(6)=plot(0:T_irf, crf4(:,3),popts.mb,popts.small);% mb
% plot(0:T_irf, crf3(:,4),popts.c,popts.small);% c
% plot(0:T_irf, crf3(:,5),popts.a,popts.small);% a
ah1 = gca;
ah2=axes('position',get(gca,'position'), 'visible','off');
set(h(4:6),'Color',[0.5,0.5,0.5])
set(ah1,'XGrid','off','YGrid','on','ZGrid','off')
legend(h([1,4]), 'Cash Flow', 'Accruals','Location','SouthEast');
title(ah1,'Cumulative response to cash flow and accrual shocks'); 
hold off;

% print -depsc2 graphs/var_irf_monthly.eps;

%% Simulate crazy impulsiveness!

select_proportion=.5;
num_of_sims = 100;
firm_nums = [1:length(NG)]';
sim_results = zeros(length(b),length(b(1,:)),num_of_sims);
sim_a_ifr = zeros(length(irf3),length(irf3(1,:)),num_of_sims);
sim_c_ifr = zeros(length(irf4),length(irf4(1,:)),num_of_sims);

%start sim loop
for sim_loop_num = drange(1:num_of_sims)
    selected_firms = firm_nums(rand(1,length(firm_nums))>select_proportion);
    data_selector = ismember(IDX(:,1),selected_firms);

    sY = Y(data_selector,:);
    sX = X(data_selector,:);
    sZ = Z(data_selector,:);

    sneq = size(sY,2);
    tmpout.neq = sneq;

    % Accumulate matrices for each equation
    % Same independent variables and instruments for each equation

    sZX = sZ'*sX;

    % Concatenate equations columnwise
    sZY = arrayfun(@(x) sZ'*sY(:,x),1:sneq,'uniformOutput',false);

    % System GMM
    sZY_s = cat(1, sZY{:});
    sZX_s = kron(eye(sneq),sZX);
    sZZ_s = kron(eye(sneq),sZ'*sZ);

    % Pre-allocate residuals matrix e
    sim_results(:,:,sim_loop_num) = reshape(inv(sZX_s'*inv(sZZ_s)*sZX_s)*sZX_s'*inv(sZZ_s)*sZY_s,sneq,sneq)';
    tmpout.b = sim_results(:,:,sim_loop_num);
    sim_a_ifr(:,:,sim_loop_num) = pvar_irf(tmpout,s.a,T_irf,gmmopt.infoz);
    sim_c_ifr(:,:,sim_loop_num) = pvar_irf(tmpout,s.c,T_irf,gmmopt.infoz);
end
sim_results = sort(sim_results,3);
sim_a_ifr = sort(sim_a_ifr,3);
sim_c_ifr = sort(sim_c_ifr,3);

ave_sb=mean(sim_results,3)
p5_sb=sim_results(:,:,floor(num_of_sims*.05))
p95_sb=sim_results(:,:,floor(num_of_sims*.95))

c_a_ifr(:,:,1) = sim_a_ifr(:,:,floor(num_of_sims*.05))
c_a_ifr(:,:,2)=mean(sim_a_ifr,3)
c_a_ifr(:,:,3) = sim_a_ifr(:,:,floor(num_of_sims*.95))

sfg1 = figure(2);
clf(sfg1);
hold on;grid off;
plot(0:T_irf, c_a_ifr(:,1,1),popts.e,popts.small);
plot(0:T_irf, c_a_ifr(:,1,2),popts.r,popts.big);
plot(0:T_irf, c_a_ifr(:,1,3),popts.e,popts.small);

disp('Code ran!');
