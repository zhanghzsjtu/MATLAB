function [Q, R] = gs_qr(A)
% GS_QR 基于修正 Gram-Schmidt 正交化实现 QR 分解
%   [Q, R] = gs_qr(A)
%   输入：
%       A : m x k 矩阵，列向量为待分解的原子
%   输出：
%       Q : m x k 正交矩阵，满足 Q'*Q = I
%       R : k x k 上三角矩阵
%
%   算法：修正 Gram-Schmidt，数值稳定性优于经典 Gram-Schmidt

[m, k] = size(A);
Q = zeros(m, k);
R = zeros(k, k);

for j = 1:k
    v = A(:, j);                % 当前列向量
    
    % 依次减去前面 q_i 方向上的投影
    for i = 1:j-1
        R(i, j) = Q(:, i)' * v;          % 投影系数
        v = v - R(i, j) * Q(:, i);       % 减去投影分量
    end
    
    R(j, j) = norm(v);                  % 残差二范数
    if R(j, j) < 1e-12
        warning('gs_qr:linearDependence', ...
                '第 %d 列与前面的列近似线性相关，模长 %.2e', j, R(j, j));
        Q(:, j) = 0;
    else
        Q(:, j) = v / R(j, j);           % 单位化
    end
end
end
