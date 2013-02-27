function [m,e] = pvar_mom(b,infoz,stat,Y,X,Z)

% Pre-allocate residuals matrix e
e = zeros(size(Y));
e(1,:) = Y(1,:);

k = rows(b);
T = size(Y,1);
n = size(Y,2);

% Construct parameter matrix with restrictions
if ~isfield(infoz,'parms')
    b = reshape(b,n,k/n);
else
    parms = NaN(k,1);
    parms(isnan(vec(infoz.parms))) = b;
    parms(~isnan(vec(infoz.parms))) = vec(infoz.parms(~isnan(vec(infoz.parms))));
    b = reshape(parms,size(infoz.parms));
end

for t=2:T
    e(t,:) = Y(t,:) - X(t,:)*b';
end

% m = e/rows(e);
m = vec(Z'*e/rows(e));