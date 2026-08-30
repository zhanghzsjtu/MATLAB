function Lambda = det_classic_kelly(z, Rhat_train, K, v)
%det_classic_kelly 经典 Kelly GLRT（单距离门）
%   z  : N x 1 待检距离门数据

z = z(:);
v = v(:);
S = K * Rhat_train + z * z';
invS = inv(S);
z_term = real(z' * invS * z);
num = abs(v' * invS * z)^2;
den = real(v' * invS * v);
Lambda = (1 + z_term) / (1 + z_term - num / den);
end
