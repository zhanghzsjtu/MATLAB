function [Lambda, eps_hat] = det_modified_dtglrt(Z, Rhat_train, v, eps_grid, Tp)
%det_modified_dtglrt Modified DT-GLRT (论文式 47)
%   对相邻 3 个距离门 (z_{l-1}, z_l, z_{l+1}) 中所有 C(3,2)=3 个 cell pair，
%   对每个 pair 计算 Conte 1995 分布式目标 GLRT：
%
%     DT-GLRT_{i,j} = |v^H R^-1 z_i|^2 + |v^H R^-1 z_j|^2
%                     ------------------------------------------------
%                     (v^H R^-1 v) * (1 + z_i^H R^-1 z_i + z_j^H R^-1 z_j)
%
%   然后取 3 个 pair 的最大值作为 M-DT-GLRT 统计量。
%   eps_grid 在此不参与决策，只在 eps=0 时退化为经典单 cell DT-GLRT（与经典 Kelly 一致）。

    invR = inv(Rhat_train);
    nEps = length(eps_grid);
    Lambda_e = zeros(nEps, 1);
    vRv = real(v' * invR * v);

    % 三个 cell 的中间变量
    vRz1 = v' * invR * Z(:,1);
    vRz2 = v' * invR * Z(:,2);
    vRz3 = v' * invR * Z(:,3);
    z1Rz1 = real(Z(:,1)' * invR * Z(:,1));
    z2Rz2 = real(Z(:,2)' * invR * Z(:,2));
    z3Rz3 = real(Z(:,3)' * invR * Z(:,3));

    % 3 个 cell pair: (1,2), (1,3), (2,3)
    num12 = abs(vRz1)^2 + abs(vRz2)^2;
    num13 = abs(vRz1)^2 + abs(vRz3)^2;
    num23 = abs(vRz2)^2 + abs(vRz3)^2;

    den12 = vRv * (1 + z1Rz1 + z2Rz2);
    den13 = vRv * (1 + z1Rz1 + z3Rz3);
    den23 = vRv * (1 + z2Rz2 + z3Rz3);

    % 论文式 47: M-DT-GLRT = max over pairs of DT-GLRT
    Lambda_pair = max([num12/den12, num13/den13, num23/den23]);
    Lambda = Lambda_pair;   % 与 eps 无关
    eps_hat = 0;
end
