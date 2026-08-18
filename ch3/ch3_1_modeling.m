function ch3_1_modeling()
% ch3_1_modeling  3.1 节 脉内频率编码信号数学建模仿真
%   图 3.1  LFM-频率编码信号示意 (时域实部/包络、频谱、时频分布)
%   图 3.2  LFM-频率编码信号模糊函数 (2D + 零多普勒/零时延切片)
%
%   公式依据:
%     式 3-1   s(t) = Σ rect((t-mT_sub)/T_sub) · u_m(t-mT_sub) · exp(j2π a_m Δf t)
%     式 3-2   s_LFM(t) = Σ rect((t-mT_sub)/T_sub) · exp(jπγ(t-mT_sub)^2) · exp(j2π a_m Δf t)
%     式 3-3   χ(τ,f_d) = ∫ s(t) s*(t-τ) e^{j2π f_d t} dt
%
% 运行:  ch3_1_modeling
% 输出:  figs/ch3_fig3_1_signal_waveform.png, figs/ch3_fig3_2_ambiguity.png

p  = ch3_params();
fs = p.fs;
a  = freq_codes(p.K, 1);
[s, t] = gen_lfm_fc(p, fs, a);
fprintf('[ch3.1] LFM-FC length: %d samples, fs=%.0f MHz\n', numel(s), fs/1e6);

fig_3_1_signal(p, s, t, a, fs);
fig_3_2_ambiguity(p, s, fs, a);

end

% =====================================================================
% 图 3.1  信号波形
% =====================================================================
function fig_3_1_signal(p, s, t, a, fs)
    M = p.K; T_sub = p.T_pp; B_sub = p.B_sub; df = p.df;

    % 频谱
    N = numel(s);
    S = fftshift(fft(s, N));
    f = (-N/2:N/2-1) * fs / N;     % 升序频率轴 (与 fftshift 对应)

    % 时频 (自写 STFT, 不依赖工具箱)
    [Z, f_stft, t_stft] = my_stft(s, fs, 128, 120);

    fig = figure('Position', [60 60 900 760], 'Color', 'w');
    % ---- (a) 时域 ----
    subplot(3, 1, 1);
    plot(t*1e6, real(s), 'b', 'LineWidth', 0.8); hold on;
    plot(t*1e6, abs(s), 'r', 'LineWidth', 1.2);
    xlim([t(1)*1e6, t(end)*1e6]);
    ylabel('Amplitude');
    title(sprintf('(a) LFM-FC time-domain waveform (K=%d, T_{sub}=%g us, B_{sub}=%g MHz, code=%s)', ...
          M, T_sub*1e6, B_sub/1e6, mat2str(a)));
    legend({'Re{s(t)}', '|s(t)|'}, 'Location', 'northeast', 'FontSize', 8);
    for m = 1:M-1
        xline(m*T_sub*1e6, ':', 'Color', [0.6 0.6 0.6], 'HandleVisibility', 'off');
    end
    grid on; grid minor;

    % ---- (b) 频谱 ----
    subplot(3, 1, 2);
    plot(f/1e6, 20*log10(abs(S)/max(abs(S)) + 1e-12), 'Color', [0.85 0.33 0.1], 'LineWidth', 0.9);
    xlim([f(1)/1e6, f(end)/1e6]); ylim([-60 5]);
    ylabel('|S(f)| (dB)');
    title('(b) Spectrum of LFM-FC signal (subpulses occupy distinct bands)');
    for m = 1:M
        c = a(m)*df;
        xline(c/1e6, ':', 'Color', [0.6 0.6 0.6], 'HandleVisibility', 'off');
        text(c/1e6, -55, sprintf('a_%d=%g', m-1, a(m)), 'HorizontalAlignment', 'center', 'FontSize', 7, 'Color', [0.4 0.4 0.4]);
    end
    grid on; grid minor;

    % ---- (c) 时频 ----
    subplot(3, 1, 3);
    imagesc(t_stft*1e6, f_stft/1e6, 20*log10(abs(Z)/max(abs(Z(:))) + 1e-12));
    axis xy; colormap('jet'); caxis([-50 0]);
    xlabel('Time (us)'); ylabel('Frequency (MHz)');
    title('(c) Time-frequency distribution (STFT) — each subpulse is a tilted LFM stripe');
    colorbar;

    sgtitle('Fig. 3.1  Schematic of the LFM-frequency-coded signal');
    save_fig(fig, 'ch3_fig3_1_signal_waveform.png');
    fprintf('  saved: figs/ch3_fig3_1_signal_waveform.png\n');
