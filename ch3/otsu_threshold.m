function [thr, sigma_b] = otsu_threshold(v, n_bins)
% otsu_threshold  式 3-20 ~ 3-26 最大类间方差法 (Otsu) 自适应阈值
%   输入: v      一维实数数组 (子脉冲脉压后幅值方差, 长度为 N*K 或 K)
%         n_bins 直方图量化区间数 I (书中步骤一)
%   输出: thr    最优阈值 g* (式 3-26)
%         sigma_b 对应的最大类间方差
%
%   步骤一: 将 [min(v), max(v)] 均匀分为 I 个子区间, 幅值量化为区间中心 g_i;
%   步骤二: 概率 p(g_i) = f_i / (N*K)   (式 3-20);
%   步骤三: 阈值 g_eta 将 g_i 划分为集合 A (g_i<=g_eta) 与 B (g_i>g_eta),
%           概率 w0, w1   (式 3-21, 3-22);
%   步骤四: 平均幅值 λ0, λ1, λ  (式 3-23, 3-24, 3-25);
%   步骤五: 类间方差 σ^2(g) = w0(λ0-λ)^2 + w1(λ1-λ)^2, 使 σ^2 最大的 g 为最优阈值 (式 3-26).

if nargin < 2
    n_bins = 256;
end

v = v(isfinite(v));
if numel(v) < 2
    thr = median(v); sigma_b = 0; return;
end

vmin = min(v); vmax = max(v);
if vmax <= vmin
    thr = vmin; sigma_b = 0; return;
end

edges   = linspace(vmin, vmax, n_bins+1);
centers = (edges(1:end-1) + edges(2:end)) / 2;   % g_i, i=1..I
counts  = histcounts(v, edges);
p       = counts / sum(counts);                  % 式 3-20

omega = cumsum(p);                               % w0 随阈值变化
mu    = cumsum(p .* centers);                    % 分子项
muT   = mu(end);                                 % 总平均幅值 λ

sigma_b_arr = (muT * omega - mu).^2 ./ (omega .* (1 - omega) + eps);  % 式 3-26 前
[sigma_b, idx] = max(sigma_b_arr);
thr = centers(idx);

end
