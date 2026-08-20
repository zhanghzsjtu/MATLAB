%% main_gen_signals.m  —  生成九类干扰示例信号并绘制图5.3/5.4
% 输出：_复现工作/sim/fig5_3_timedomain.png, fig5_4_spectrum.png
% 本文件自包含（库函数以局部函数形式内联），无需额外addpath

%% 1. 仿真参数（书179页表5.1设定）
Tp  = 20e-6;     % 脉冲宽度 20us
B   = 10e6;      % 带宽 10MHz
fs  = 20e6;      % 采样率 20MHz

[t, S] = lfm_signal(Tp, B, fs, 0);

%% 2. 生成九类干扰（典型参数，对齐书164页干扰识别实验）
% 类别1 全脉冲转发 (距离欺骗 RDJ, 公式5-7)
J1 = gen_full_repeater(t, S, 3e-6, 1.0, 0);
% 类别2 全脉冲密集转发 (密集假目标 DFTJ, 公式5-10)
taus2 = linspace(1e-6, 10e-6, 5);
J2 = gen_dense_repeater(t, S, taus2, 0.8*ones(size(taus2)), 0);
% 类别3 ISRJ (公式5-11)
J3 = gen_isrj(t, S, 1.3e-6, 2.6e-6, floor(Tp/2.6e-6), 1);
% 类别4 部分脉冲密集转发
J4 = gen_partial_dense(t, S, 0.3*Tp, 0.7*Tp, linspace(0.5e-6,5e-6,4), 0.7*ones(1,4));
% 类别5 灵巧噪声(ISRJ噪声调制, 公式5-6)
rng(42); J5 = gen_smart_noise(t, S, 1.3e-6, 2.6e-6, floor(Tp/2.6e-6), 0.4);
% 类别6 噪声调频 (公式5-3)
rng(7);  J6 = gen_noise_fm(t, 1.0, 2.0e7, 0.5);
% 类别7 宽带压制（阻塞）
rng(11); J7 = gen_barrage(t, 1.5);
% 类别8 扫频 (公式5-4)
rng(13); J8 = gen_sweep(t, 15e6, 12e-6, 1.0);
% 类别9 梳状谱 (公式5-16)
rng(17); J9 = gen_comb(t, Tp, linspace(-4e6,4e6,5), 0.3*ones(1,5));

Jall = {J1,J2,J3,J4,J5,J6,J7,J8,J9};
names = {'1.全脉冲转发','2.全脉冲密集转发','3.ISRJ','4.部分脉冲密集转发', ...
         '5.灵巧噪声(ISRJ调制)','6.噪声调频','7.宽带压制','8.扫频','9.梳状谱'};

%% 3. 图5.3 时域图
figure('Position',[50 50 1200 800]);
for i = 1:9
    subplot(3,3,i);
    plot(t*1e6, real(Jall{i}), 'LineWidth', 0.6);
    title(names{i},'FontSize',10); xlabel('时间/\mus'); ylabel('幅度');
    grid on; axis tight;
end
sgtitle('图5.3 九类干扰信号示例的时域图（复现）','FontSize',13,'FontWeight','bold');
saveas(gcf, 'figs/fig5_3_timedomain.png');

%% 4. 图5.4 频谱图
Nfft = 2048;
faxis = linspace(-fs/2, fs/2, Nfft)/1e6;
figure('Position',[50 50 1200 800]);
for i = 1:9
    subplot(3,3,i);
    X = fftshift(fft(Jall{i}, Nfft));
    Xdb = 20*log10(abs(X)/max(abs(X)) + 1e-10);
    plot(faxis, Xdb, 'LineWidth', 0.6);
    title(names{i},'FontSize',10); xlabel('频率/MHz'); ylabel('幅度/dB');
    ylim([-60 5]); grid on;
end
sgtitle('图5.4 九类干扰信号示例的频谱图（复现）','FontSize',13,'FontWeight','bold');
saveas(gcf, 'figs/fig5_4_spectrum.png');

