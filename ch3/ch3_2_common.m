function ch3_2_common(G, T_j, T_s, tag, fig_prefix, n_mc)
% ch3_2_common  3.2.4 节仿真实验公共流程 (实验一/二共用)
%   实验一 (ISRJ-DF, G=1, T_j=4us, T_s=8us)  -> 图 3.3 ~ 3.7
%   实验二 (ISRJ-RF, G=2, T_j=4us, T_s=12us) -> 图 3.8 ~ 3.12
%
%   输入: G        重复转发次数 (1=直接转发, 2=重复转发)
%         T_j      干扰采样宽度 (s)
%         T_s      间歇采样重复周期 (s)
%         tag      'DF' 或 'RF' (用于文件名)
%         fig_prefix 图文件前缀, 如 'ch3_fig3_'
%         n_mc     蒙特卡罗次数 (书为 100)
%
% 输出图 (figs/ 目录):
%   识别准确率 vs SNR (书图 3.3 / 3.8)
%   方差-阈值 vs JSR  (书图 3.4 / 3.9)
%   回波/脉压演示     (书图 3.5~3.7 / 3.10~3.12)

p  = ch3_params();
fs = p.fs;
a  = freq_codes(p.K, 2);          % 固定频率码字 (可复现)
K  = p.K;

truth = get_truth(p, T_j, T_s, G);
fprintf('[ch3.2 %s] truth (jammed subpulse): %s\n', tag, mat2str(find(truth)));

% ---------------- 图 3.3/3.8 识别准确率 vs SNR ----------------
fig_recognition(p, fs, a, T_j, T_s, G, truth, tag, fig_prefix, n_mc);

% ---------------- 图 3.4/3.9 方差与阈值 vs JSR ----------------
fig_variance_vs_jsr(p, fs, a, T_j, T_s, G, truth, tag, fig_prefix, n_mc);

% ---------------- 图 3.5~3.7 / 3.10~3.12 单次演示 ----------------
fig_demo(p, fs, a, T_j, T_s, G, truth, tag, fig_prefix);

end

% =====================================================================
% 图 3.3/3.8  识别准确率 vs SNR (JSR=10/20/30 dB, SNR=-20~20 dB, n_mc MC)
% =====================================================================
function fig_recognition(p, fs, a, T_j, T_s, G, truth, tag, fig_prefix, n_mc)
    jsr_list = [10, 20, 30];
    snr_list = -20:2:20;
    K = p.K;

    fig = figure('Position', [80 80 620 420], 'Color', 'w');
    hold on;
    for i_jsr = 1:numel(jsr_list)
        jsr = jsr_list(i_jsr);
        acc = zeros(1, numel(snr_list));
        for i_snr = 1:numel(snr_list)
            snr = snr_list(i_snr);
            correct = 0;
            for mc = 1:n_mc
                seed = mc + i_snr*10000 + i_jsr*1000000;
                A_tar = swerling1(seed + 7);
                rx = build_rx(p, fs, a, T_j, T_s, G, jsr, snr, A_tar, seed);
                res = process_pulse(rx, fs, p, a);
                jammed = ~res.keep;
                correct = correct + sum(jammed == truth);
            end
            acc(i_snr) = correct / (K * n_mc) * 100;
        end
        plot(snr_list, acc, '-o', 'MarkerSize', 4, 'LineWidth', 1.2, ...
             'DisplayName', sprintf('JSR = %d dB', jsr));
    end
    hold off;
    xlabel('Single-subpulse SNR after pulse compression (dB)');
    ylabel('Recognition accuracy (%)');
    ylim([40 105]); grid on; grid minor; legend('Location', 'southeast');
    title(sprintf('Recognition accuracy vs SNR (ISRJ-%s, G=%d, %d MC trials)', tag, G, n_mc));
    save_fig(fig, sprintf('%srecognition_%s.png', fig_prefix, lower(tag)));
    fprintf('  saved: figs/%srecognition_%s.png\n', fig_prefix, lower(tag));
