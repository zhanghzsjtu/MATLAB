function Z = generate_primary(R, v, alpha, epsilon, Tp)
%generate_primary 生成三个连续距离门的主数据 Z = [z_{l-1}, z_l, z_{l+1}]
%   R        : N x N 杂波协方差
%   v        : N x 1 导向矢量
%   alpha    : 目标复幅度（标量）
%   epsilon  : 残留时延，范围 [-Tp/2, Tp/2]
%   Tp       : 脉冲宽度（归一化）
%
%   Z        : N x 3 矩阵

N = size(R, 1);
Noise = generate_samples(R, 3); % 三门独立杂波

c = leakage_coeffs(epsilon, Tp); % [c_{l-1}; c_l; c_{l+1}]

Z = Noise;
for j = 1:3
    if c(j) ~= 0
        Z(:,j) = Z(:,j) + alpha * c(j) * v;
    end
end
end
