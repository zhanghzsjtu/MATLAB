function X = generate_samples(R, K)
%generate_samples 从复高斯分布 CN(0,R) 生成 N x K 样本
%   R : N x N 协方差矩阵（正定）
%   K : 样本数

N = size(R, 1);
L = chol(R, 'lower'); % R = L * L'
W = (randn(N, K) + 1j * randn(N, K)) / sqrt(2);
X = L * W;
end
