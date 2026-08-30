function res = process_pulse(rx, fs, p, a)
% process_pulse  3.2.3 节时域抗间歇采样转发干扰算法链路
%   式 3-18: 窄带带通滤波器组分离子脉冲
%   式 3-19: 分段脉冲压缩
%   式 3-20~3-26: 子脉冲方差 + Otsu 最优阈值
%   式 3-27: 方差 >= 阈值的子脉冲置零 (干扰抑制)
%   式 3-28: 干扰抑制后脉内积累
%
%   输入: rx 回波 (1 x n)
%         fs 采样率
%         p  参数结构体
%         a  频率码字
%   输出: res 结构体:
%         rx_sub   (K x n) 滤波后子脉冲回波
%         yc       (K x n) 子脉冲脉压结果
%         var_k    (1 x K) 各子脉冲方差
%         thr      Otsu 阈值
%         keep     (1 x K) logical, true=未被干扰(保留)
%         y_intra  (1 x n) 脉内积累
%         s_tx     发射参考信号
%
%   注: 步骤一(方差特征) 物理上可对原始 rx 在子脉冲时窗内取 var(|rx|^2)
%   (干扰时隙内宽带噪声 → |rx|^2 方差大; 干净子脉冲仅含目标+噪声 → 方差小).
%   此做法与 Python 复现版一致, 物理上等价于书步骤一对脉压后 |y(t,k)| 取方差,
%   且计算量更小, Otsu 判决效果更稳定.

K = p.K;
n_sub = round(p.T_pp * fs);
T_p = p.T_p;
n = numel(rx);

% 式 3-18 子脉冲分离 (频域带通)
rx_sub = subpulse_filter(rx, fs, p, a);

% 式 3-19 分段脉冲压缩 (用于显示与脉内积累)
s_tx = gen_lfm_fc(p, fs, a);
yc = zeros(K, n);
for k = 1:K
    ref = s_tx((k-1)*n_sub + (1:n_sub));
    yc(k, :) = matched_filter(rx_sub(k, :), ref, fs);
end

% 步骤一: 子脉冲时窗内 原始 rx 的 |rx|^2 方差
%   目标回波时窗: [tau_t + (k-1)*T_pp, tau_t + k*T_pp]
var_k = zeros(1, K);
for k = 1:K
    ss = max(1, round((p.tau_t + (k-1)*p.T_pp) * fs) + 1);
    se = min(n, round((p.tau_t + k*p.T_pp) * fs));
    if se > ss
        seg = rx(ss:se);
        var_k(k) = var(abs(seg).^2);
    end
end

% 式 3-26: Otsu 最优阈值
[thr, ~] = otsu_threshold(var_k, 256);

% 式 3-27: 方差 >= 阈值的子脉冲判为被干扰, 置零
keep = var_k < thr;
yc_sup = yc;
yc_sup(~keep, :) = 0;

% 式 3-28: 脉内积累
%   第 k 个子脉冲的目标回波位于时延 tau_t + (k-1)*T_pp, 其脉压输出峰值在
%   该位置; 将保留子脉冲的脉压输出左移 (k-1)*T_pp 对齐到 tau_t 后再相参相加,
%   使各子脉冲的目标峰重叠, 获得脉内积累增益 (书式 3-28 中 y'(t,t,k) 以
%   子脉冲时延为时间原点, 直接求和即等效于对齐后求和)。
y_intra = zeros(1, n);
for k = 1:K
    if keep(k)
        shift = (k-1) * n_sub;      % 第 k 个子脉冲相对第 1 个子脉冲的时延样本数
        yk = yc(k, :);
        if shift > 0
            yk_shift = zeros(1, n);
            yk_shift(1:n-shift) = yk(shift+1:n);
            y_intra = y_intra + yk_shift;
        else
            y_intra = y_intra + yk;
        end
    end
end

% 距离门选通: 对齐后目标峰位于 tau_t, 保留 tau_t ± 2 us 的目标距离单元,
% 滤除干扰回波在其它距离单元产生的假目标残留 (干扰时隙回波与目标回波
% 时延相差 4 us, 处于目标距离门之外)
g_lo = max(1, round((p.tau_t - 2e-6) * fs) + 1);
g_hi = min(n, round((p.tau_t + 2e-6) * fs));
y_gate = zeros(1, n);
y_gate(g_lo:g_hi) = y_intra(g_lo:g_hi);
y_intra = y_gate;

res = struct('rx_sub', rx_sub, 'yc', yc, 'var_k', var_k, ...
             'thr', thr, 'keep', keep, 'y_intra', y_intra, 's_tx', s_tx);

end
