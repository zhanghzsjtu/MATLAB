function c = leakage_coeffs(epsilon, Tp)
%leakage_coeffs 矩形脉冲在 f=0 时的三距离门泄漏系数
%   按论文 (33) 的 piecewise 模型：
%   当 -Tp/2 <= epsilon < 0 时，能量泄漏到 z_{l-1} 和 z_l
%   当 0 <= epsilon <= Tp/2 时，能量泄漏到 z_l 和 z_{l+1}
%
%   输出 c = [c_{l-1}; c_l; c_{l+1}]

if epsilon < 0
    c_lm = -epsilon / Tp;       % |epsilon|/Tp
    c_l  = 1 + epsilon / Tp;    % 1 - |epsilon|/Tp
    c_lp = 0;
else
    c_lm = 0;
    c_l  = 1 - epsilon / Tp;
    c_lp = epsilon / Tp;
end

c = [c_lm; c_l; c_lp];
end