fprintf('九类干扰示例信号与图5.3/5.4已生成完毕。\n');

%% ===================== 局部函数库 =====================
function [t, S] = lfm_signal(Tp, B, fs, f0)
    if nargin < 4, f0 = 0; end
    N = round(Tp*fs);
    t = (0:N-1)'/fs;
    k = B/Tp;
    rect = double(abs(t) <= Tp/2);
    S = rect .* exp(1j*(2*pi*f0*t + pi*k*t.^2));
end

function J = gen_full_repeater(t, S, tau, A, fd)
    if nargin < 5, fd = 0; end
    if nargin < 4, A = 1.0; end
    tt = t + tau;
    Sd = interp1(t, S, tt, 'linear', 0);
    J = A * Sd .* exp(1j*2*pi*fd*t);
end

function J = gen_dense_repeater(t, S, taus, As, fd)
    if nargin < 5, fd = 0; end
    if nargin < 4, As = 0.8*ones(size(taus)); end
    J = zeros(size(S));
    for n = 1:length(taus)
        J = J + As(n) * gen_full_repeater(t, S, taus(n), As(n), fd);
    end
end

function J = gen_isrj(t, S, T_slice, T_samp, K, L)
    if nargin < 6, L = 1; end
    if nargin < 5, K = floor(max(t)/T_samp); end
    J = zeros(size(S));
    for l = 1:L
        for k = 1:K
            p_rect = double(abs((t - k*T_samp - T_slice/2)/T_slice) <= 0.5);
            J = J + p_rect .* interp1(t, S, t - l*T_samp, 'linear', 0);
        end
    end
end

function J = gen_partial_dense(t, S, tstart, tend, taus, As)
    if nargin < 6, As = 0.7*ones(size(taus)); end
    J = zeros(size(S));
    dt = t(2)-t(1);
    for n = 1:length(taus)
        tmp = zeros(size(S));
        idx_s = round((tstart+taus(n))/dt) + 1;
        idx_e = min(idx_s + length(S) - 1, length(S));
        if idx_e > idx_s && idx_s > 1
            len = idx_e - idx_s + 1;
            tmp(idx_s:idx_e) = S(1:len) * As(n);
        end
        J = J + tmp;
    end
    gate = double((t >= tstart) & (t <= tend));
    J = J .* gate;
end

function J = gen_smart_noise(t, S, T_slice, T_samp, K, sigma)
    if nargin < 6, sigma = 0.4; end
    S_isrj = gen_isrj(t, S, T_slice, T_samp, K, 1);
    n = sigma*randn(size(t));
    J = S_isrj .* (1 + n);
end

function J = gen_noise_fm(t, U0, K_fm, sigma)
    if nargin < 4, sigma = 0.5; end
    if nargin < 3, K_fm = 2.0e7; end
    if nargin < 2, U0 = 1.0; end
    dt = t(2)-t(1);
    n = sigma*randn(size(t));
    int_n = cumsum(n)*dt;
    phase = 2*pi*K_fm*int_n;
    J = U0*cos(phase);
end

function J = gen_barrage(t, P)
    if nargin < 2, P = 1.5; end
    J = sqrt(P)*randn(size(t));
end

function J = gen_sweep(t, delta_fs, T_sweep, U0)
    if nargin < 4, U0 = 1.0; end
    if nargin < 3, T_sweep = 12e-6; end
    if nargin < 2, delta_fs = 15e6; end
    dt = t(2)-t(1);
    fj = delta_fs * mod(t, T_sweep) / T_sweep;
    phase = 2*pi*cumsum(fj)*dt;
    J = U0*cos(phase);
end

function J = gen_comb(t, Tp, f_comb, k_comb)
    if nargin < 4, k_comb = 0.3*ones(size(f_comb)); end
    rect = double(abs(t) <= Tp/2);
    J = zeros(size(t));
    for i = 1:length(f_comb)
        J = J + k_comb(i)*rect.*exp(1j*2*pi*f_comb(i)*t);
    end
    J = real(J);
end