end

% =====================================================================
% 图 3.2  模糊函数
% =====================================================================
function fig_3_2_ambiguity(p, s, fs, a)
    fprintf('[ch3.1] computing ambiguity function ...\n');
    [chi2, tau, fd] = ambiguity_lfmfc(s, fs, 96, 4);
    chi2_db = 10*log10(chi2 / max(chi2(:)) + 1e-12);

    T_sub = p.T_pp; T_p = p.T_p;

    fig = figure('Position', [80 40 980 680], 'Color', 'w');
    % ---- (a) 2D 等高线 ----
    subplot(2, 2, 1);
    imagesc(tau*1e6, fd/1e3, chi2_db');
    axis xy; colormap('jet'); caxis([-40 0]);
    xlabel('Delay \tau (us)'); ylabel('Doppler f_d (kHz)');
    title(sprintf('(a) |\\chi(\\tau,f_d)|^2 of LFM-FC (K=%d)', p.K));
    colorbar;

    % ---- (b) 零多普勒切片 ----
    subplot(2, 2, 2);
    [~, i_fd0] = min(abs(fd));
    plot(tau*1e6, chi2_db(:, i_fd0), 'b', 'LineWidth', 1.0);
    xlim([-2*T_p*1e6, 2*T_p*1e6]); ylim([-60 2]);
    xlabel('\tau (us)'); ylabel('dB');
    title('(b) Zero-Doppler cut');
    grid on;

    % ---- (c) 零时延切片 ----
    subplot(2, 2, 3);
    [~, i_tau0] = min(abs(tau));
    plot(fd/1e3, chi2_db(i_tau0, :), 'r', 'LineWidth', 1.0);
    xlim([-2/T_sub/1e3, 2/T_sub/1e3]); ylim([-60 2]);
    xlabel('f_d (kHz)'); ylabel('dB');
    title('(c) Zero-range cut');
    grid on;

    % ---- (d) 注释 ----
    subplot(2, 2, 4); axis off;
    note = sprintf([ ...
        'Thumbtack-shape ambiguity\n', ...
        '  K = %d subpulses\n', ...
        '  code a_m = %s\n', ...
        '  T_p = K*T_sub = %.1f us\n', ...
        '  df*T_sub = %g\n', ...
        'Grating lobes at\n', ...
        '  tau = k*T_sub (from code)\n', ...
        '  f_d = (a_i-a_j)*df (from\n', ...
        '         carrier hops).\n'], ...
        p.K, mat2str(a), T_p*1e6, p.df*T_sub);
    text(0.02, 0.5, note, 'FontSize', 10, 'VerticalAlignment', 'middle', ...
         'BackgroundColor', [0.95 0.95 0.95], 'EdgeColor', [0.5 0.5 0.5]);

    sgtitle('Fig. 3.2  Ambiguity function of the LFM-frequency-coded waveform');
    save_fig(fig, 'ch3_fig3_2_ambiguity_function.png');
    fprintf('  saved: figs/ch3_fig3_2_ambiguity_function.png\n');
end

% =====================================================================
% 自写短时傅里叶变换 (避免工具箱依赖)
% =====================================================================
function [Z, f, t] = my_stft(s, fs, win_len, hop)
    win = 0.5 * (1 - cos(2*pi*(0:win_len-1) / (win_len-1)));   % Hann 窗
    n = numel(s);
    n_frames = max(1, floor((n - win_len) / hop) + 1);
    Z = zeros(win_len, n_frames);
    for i = 1:n_frames
        idx = (i-1)*hop + (1:win_len);
        seg = s(idx) .* win;
        Z(:, i) = fft(seg);
    end
    f = (-win_len/2:win_len/2-1) * fs / win_len;   % 升序频率轴
    Z = fftshift(Z, 1);
    t = ((0:n_frames-1)*hop + win_len/2) / fs;
end
