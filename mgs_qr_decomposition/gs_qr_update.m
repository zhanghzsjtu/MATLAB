function [Q_new, R_new] = gs_qr_update(Q_old, R_old, a_new)
% GS_QR_UPDATE 增量更新 QR 分解
%   [Q_new, R_new] = gs_qr_update(Q_old, R_old, a_new)
%   输入：
%       Q_old : 旧的 Q 矩阵，满足 Q_old' * Q_old = I
%       R_old : 旧的上三角矩阵
%       a_new : 新增的列向量（新选中的原子）
%   输出：
%       Q_new : 更新后的 Q 矩阵
%       R_new : 更新后的上三角矩阵
%
%   说明：该函数仅对新增列执行一次 Gram-Schmidt 正交化，
%         适合匹配追踪类算法中原子支撑集逐步扩大的场景。

[m, k_old] = size(Q_old);
k_new = k_old + 1;

% 计算新列在旧 Q 上的投影系数
r = Q_old' * a_new;                  % k_old x 1

% 计算正交残差
v = a_new - Q_old * r;               % m x 1
rho = norm(v);                       % 残差模长

if rho < 1e-12
    warning('gs_qr_update:linearDependence', ...
            '新增原子与现有支撑集近似线性相关，模长 %.2e', rho);
    q_new = zeros(m, 1);
else
    q_new = v / rho;                 % 新正交列
end

% 组装新 Q 和新 R
Q_new = [Q_old, q_new];              % m x (k_old+1)
R_new = [R_old, r;                   % (k_old+1) x (k_old+1)
         zeros(1, k_old), rho];
end
