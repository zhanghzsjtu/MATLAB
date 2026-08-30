function [Lambda, eps_hat] = det_modified_ace(Z, Rhat_train, v, eps_grid, Tp)
%det_modified_ace Modified ACE（两距离门泄漏模型，对部分均匀环境 CFAR）
%   ACE 统计量 = |v_bin^H R^{-1} z_bin|^2 / [(v_bin^H R^{-1} v_bin)(z_bin^H R^{-1} z_bin)]

invR = inv(Rhat_train);
nEps = length(eps_grid);
Lambda_e = zeros(nEps, 1);
vRv = real(v' * invR * v);

for k = 1:nEps
    eps = eps_grid(k);
    if eps == 0
        Lambda_e(k) = det_classic_ace(Z(:,2), Rhat_train, v);
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
    z_term = real(z1'*invR*z1 + z2'*invR*z2);
    den = (chi(1)^2 + chi(2)^2) * vRv * z_term;
    Lambda_e(k) = num / den;
end

[Lambda, idx] = max(Lambda_e);
eps_hat = eps_grid(idx);
end
