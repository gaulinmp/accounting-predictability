%% Set up paths
close all; clear all; path(pathdef); clc;

cd 'E:\Dropbox\Research\Return_Predictability_of_Earnings\code'

%% Import data, set global variables
load('D:\pvar\test4.mat');
% load('E:\Dropbox\Return_Predictability_of_Earnings\data\02_accdata.mat');

% data = dataset('File','E:\Dropbox\Research\Return_Predictability_of_Earnings\data\testnew.csv','ReadVarNames',true,'ReadObsNames',false,'Delimiter',',');
% data = double(data);

addpath(genpath('E:\Applications\Matlab\packages\gmm'))
addpath(genpath('E:\Applications\Matlab\packages\minz'))
addpath(genpath('E:\Applications\Matlab\packages\jplv7-metrics\util'))

% Data indices/groups
[IDX(:,1),NG]=grp2idx(data(:,1));
[IDX(:,2),TG]=grp2idx(data(:,2));

%% Construct Matrices

rho = 0.967;
y = data(:,3:5);
Y = data(:,6:8);
X = data(:,9:11);
Z = data(:,12:14);

nlags=1; % number of lags
neq = size(Y,2);

% Accumulate matrices for each equation
% Same independent variables and instruments for each equation
y(isnan(y)) = 0;
Y(isnan(Y)) = 0;
X(isnan(X)) = 0;
Z(isnan(Z)) = 0;

ZX = Z'*X;