end

% =====================================================================
% 图 3.4/3.9  方差与阈值 vs JSR (SNR=5 dB, JSR=15~50 dB, n_mc MC)
%   统计: 未干扰子脉冲方差 min/max, 被干扰子脉冲方差 min/max, Otsu 阈值
% =====================================================================
function fig_variance_vs_jsr(p, fs, a, T_j, T_s, G, truth, tag, fig_prefix, n_mc)
    jsr_list = 15:5:50;
    snr = 5;

    v_cmin = zeros(1, numel(jsr_list));
    v_cmax = zeros(1, numel(jsr_list));
    v_jmin = zeros(1, numel(jsr_list));
    v_jmax = zeros(1, numel(jsr_list));
    thr_arr = zeros(1, numel(jsr_list));

    for i_jsr = 1:numel(jsr_list)
        jsr = jsr_list(i_jsr);
        cmin = 0; cmax = 0; jmin = 0; jmax = 0; thr_sum = 0;
        for mc = 1:n_mc
            seed = mc + i_jsr*100000;
            A_tar = swerling1(seed + 3);
            rx = build_rx(p, fs, a, T_j, T_s, G, jsr, snr, A_tar, seed);
            res = process_pulse(rx, fs, p, a);
            v_clean = res.var_k(~truth);
            v_jam   = res.var_k(truth);
            cmin = cmin + min(v_clean);
            cmax = cmax + max(v_clean);
            jmin = jmin + min(v_jam);
            jmax = jmax + max(v_jam);
            thr_sum = thr_sum + res.thr;
        end
        n = n_mc;
        v_cmin(i_jsr) = cmin / n;
        v_cmax(i_jsr) = cmax / n;
        v_jmin(i_jsr) = jmin / n;
        v_jmax(i_jsr) = jmax / n;
        thr_arr(i_jsr) = thr_sum / n;
    end

    fig = figure('Position', [80 80 620 420], 'Color', 'w');
    plot(jsr_list, v_cmin, 'o-', 'Color', [0.2 0.6 0.2], 'LineWidth', 1.2, 'DisplayName', 'clean subpulse var (min)');
    hold on;
    plot(jsr_list, v_cmax, 's-', 'Color', [0.4 0.8 0.4], 'LineWidth', 1.2, 'DisplayName', 'clean subpulse var (max)');
    plot(jsr_list, v_jmin, '^-', 'Color', [0.85 0.15 0.15], 'LineWidth', 1.2, 'DisplayName', 'jammed subpulse var (min)');
    plot(jsr_list, v_jmax, 'd-', 'Color', [1 0.5 0.2], 'LineWidth', 1.2, 'DisplayName', 'jammed subpulse var (max)');
    plot(jsr_list, thr_arr, '*--', 'Color', [0.5 0.2 0.8], 'LineWidth', 1.2, 'DisplayName', 'Otsu threshold');
    hold off;
    xlabel('JSR (dB)'); ylabel('Variance of |y(t,k)|');
    grid on; grid minor; legend('Location', 'northwest');
    title(sprintf('Variance & Otsu threshold vs JSR (ISRJ-%s, %d MC, SNR=%d dB)', tag, n_mc, snr));
    save_fig(fig, sprintf('%svariance_threshold_%s.png', fig_prefix, lower(tag)));
    fprintf('  saved: figs/%svariance_threshold_%s.png\n', fig_prefix, lower(tag));
end

