function irf = pvar_irf(out,s,T,infoz)

k = rows(out.b);
parms = NaN(k,1);
parms(isnan(vec(infoz.parms))) = out.b;
parms(~isnan(vec(infoz.parms))) = vec(infoz.parms(~isnan(vec(infoz.parms))));
b = reshape(parms,size(infoz.parms));

irf = zeros(T+infoz.nlags+1,out.neq);
irf(infoz.nlags+2,:) = s;

% Truncate
irf = irf(infoz.nlags+1:end,:);

for t=2:T+1
   X = mlag(irf,infoz.nlags,0);
   irf(t,:) = X(t,:)*b' + irf(t,:);
end