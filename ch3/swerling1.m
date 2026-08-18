function A = swerling1(rng_state)
% swerling1  Swerling I 目标幅度起伏 (脉间独立)
%   幅度 A 服从瑞利分布, 归一化使 E[|A|^2] = 1
%   输入: rng_state 随机种子 (整数)
%   输出: A 目标幅度 (标量)

rng(rng_state);
% Rayleigh: A = sqrt(X1^2 + X2^2)/sqrt(2), X1,X2 ~ N(0,1)
x1 = randn; x2 = randn;
A = sqrt(x1^2 + x2^2) / sqrt(2);

end