% =====================================================================
% 图 3.5~3.7 / 3.10~3.12  单次演示 (SNR=5 dB, JSR=20 dB)
%   (a) 含干扰回波; (b) 被干扰子脉冲脉压
%   (a) 无干扰子脉冲脉压; (b) 方差柱状图 + Otsu 阈值
%   (a) 干扰抑制后脉内积累; (b) 二维稀疏重构 (64 脉冲相参距离-多普勒)
% =====================================================================
function fig_demo(p, fs, a, T_j, T_s, G, truth, tag, fig_prefix)
    snr = 5; jsr = 20; seed = 2024;
    A_tar = 1.0;                       % 演示用固定幅度
    rx = build_rx(p, fs, a, T_j, T_s, G, jsr, snr, A_tar, seed);
    res = process_pulse(rx, fs, p, a);
    K = p.K; T_sub = p.T_pp;
    t_rx = (0:numel(rx)-1) / fs;

    jammed_idx = find(truth);
    clean_idx  = find(~truth);
    m_jam  = jammed_idx(1);
    m_clean = clean_idx(1);

    % ============ 图 3.5/3.10: 回波 + 被干扰子脉冲脉压 ============
    fig = figure('Position', [100 60 800 560], 'Color', 'w');
    subplot(2, 1, 1);
    plot(t_rx*1e6, real(rx), 'b', 'LineWidth', 0.7); hold on;
    P = floor(p.T_p / T_s) + 1;
    for n = 0:P-1
        xline((p.tau_j + n*T_s)*1e6, '--', 'Color', [0.7 0.7 0.7]);
    end
    xlim([t_rx(1)*1e6, t_rx(end)*1e6]);
    xlabel('Time (us)'); ylabel('Amplitude');
    title(sprintf('(a) Received pulse with ISRJ-%s (JSR=%d dB, SNR=%d dB)', tag, jsr, snr));
    grid on; grid minor;

    subplot(2, 1, 2);
    plot(t_rx*1e6, abs(res.yc(m_jam, :)), 'Color', [0.85 0.15 0.15], 'LineWidth', 0.8);
    xlim([t_rx(1)*1e6, t_rx(end)*1e6]);
    xlabel('Time (us)'); ylabel('|y(t,k)|');
    title(sprintf('(b) Pulse compression of a jammed subpulse (m=%d) — false targets', m_jam));
    grid on; grid minor;
    sgtitle(sprintf('Received pulse & jammed-subpulse compression (ISRJ-%s, JSR=%d dB, SNR=%d dB)', tag, jsr, snr));
    save_fig(fig, sprintf('%srx_compressed_jammed_%s.png', fig_prefix, lower(tag)));
    fprintf('  saved: figs/%srx_compressed_jammed_%s.png\n', fig_prefix, lower(tag));

    % ============ 图 3.6/3.11: 无干扰子脉冲脉压 + 方差阈值 ============
    fig = figure('Position', [120 60 760 400], 'Color', 'w');
    subplot(1, 2, 1);
    plot(t_rx*1e6, abs(res.yc(m_clean, :)), 'Color', [0.2 0.6 0.2], 'LineWidth', 0.8);
    xlim([t_rx(1)*1e6, t_rx(end)*1e6]);
    xlabel('Time (us)'); ylabel('|y(t,k)|');
    title(sprintf('(a) Clean subpulse compression (m=%d) — true target', m_clean));
    grid on; grid minor;

    subplot(1, 2, 2);
    b = bar(1:K, res.var_k, 0.6);
    for k = 1:K
        if truth(k)
            b.FaceColor = 'flat'; b.CData(k, :) = [0.85 0.15 0.15];
        else
            b.FaceColor = 'flat'; b.CData(k, :) = [0.2 0.6 0.2];
        end
    end
    hold on;
    yline(res.thr, '--', 'Color', [0.5 0.2 0.8], 'LineWidth', 1.5, ...
          'Label', sprintf('Otsu thr = %.2e', res.thr));
    hold off;
    xlabel('Subpulse index k'); ylabel('Variance');
    title('(b) Subpulse variance vs Otsu threshold (red=jammed, green=clean)');
    grid on; grid minor;
    sgtitle(sprintf('Clean-subpulse compression & subpulse variance vs Otsu threshold (ISRJ-%s)', tag));
    save_fig(fig, sprintf('%sclean_var_thr_%s.png', fig_prefix, lower(tag)));
    fprintf('  saved: figs/%sclean_var_thr_%s.png\n', fig_prefix, lower(tag));

    % ============ 图 3.7/3.12: 脉内积累 + 二维稀疏重构 ============
    fig = figure('Position', [140 60 800 400], 'Color', 'w');
    subplot(1, 2, 1);
    y_db = 20 * log10(abs(res.y_intra) / max(abs(res.y_intra)) + 1e-12);
    plot(t_rx*1e6, y_db, 'b', 'LineWidth', 0.9);
    xlim([t_rx(1)*1e6, t_rx(end)*1e6]); ylim([-50 2]);
    xlabel('Time (us)'); ylabel('|y_{intra}(t)| (dB)');
    title('(a) Intra-pulse accumulation after suppression — target only');
    grid on; grid minor;

    subplot(1, 2, 2);
    img = range_doppler_img(p, fs, a, T_j, T_s, G, jsr, snr, 64);
    imagesc(img.t_axis*1e6, img.v_axis, img.db);
    axis xy; colormap('jet'); caxis([-30 0]);
    xlabel('Time (us)'); ylabel('Radial velocity (m/s)');
    title('(b) 2D sparse-reconstruction map (range-Doppler, 64 pulses)');
    colorbar;
    sgtitle(sprintf('Intra-pulse accumulation & 2D sparse reconstruction (ISRJ-%s)', tag));
    save_fig(fig, sprintf('%sintra_sparse_%s.png', fig_prefix, lower(tag)));
    fprintf('  saved: figs/%sintra_sparse_%s.png\n', fig_prefix, lower(tag));
