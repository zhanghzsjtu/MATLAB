function [Lambda, eps_hat] = det_modified_gasd(Z, Rhat_train, v, eps_grid, Tp)
%det_modified_gasd Modified GASD (论文式 49)
%   对相邻 3 个距离门 (z_{l-1}, z_l, z_{l+1}) 中所有 C(3,2)=3 个 cell pair，
%   对每个 pair 计算 Bidon 2011 广义 ACE/ASD：
%
%     GASD_{i,j} = |v^H R^-1 z_i|^2 + |v^H R^-1 z_j|^2
%                  ----------------------------------------------
%                  (v^H R^-1 v) * (z_i^H R^-1 z_i + z_j^H R^-1 z_j)
%
%   然后取 3 个 pair 的最大值作为 M-GASD 统计量。
%   与 M-ACE 相比，分母少了常数 1；对部分均匀环境仍具有 CFAR 性质（论文附录）。

    invR = inv(Rhat_train);
    vRv = real(v' * invR * v);

    vRz1 = v' * invR * Z(:,1);
    vRz2 = v' * invR * Z(:,2);
    vRz3 = v' * invR * Z(:,3);
    z1Rz1 = real(Z(:,1)' * invR * Z(:,1));
    z2Rz2 = real(Z(:,2)' * invR * Z(:,2));
    z3Rz3 = real(Z(:,3)' * invR * Z(:,3));

    num12 = abs(vRz1)^2 + abs(vRz2)^2;
    num13 = abs(vRz1)^2 + abs(vRz3)^2;
    num23 = abs(vRz2)^2 + abs(vRz3)^2;

    den12 = vRv * (z1Rz1 + z2Rz2);
    den13 = vRv * (z1Rz1 + z3Rz3);
    den23 = vRv * (z2Rz2 + z3Rz3);

    Lambda_pair = max([num12/den12, num13/den13, num23/den23]);
    Lambda = Lambda_pair;
    eps_hat = 0;
end
