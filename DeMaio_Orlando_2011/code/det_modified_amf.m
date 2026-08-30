function [Lambda, eps_hat] = det_modified_amf(Z, Rhat_train, v, eps_grid, Tp)
%det_modified_amf Modified AMF（论文两距离门泄漏模型）
%   对每对相邻距离门构造有效导向 v_bin = [chi1*v; chi2*v]，
%   统计量为 |v_bin^H R^{-1} z_bin|^2 / (v_bin^H R^{-1} v_bin)。

invR = inv(Rhat_train);
nEps = length(eps_grid);
Lambda_e = zeros(nEps, 1);
vRv = real(v' * invR * v);

for k = 1:nEps
    eps = eps_grid(k);
    if eps == 0
        Lambda_e(k) = det_classic_amf(Z(:,2), Rhat_train, v);
        continue;
    end

    if eps < 0
        chi = [-eps/Tp; 1 + eps/Tp];
        z1 = Z(:,1);
        z2 = Z(:,2);
    else
        chi = [1 - eps/Tp; eps/Tp];
        z1 = Z(:,2);
        z2 = Z(:,3);
    end

    num = abs(chi(1)*v'*invR*z1 + chi(2)*v'*invR*z2)^2;
    den = (chi(1)^2 + chi(2)^2) * vRv;
    Lambda_e(k) = num / den;
end

[Lambda, idx] = max(Lambda_e);
eps_hat = eps_grid(idx);
end