end

% =====================================================================
% 二维稀疏重构: N 个脉冲干扰抑制后脉内积累 (复距离像) 沿脉冲维 FFT
% =====================================================================
function img = range_doppler_img(p, fs, a, T_j, T_s, G, jsr_db, snr_db, N_pulses)
    fd = 2 * p.v * p.f0 / p.c;         % 目标多普勒 (固定载频 f0)

    % 距离窗: 脉内积累已将各子脉冲目标峰对齐到 tau_t, 取前后各 1 us
    w_start = p.tau_t - 1e-6;
    w_end   = p.tau_t + 1e-6;
    i_start = max(1, round(w_start * fs) + 1);
    i_end   = min(round(w_end * fs) + 1, round((p.tau_t + p.T_p + 20e-6) * fs));
    n_win   = i_end - i_start + 1;

    Y = zeros(N_pulses, n_win);
    for np = 1:N_pulses
        A_tar = swerling1(100000 + np);
        rx = build_rx(p, fs, a, T_j, T_s, G, jsr_db, snr_db, A_tar, 300000 + np, fd);
        res = process_pulse(rx, fs, p, a);
        % 脉冲间多普勒相位递进 exp(j2π f_d (np-1) T_PRT), 使目标回波
        % 在脉冲维相参, 距离-多普勒 FFT 后在 f_d 处形成峰值
        pulse_phase = exp(1j * 2 * pi * fd * (np-1) * p.PRT);
        Y(np, :) = res.y_intra(i_start:i_end) * pulse_phase;   % 复距离像
    end

    % 多普勒维 FFT (零填充到 nfd)
    nfd = 128;
    Yd = fftshift(fft(Y, nfd, 1), 1);
    img.db = 20 * log10(abs(Yd) / max(abs(Yd(:))) + 1e-12);
    img.t_axis = (i_start-1:i_end-1) / fs;
    df_bin = 1 / (nfd * p.PRT);             % 多普勒分辨率 (零填充后 bin 间隔 = 1/(nfd*PRT))
    img.v_axis = (-nfd/2:nfd/2-1) * df_bin * p.c / (2 * p.f0);
end
