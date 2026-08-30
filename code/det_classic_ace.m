function Lambda = det_classic_ace(z, Rhat_train, v)
%det_classic_ace 经典 ACE（单距离门，Adaptive Coherence Estimator）
%   z  : N x 1 待检距离门数据
%   ACE 对协方差功率尺度 CFAR，适用于部分均匀环境

invR = inv(Rhat_train);
num = abs(v' * invR * z)^2;
den = real(v' * invR * v) * real(z' * invR * z);
Lambda = num / den;
end
