function [s, t] = gen_lfm_fc(p, fs, a)
% gen_lfm_fc  式 3-2 线性调频-频率编码信号 (复基带)
%   输入: p  参数结构体 (ch3_params)
%         fs 采样率 (Hz)
%         a  频率码字 (1xK, 默认使用 freq_codes 生成)
%   输出: s  复包络 (1 x K*n_sub)
%         t  时间轴 (s), 从脉冲起点 t=0 开始
%
%   式 3-2: s_LFM(t) = Σ rect((t-m*T_sub)/T_sub)
%                      · exp(j*pi*gamma*(t-m*T_sub)^2)
%                      · exp(j*2*pi*a_m*df*t)
%   其中 gamma = B_sub/T_sub 为调频斜率 (书中式 3-1 后定义)。
%   第 m 个子脉冲占据时间 [m*T_sub, (m+1)*T_sub], 载频 a_m*df。

if nargin < 3
    a = freq_codes(p.K, 1);
end

M     = p.K;
T_sub = p.T_pp;
B_sub = p.B_sub;
df    = p.df;
gamma = B_sub / T_sub;              % 调频斜率

n_sub   = round(T_sub * fs);        % 每子脉冲样本数
n_pulse = n_sub * M;                % 总样本数
t = (0:n_pulse-1) / fs;             % 全局时间轴, 从 0 开始

s = zeros(1, n_pulse);
for m = 1:M
    idx    = (m-1)*n_sub + (1:n_sub);
    t_loc  = t(idx) - (m-1)*T_sub;  % 子脉冲局部时间
    s(idx) = exp(1j*2*pi*(a(m)*df)*t_loc + 1j*pi*gamma*t_loc.^2);
end

end
