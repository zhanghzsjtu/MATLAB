function truth = get_truth(p, T_j, T_s, G)
% get_truth  计算各子脉冲是否被间歇采样转发干扰 (真值, 用于准确率统计)
%   判定依据: 干扰时隙 [tau_j + n*T_s + g*T_j, +T_j] 与目标回波第 k 个子脉冲
%   时窗 [tau_t + (k-1)*T_pp, tau_t + k*T_pp] 的重叠时长是否超过半个子脉冲宽度。
%
%   输入: p    参数结构体
%         T_j  干扰采样宽度
%         T_s  间歇采样重复周期
%         G    重复转发次数
%   输出: truth (1 x K) logical, true=该子脉冲被干扰

K = p.K;
T_pp = p.T_pp;
tau_t = p.tau_t;
tau_j = p.tau_j;

n_sub = round(T_pp * p.fs);
T_p = K * T_pp;

% 干扰采样次数 P = floor(T_p/T_s) + 1 (覆盖整个脉宽)
P = floor(T_p / T_s) + 1;

% 干扰时隙相对目标回波起点的时延差
d_tau = tau_j - tau_t;          % = -4 us (干扰机前置 600 m)

truth = false(1, K);
for k = 1:K
    % 目标回波第 k 个子脉冲时窗 [t1, t2] (相对目标回波起点)
    t1 = (k-1) * T_pp;
    t2 = k * T_pp;
    overlap = 0;
    for n = 0:P-1
        for g = 0:G-1
            s1 = d_tau + n*T_s + g*T_j;      % 干扰时隙起点 (相对目标回波起点)
            s2 = s1 + T_j;
            ov = min(t2, s2) - max(t1, s1);  % 重叠时长
            overlap = overlap + max(0, ov);
        end
    end
    if overlap > 0.5 * T_pp
        truth(k) = true;
    end
end

end
