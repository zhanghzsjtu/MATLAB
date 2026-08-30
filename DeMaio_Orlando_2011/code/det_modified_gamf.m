function [Lambda, eps_hat] = det_modified_gamf(Z, Rhat_train, v, eps_grid, Tp)
%det_modified_gamf Modified GAMF (论文式 48)
%   对相邻 3 个距离门 (z_{l-1}, z_l, z_{l+1}) 中所有 C(3,2)=3 个 cell pair，
%   对每个 pair 计算 Bidon 2011 广义 AMF：
%
%     GAMF_{i,j} = |v^H R^-1 z_i|^2 + |v^H R^-1 z_j|^2
%                  ----------------------------------
%                       v^H R^-1 v
%
%   然后取 3 个 pair 的最大值作为 M-GAMF 统计量。

    invR = inv(Rhat_train);
    vRv = real(v' * invR * v);

    vRz1 = v' * invR * Z(:,1);
    vRz2 = v' * invR * Z(:,2);
    vRz3 = v' * invR * Z(:,3);

    num12 = abs(vRz1)^2 + abs(vRz2)^2;
    num13 = abs(vRz1)^2 + abs(vRz3)^2;
    num23 = abs(vRz2)^2 + abs(vRz3)^2;

    Lambda_pair = max([num12, num13, num23]) / vRv;
    Lambda = Lambda_pair;
    eps_hat = 0;
end
