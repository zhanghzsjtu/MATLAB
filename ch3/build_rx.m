function rx = build_rx(p, fs, a, T_j, T_s, G, jsr_db, snr_pc_db, A_tar, seed, doppler_hz)
% build_rx  构造一个脉冲的复基带回波信号 (式 3-13 / 3-17)
%   rx = s_tar(目标回波) + j(ISRJ) + n(AWGN)
%
%   输入: p         参数结构体
%         fs        采样率
%         a         频率码字
%         T_j       干扰采样宽度
%         T_s       间歇采样重复周期
%         G         重复转发次数
%         jsr_db    干信比 JSR (dB)
%         snr_pc_db 单子脉冲匹配滤波后信噪比 SNR (dB)
%         A_tar     目标幅度 (Swerling I 起伏, E[|A|^2]=1)
%         seed      随机种子
%         doppler_hz 目标多普勒频移 (可选, 默认 0)
%   输出: rx        回波信号 (1 x n), n = 回波窗长度
%
%   时间设定: 发射信号以 t=0 为起点; 目标回波时延 tau_t = 2R0/c;
%   干扰机前置 600 m, 干扰回波时延 tau_j = 2(R0-600)/c。
%   噪声按"单子脉冲匹配滤波后 SNR"注入: N0 = A_tar^2*T_pp / 10^(SNR/10)。

if nargin < 11
    doppler_hz = 0;
end

T_p = p.K * p.T_pp;
tau_t = p.tau_t;
tau_j = p.tau_j;

T_window = tau_t + T_p + 20e-6;             % 回波窗: 目标回波 + 脉宽 + 余量
n = round(T_window * fs);
t = (0:n-1) / fs;

s_tx = gen_lfm_fc(p, fs, a);                % 发射信号

% ---- 1. 目标回波 (含多普勒) ----
rx = zeros(1, n);
st = round(tau_t * fs) + 1;
if st + numel(s_tx) - 1 <= n
    if doppler_hz ~= 0
        fd_phase = exp(1j * 2 * pi * doppler_hz * (t(st:st+numel(s_tx)-1) - tau_t));
        rx(st:st+numel(s_tx)-1) = A_tar * s_tx .* fd_phase;
    else
        rx(st:st+numel(s_tx)-1) = A_tar * s_tx;
    end
end

% ---- 2. 间歇采样转发干扰 (噪声调制, 频谱以被采样子脉冲频带为中心) ----
A_j = 10^(jsr_db / 20);
j = isrj_noise_mod(n, fs, T_j, T_s, G, tau_j, A_j, seed, s_tx);
rx = rx + j;

% ---- 3. AWGN (按脉压后 SNR 注入) ----
Es = A_tar^2 * p.T_pp;                      % 子脉冲信号能量 (连续域)
N0 = Es / 10^(snr_pc_db / 10);              % 噪声功率谱密度
noise_pow = N0 * fs;                        % 每样本功率
rx = rx + sqrt(noise_pow/2) * (randn(1, n) + 1j*randn(1, n));

end
