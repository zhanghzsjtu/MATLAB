function R = generate_covariance(N, rho, sigma_n2, sigma_c2)
%generate_covariance 生成杂波协方差矩阵
%   R = sigma_n2 * I + sigma_c2 * C
%   C(i,j) = rho^{(i-j)^2}, rho 为一阶相关系数

idx = (0:N-1).' - (0:N-1);  % N x N 下标差矩阵
C = rho .^ (idx .^ 2);
R = sigma_n2 * eye(N) + sigma_c2 * C;
end
