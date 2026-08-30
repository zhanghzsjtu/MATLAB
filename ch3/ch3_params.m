function p = ch3_params()
% ch3_params  第3章 表3.1 仿真实验参数
%   《捷变雷达抗干扰与信号处理技术》3.2.4 节 表 3.1
%   脉间频率捷变-脉内频率编码波形联合仿真参数
%
% 返回结构体 p, 字段含义见下表。

p.N_pulses   = 64;        % 脉冲数 N / 个
p.K          = 10;        % 编码种类 K / 个 (脉内子脉冲数)
p.M_freqhop  = 100;       % 跳频点数 M / 个 (脉间频率捷变)
p.f0         = 14e9;      % 载频 f0 / GHz
p.df         = 7e6;       % 脉内跳频间隔 df / MHz
p.dF         = 80e6;      % 脉间跳频间隔 dF / MHz
p.T_pp       = 4e-6;      % 子脉冲脉宽 T_pp / us
p.B_sub      = 5e6;       % 子脉冲带宽 B_sub / MHz
p.R0         = 10e3;      % 目标距离 R0 / km
p.v          = 20;        % 目标速度 v / (m/s)
p.PRT        = 100e-6;    % 脉冲重复周期 PRT / us
p.c          = 3e8;       % 光速

% ---- 由表 3.1 推导的仿真参数 ----
p.T_p        = p.K * p.T_pp;                       % 信号脉宽 T_p = K*T_pp = 40 us
p.B_total    = (p.K - 1) * p.df + p.B_sub;         % 脉内合成带宽 = 68 MHz
p.fs         = 160e6;                              % 采样率 (满足 Nyquist: fs/2=80MHz > 68MHz)
p.jammer_lead = 600;                               % 干扰机前置目标距离 / m
p.tau_t      = 2 * p.R0 / p.c;                     % 目标回波时延 = 66.67 us
p.tau_j      = 2 * (p.R0 - p.jammer_lead) / p.c;   % 干扰回波时延 = 62.67 us

end