% Concatenate equations columnwise
ZY = arrayfun(@(x) Z'*Y(:,x),1:neq,'uniformOutput',false);

% System GMM
ZY_s = cat(1, ZY{:});
ZX_s = kron(eye(neq),ZX);
ZZ_s = kron(eye(neq),Z'*Z);

% Compute sandwich form estimator
b1 = reshape(inv(ZX_s'*inv(ZZ_s)*ZX_s)*ZX_s'*inv(ZZ_s)*ZY_s,neq,neq)';

% Compute AR1 terms
phi = arrayfun(@(x) (Z(:,x)'*Z(:,x))\(Z(:,x)'*y(:,x)),1:neq,'uniformOutput',false);
phi = diag(cat(1,phi{:}));

% Compute Long-Horizon Coefficients
e1 = [1 0 0];
lrB = zeros(neq,neq,100);
lrB(:,:,1) = b1;
for k = 2:100
    lrB(:,:,k) = b1*rho^(k-1)*phi^(k-1) + lrB(:,:,k-1);
end

(1-rho*phi(3,3))\b1
%%

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

% k = rows(b1);
% parms = NaN(k,1);
% parms(isnan(vec(gmmopt.infoz.parms))) = b1;
% parms(~isnan(vec(gmmopt.infoz.parms))) = vec(gmmopt.infoz.parms(~isnan(vec(gmmopt.infoz.parms))));
% b = reshape(parms,size(gmmopt.infoz.parms))


badzmtb = data(:,18);
zmtb = badzmtb(~isnan(badzmtb));
nzmtb = data(~isnan(badzmtb),5);
phi = (zmtb'*zmtb)\zmtb'*nzmtb;

lrN = 10;


%% Impulse Responses
s.e = [0 1 0 0 0]; % shock 1 (e shock)
s.mb = [-rho 0 1 0 0]; % shock 2 (mtb or E[r] shock)
s.c = [0 0 0 1 0]; % shock 2 (cashflow shock)
s.a = [0 0 0 0 1]; % shock 2 (accruals shock)

T_irf = 10; 

irf1 = pvar_irf(out,s.e,T_irf,gmmopt.infoz);
irf2 = pvar_irf(out,s.mb,T_irf,gmmopt.infoz);
irf3 = pvar_irf(out,s.c,T_irf,gmmopt.infoz);
irf4 = pvar_irf(out,s.a,T_irf,gmmopt.infoz);

% Replace dp with p
% \delta p_{t} = p_{t+1} - p_{t} = -(d_{t+1} - p_{t+1}) + (d_{t} -
% p_{t}) + \delta d_{t+1}
irf1(2:end,3) = -irf1(2:end,3) + irf1(1:end-1,3) + irf1(2:end,2);
irf2(2:end,3) = -irf2(2:end,3) + irf2(1:end-1,3) + irf2(2:end,2);
irf3(2:end,3) = -irf3(2:end,3) + irf3(1:end-1,3) + irf3(2:end,2);
irf4(2:end,3) = -irf4(2:end,3) + irf4(1:end-1,3) + irf4(2:end,2);

crf1 = cumsum(irf1);
crf2 = cumsum(irf2);
crf3 = cumsum(irf3);
crf4 = cumsum(irf4);

% Plot impulse responses
figure;
subplot(4,2,1);
plot(0:T_irf, irf1(:,1),'-bv','linewidth',1.5,'MarkerSize',2);
hold on;
plot(0:T_irf, irf1(:,2),'-ro','linewidth',1.25,'MarkerSize',2);
plot(0:T_irf, irf1(:,3),'-mo','linewidth',1.25,'MarkerSize',2);
plot(0:T_irf, irf1(:,4),'-gd','linewidth',1.25,'MarkerSize',2);
plot(0:T_irf, irf1(:,5),'-kv','linewidth',1.25,'MarkerSize',2);
grid on;
%axis([0 25 0 .04]); 
legend('r','e','c','a','Location','NorthEast'); 
title('Response to e shock'); 

subplot(4,2,2);
plot(0:T_irf, crf1(:,1),'-bv','linewidth',1.5,'MarkerSize',2);
hold on;
plot(0:T_irf, crf1(:,2),'-ro','linewidth',1.25,'MarkerSize',2);
plot(0:T_irf, crf1(:,3),'-mo','linewidth',1.25,'MarkerSize',2);
% plot(0:T_irf, crf1(:,4),'-gd','linewidth',1.25);
% plot(0:T_irf, crf1(:,5),'-kv','linewidth',1.25);
grid on;
%axis([0 25 0 0.2]); 
legend('d','p','Location','SouthEast'); 
title('Cumulative response to \Deltad shock'); 

subplot(4,2,3);
plot(0:T_irf, irf2(:,1),'-bv','linewidth',1.5,'MarkerSize',2);
hold on;
plot(0:T_irf, irf2(:,2),'-ro','linewidth',1.25,'MarkerSize',2);
plot(0:T_irf, irf2(:,3),'-mo','linewidth',1.25,'MarkerSize',2);
plot(0:T_irf, irf2(:,4),'-gd','linewidth',1.25,'MarkerSize',2);
plot(0:T_irf, irf2(:,5),'-kv','linewidth',1.25,'MarkerSize',2);
grid on;
%axis([0 25 -1 .01]); 
legend('r','\Deltad','fc','Location','SouthEast'); 
title('Response to dp shock'); 

subplot(4,2,4);
plot(0:T_irf, crf2(:,1),'-bv','linewidth',1.5,'MarkerSize',2);
hold on;
plot(0:T_irf, crf2(:,2),'-ro','linewidth',1.25,'MarkerSize',2);
plot(0:T_irf, crf2(:,3),'-mo','linewidth',1.25);
% plot(0:T_irf, crf2(:,4),'-gd','linewidth',1.25);
% plot(0:T_irf, crf2(:,5),'-kv','linewidth',1.25);
grid on;
%axis([0 25 -1 .01]); 
legend('d','p','fc','Location','East'); 
title('Cumulative response to dp shock'); 

subplot(4,2,5);
plot(0:T_irf, irf3(:,1),'-bv','linewidth',1.5,'MarkerSize',2);
hold on;
plot(0:T_irf, irf3(:,2),'-ro','linewidth',1.25,'MarkerSize',2);
plot(0:T_irf, irf3(:,3),'-mo','linewidth',1.25,'MarkerSize',2);
% plot(0:T_irf, irf3(:,4),'-gd','linewidth',1.25,'MarkerSize',2);
plot(0:T_irf, irf3(:,5),'-kv','linewidth',1.25,'MarkerSize',2);
grid on;
%axis([0 25 -1 .01]); 
legend('\Deltad','\Deltap','fc','Location','NorthEast'); 
title('Response to fundamental correlation shock'); 

subplot(4,2,6);
plot(0:T_irf, crf3(:,1),'-bv','linewidth',1.5,'MarkerSize',2);
hold on;
plot(0:T_irf, crf3(:,2),'-ro','linewidth',1.25,'MarkerSize',2);
plot(0:T_irf, crf3(:,3),'-mo','linewidth',1.25);
% plot(0:T_irf, crf3(:,4),'-gd','linewidth',1.25);
%plot(0:T_irf, crf3(:,5),'-kv','linewidth',1.25);
grid on;
%axis([0 25 -1 .01]); 
legend('d','p','Location','NorthEast'); 
title('Cumulative response to fundamental correlation shock'); 

subplot(4,2,7);
plot(0:T_irf, irf4(:,1),'-bv','linewidth',1.5,'MarkerSize',2);
hold on;
plot(0:T_irf, irf4(:,2),'-ro','linewidth',1.25,'MarkerSize',2);
plot(0:T_irf, irf4(:,3),'-mo','linewidth',1.25,'MarkerSize',2);
plot(0:T_irf, irf4(:,4),'-gd','linewidth',1.25,'MarkerSize',2);
% plot(0:T_irf, irf4(:,5),'-kv','linewidth',1.25,'MarkerSize',2);
grid on;
%axis([0 25 -1 .01]); 
legend('\Deltad','\Deltap','fc','Location','NorthEast'); 
title('Response to fundamental correlation shock'); 

subplot(4,2,8);
plot(0:T_irf, crf4(:,1),'-bv','linewidth',1.5,'MarkerSize',2);
hold on;
plot(0:T_irf, crf4(:,2),'-ro','linewidth',1.25,'MarkerSize',2);
plot(0:T_irf, crf4(:,3),'-mo','linewidth',1.25);
%plot(0:T_irf, crf4(:,4),'-gd','linewidth',1.25);
% plot(0:T_irf, crf4(:,5),'-kv','linewidth',1.25);
grid on;
%axis([0 25 -1 .01]); 
legend('d','p','Location','NorthEast'); 
title('Cumulative response to fundamental correlation shock'); 

% print -depsc2 graphs/var_irf_monthly.eps;