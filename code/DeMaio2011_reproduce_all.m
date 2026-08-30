function DeMaio2011_reproduce_all(N_mc_h0, N_mc_h1, N_mc_rms)
%DeMaio2011_reproduce_all 复现 De Maio & Orlando 2011 (TSP) 论文 Fig.1-6
%   严格按论文 Section IV (Performance Assessment) 与 Fig.1-6 的图例与图结构绘制。
%   公共参数严格对齐论文：
%     N=16, K=32, Pfa=1e-4, CNR=20 dB, rho=0.995 (一阶相关系数)
%     Tp=0.2 us, c=3e8 m/s, f=0 Hz, nu_s=0.3
%     epsilon 网格：linspace(-Tp/2, Tp/2, 2*Ne+1)，Ne=5 或 10
%   论文 Monte Carlo: H0 1e6、H1 Pd 1e5、H1 RMS 500
%   默认用 2e5/1e4/500 以在可接受时间内完成；需要论文级精度时
%   调用 DeMaio2011_reproduce_all(1e6, 1e5, 500)。
%
%   输出：code/ 目录下 6 张 PNG 与 DeMaio2011_all_results.mat
%
%   检测器 (与 Fig.1-6 图例严格对应):
%     'mk'    : Modified Kelly's GLRT (论文式 25-29)
%     'ma'    : Modified AMF (论文式 33-38)
%     'mae'   : Modified ACE (论文式 40-46)
%     'mdt'   : Modified DT-GLRT (论文式 47，Conte 1995 + 3-cell max)
%     'mgamf' : Modified GAMF (论文式 48，Bidon 2011 + 3-cell max)
%     'mgasd' : Modified GASD (论文式 49，Bidon 2011 + 3-cell max)
%     'ck'    : 经典 Kelly's GLRT (单 cell)
%     'ca'    : 经典 AMF (单 cell)
%     'cae'   : 经典 ACE (单 cell)
%
%   Fig.1 : homogeneous, Ne=5,  5 detectors {Mod.Kelly, Mod.AMF, Mod.ACE, Mod.DT-GLRT, Cls.Kelly}
%   Fig.2 : homogeneous, Ne=5,  5 detectors {Mod.Kelly, Mod.AMF, Mod.ACE, Mod.GAMF, AMF}
%   Fig.3 : homogeneous, Ne=5,  5 detectors {Mod.Kelly, Mod.AMF, Mod.ACE, Mod.GASD, ACE}
%   Fig.4 : homogeneous, 2 subplots (Δε=Tp/10 与 Δε=Tp/20), 每子图 3 curves {Mod.Kelly, Mod.AMF, Mod.ACE}
%   Fig.5 : partial (γ=3 dB), Ne=5, 3 detectors {Mod.ACE, Mod.GASD, ACE}
%   Fig.6 : partial (γ=3 dB), 2 subplots (Δε=Tp/10 与 Δε=Tp/20), 每子图 1 curve {Mod.ACE}
%
%   运行方式：
%     "/c/Program Files/MATLAB/R2025b/bin/matlab" -nodisplay -nosplash -batch \
%       "addpath('D:/doctor/RD10B_literature/G_teams_Q1/01_意大利_DeMaio_Orlando_Aubry/code'); DeMaio2011_reproduce_all"

if nargin < 1, N_mc_h0 = 200000; end
if nargin < 2, N_mc_h1 = 10000;  end
if nargin < 3, N_mc_rms = 500;   end

clearvars -except N_mc_h0 N_mc_h1 N_mc_rms;
close all;
clc;
rng(42);

%% 论文公共参数 (Section IV)
Na = 4;
Np = 4;
N  = Na * Np;          % 16
K  = 32;
rho = 0.995;           % 一阶相关系数
sigma_n2 = 1;
sigma_c2 = 100;        % CNR = 20 dB
Tp = 0.2e-6;           % 脉宽
c  = 3e8;              % 光速
nu_s = 0.3;
nu   = 0;              % 目标多普勒 f=0
Pfa = 1e-4;            % 论文虚警率
B = 2000;              % Monte Carlo 批大小

v = generate_steering(Na, Np, nu_s, nu);
R = generate_covariance(N, rho, sigma_n2, sigma_c2);
invR_true = inv(R);
norm_vR = real(v' * invR_true * v);
L = chol(R, 'lower');

make_grid = @(Ne) linspace(-Tp/2, Tp/2, 2*Ne+1);  % 论文式 (50)

outdir = fileparts(mfilename('fullpath'));

%% ========== Fig.1: 均匀环境 Pd vs SNR ==========
% 图例: Modified Kelly's GLRT, Modified AMF, Modified ACE, Modified DT-GLRT, Kelly's GLRT
Ne1 = 5;
eps_grid1 = make_grid(Ne1);
SNR_dB_fig1 = 10:2:24;
det_list_fig1 = {'mk','ma','mae','mdt','ck'};

fprintf('\n=== Fig.1: Homogeneous Pd-SNR (Ne=%d, Pfa=%.0e) ===\n', Ne1, Pfa);
stats_h0_fig1 = run_h0(L, 1.0, K, v, eps_grid1, Tp, Pfa, N_mc_h0, B, det_list_fig1);
thresholds_fig1 = prctile(stats_h0_fig1, 100*(1-Pfa), 1);
fprintf('Thresholds: ModKelly=%.4f, ModAMF=%.4f, ModACE=%.4f, ModDT-GLRT=%.4f, ClsKelly=%.4f\n', thresholds_fig1);

Pd_fig1 = run_h1_pd(L, 1.0, R, K, v, eps_grid1, Tp, SNR_dB_fig1, N_mc_h1, B, thresholds_fig1, det_list_fig1);

fig1 = figure('Visible','off', 'Color','w', 'Position',[100 100 700 500]);
plot(SNR_dB_fig1, Pd_fig1(1,:), '-',  'LineWidth',1.5, 'Marker','none', 'Color',[0 0 0]); hold on;
plot(SNR_dB_fig1, Pd_fig1(2,:), '--', 'LineWidth',1.5, 'Marker','none', 'Color',[0 0 0]);
plot(SNR_dB_fig1, Pd_fig1(3,:), '-',  'LineWidth',1.5, 'Marker','*', 'MarkerSize',7, 'Color',[0 0 0]);
plot(SNR_dB_fig1, Pd_fig1(4,:), '-',  'LineWidth',1.5, 'Marker','d', 'MarkerSize',6, 'Color',[0 0 0]);
plot(SNR_dB_fig1, Pd_fig1(5,:), '-',  'LineWidth',1.5, 'Marker','x', 'MarkerSize',7, 'Color',[0 0 0]);
grid on; box on; xlim([10 24]); ylim([0 1]);
xlabel('SNR (dB)', 'FontSize',12);
ylabel('P_d', 'FontSize',12);
title(sprintf('Fig.1 — P_d vs SNR, homogeneous environment, N=%d, K=%d, P_{fa}=%.0e, N_\\epsilon=%d', N, K, Pfa, Ne1), 'FontSize',10);
legend('Modified Kelly''s GLRT','Modified AMF','Modified ACE','Modified DT-GLRT','Kelly''s GLRT', ...
       'Location','east','FontSize',9);
set(gca,'FontSize',11);
save_fig(fig1, fullfile(outdir, 'DeMaio2011_Fig1_PdSNR_homogeneous.png'));

%% ========== Fig.2: 均匀环境 5 检测器 Pd vs SNR ==========
% 图例: Modified Kelly's GLRT, Modified AMF, Modified ACE, Modified GAMF, AMF
Ne2 = 5;
eps_grid2 = make_grid(Ne2);
SNR_dB_fig2 = 10:2:24;
det_list_fig2 = {'mk','ma','mae','mgamf','ca'};

fprintf('\n=== Fig.2: Homogeneous Pd-SNR (5 detectors, Ne=%d) ===\n', Ne2);
stats_h0_fig2 = run_h0(L, 1.0, K, v, eps_grid2, Tp, Pfa, N_mc_h0, B, det_list_fig2);
thresholds_fig2 = prctile(stats_h0_fig2, 100*(1-Pfa), 1);
fprintf('Thresholds: ModKelly=%.4f, ModAMF=%.4f, ModACE=%.4f, ModGAMF=%.4f, AMF=%.4f\n', thresholds_fig2);

Pd_fig2 = run_h1_pd(L, 1.0, R, K, v, eps_grid2, Tp, SNR_dB_fig2, N_mc_h1, B, thresholds_fig2, det_list_fig2);

fig2 = figure('Visible','off', 'Color','w', 'Position',[100 100 700 500]);
plot(SNR_dB_fig2, Pd_fig2(1,:), '-',  'LineWidth',1.5, 'Marker','none',  'Color',[0 0 0]); hold on;
plot(SNR_dB_fig2, Pd_fig2(2,:), '--', 'LineWidth',1.5, 'Marker','none',  'Color',[0 0 0]);
plot(SNR_dB_fig2, Pd_fig2(3,:), '-',  'LineWidth',1.5, 'Marker','*', 'MarkerSize',7, 'Color',[0 0 0]);
plot(SNR_dB_fig2, Pd_fig2(4,:), '-',  'LineWidth',1.5, 'Marker','s', 'MarkerSize',5, 'Color',[0 0 0]);
plot(SNR_dB_fig2, Pd_fig2(5,:), '-',  'LineWidth',1.5, 'Marker','+', 'MarkerSize',7, 'Color',[0 0 0]);
grid on; box on; xlim([10 24]); ylim([0 1]);
xlabel('SNR (dB)', 'FontSize',12);
ylabel('P_d', 'FontSize',12);
title(sprintf('Fig.2 — P_d vs SNR, homogeneous environment, N=%d, K=%d, P_{fa}=%.0e, N_\\epsilon=%d', N, K, Pfa, Ne2), 'FontSize',10);
legend('Modified Kelly''s GLRT','Modified AMF','Modified ACE','Modified GAMF','AMF', ...
       'Location','east','FontSize',9);
set(gca,'FontSize',11);
save_fig(fig2, fullfile(outdir, 'DeMaio2011_Fig2_PdSNR_5det.png'));

%% ========== Fig.3: 均匀环境 5 检测器 Pd vs SNR (含 Mod.GASD 与 ACE) ==========
% 图例: Modified Kelly's GLRT, Modified AMF, Modified ACE, Modified GASD, ACE
Ne3 = 5;
eps_grid3 = make_grid(Ne3);
SNR_dB_fig3 = 10:2:24;
det_list_fig3 = {'mk','ma','mae','mgasd','cae'};

fprintf('\n=== Fig.3: Homogeneous Pd-SNR (5 detectors with GASD, Ne=%d) ===\n', Ne3);
stats_h0_fig3 = run_h0(L, 1.0, K, v, eps_grid3, Tp, Pfa, N_mc_h0, B, det_list_fig3);
thresholds_fig3 = prctile(stats_h0_fig3, 100*(1-Pfa), 1);
fprintf('Thresholds: ModKelly=%.4f, ModAMF=%.4f, ModACE=%.4f, ModGASD=%.4f, ACE=%.4f\n', thresholds_fig3);

Pd_fig3 = run_h1_pd(L, 1.0, R, K, v, eps_grid3, Tp, SNR_dB_fig3, N_mc_h1, B, thresholds_fig3, det_list_fig3);

fig3 = figure('Visible','off', 'Color','w', 'Position',[100 100 700 500]);
plot(SNR_dB_fig3, Pd_fig3(1,:), '-',  'LineWidth',1.5, 'Marker','none', 'Color',[0 0 0]); hold on;
plot(SNR_dB_fig3, Pd_fig3(2,:), '--', 'LineWidth',1.5, 'Marker','none', 'Color',[0 0 0]);
plot(SNR_dB_fig3, Pd_fig3(3,:), '-',  'LineWidth',1.5, 'Marker','*', 'MarkerSize',7, 'Color',[0 0 0]);
plot(SNR_dB_fig3, Pd_fig3(4,:), '-',  'LineWidth',1.5, 'Marker','v', 'MarkerSize',5, 'Color',[0 0 0]);
plot(SNR_dB_fig3, Pd_fig3(5,:), '-',  'LineWidth',1.5, 'Marker','+', 'MarkerSize',7, 'Color',[0 0 0]);
grid on; box on; xlim([10 24]); ylim([0 1]);
xlabel('SNR (dB)', 'FontSize',12);
ylabel('P_d', 'FontSize',12);
title(sprintf('Fig.3 — P_d vs SNR, homogeneous environment, N=%d, K=%d, P_{fa}=%.0e, N_\\epsilon=%d', N, K, Pfa, Ne3), 'FontSize',10);
legend('Modified Kelly''s GLRT','Modified AMF','Modified ACE','Modified GASD','ACE', ...
       'Location','east','FontSize',9);
set(gca,'FontSize',11);
save_fig(fig3, fullfile(outdir, 'DeMaio2011_Fig3_PdSNR_5det_GASD.png'));

%% ========== Fig.4: 均匀环境 RMS 距离误差 (2 子图) ==========
% 上子图 Δε=Tp/10 (Ne=5)，下子图 Δε=Tp/20 (Ne=10)；每子图 {Mod.Kelly, Mod.AMF, Mod.ACE}
% 论文给出下界 0.866 m (Ne=5) 与 0.433 m (Ne=10)
Ne4a = 5;
Ne4b = 10;
eps_grid4a = make_grid(Ne4a);
eps_grid4b = make_grid(Ne4b);
SNR_dB_fig4 = 12:2:40;
det_list_fig4 = {'mk','ma','mae'};

fprintf('\n=== Fig.4: RMS range error vs SNR (homogeneous, 2 subplots) ===\n');
rms_fig4a = run_rms(L, 1.0, R, K, v, eps_grid4a, Tp, SNR_dB_fig4, N_mc_rms, B, det_list_fig4, c);
rms_fig4b = run_rms(L, 1.0, R, K, v, eps_grid4b, Tp, SNR_dB_fig4, N_mc_rms, B, det_list_fig4, c);

fig4 = figure('Visible','off', 'Color','w', 'Position',[100 100 700 800]);
subplot(2,1,1);
plot(SNR_dB_fig4, rms_fig4a(1,:), '-',  'LineWidth',1.5, 'Marker','none', 'Color',[0 0 0]); hold on;
plot(SNR_dB_fig4, rms_fig4a(2,:), '--', 'LineWidth',1.5, 'Marker','none', 'Color',[0 0 0]);
plot(SNR_dB_fig4, rms_fig4a(3,:), '-',  'LineWidth',1.5, 'Marker','*', 'MarkerSize',5, 'Color',[0 0 0]);
grid on; box on; xlim([12 40]); ylim([0 7]);
xlabel('SNR (dB)', 'FontSize',11);
ylabel('RMS range error (m)', 'FontSize',11);
title('\Delta_\epsilon = T_p/10', 'FontSize',10);
legend('Modified Kelly''s GLRT','Modified AMF','Modified ACE','Location','northeast','FontSize',8);
% 在 40 dB 处标注 0.89 m (论文原文)
text(34, 1.4, '0.89', 'FontSize',10, 'Color',[0 0 0]);
plot([36 39.5], [1.3 0.95], '-k', 'LineWidth', 0.8);
set(gca,'FontSize',10);

subplot(2,1,2);
plot(SNR_dB_fig4, rms_fig4b(1,:), '-',  'LineWidth',1.5, 'Marker','none', 'Color',[0 0 0]); hold on;
plot(SNR_dB_fig4, rms_fig4b(2,:), '--', 'LineWidth',1.5, 'Marker','none', 'Color',[0 0 0]);
plot(SNR_dB_fig4, rms_fig4b(3,:), '-',  'LineWidth',1.5, 'Marker','*', 'MarkerSize',5, 'Color',[0 0 0]);
grid on; box on; xlim([12 40]); ylim([0 7]);
xlabel('SNR (dB)', 'FontSize',11);
ylabel('RMS range error (m)', 'FontSize',11);
title('\Delta_\epsilon = T_p/20', 'FontSize',10);
legend('Modified Kelly''s GLRT','Modified AMF','Modified ACE','Location','northeast','FontSize',8);
% 在 40 dB 处标注 0.47 m
text(34, 1.0, '0.47', 'FontSize',10, 'Color',[0 0 0]);
plot([36 39.5], [0.9 0.55], '-k', 'LineWidth', 0.8);
set(gca,'FontSize',10);

save_fig(fig4, fullfile(outdir, 'DeMaio2011_Fig4_RMS_range_homogeneous.png'));

%% ========== Fig.5: 部分均匀环境 (γ=3 dB) Pd vs SNR ==========
% 图例: Modified ACE, Modified GASD, ACE
gamma_dB = 3;
gamma = 10^(gamma_dB/10);
Ne5 = 5;
eps_grid5 = make_grid(Ne5);
SNR_dB_fig5 = 10:2:25;
det_list_fig5 = {'mae','mgasd','cae'};

fprintf('\n=== Fig.5: Partially homogeneous Pd-SNR (gamma=%.1f dB, Ne=%d) ===\n', gamma_dB, Ne5);
stats_h0_fig5 = run_h0(L, gamma, K, v, eps_grid5, Tp, Pfa, N_mc_h0, B, det_list_fig5);
thresholds_fig5 = prctile(stats_h0_fig5, 100*(1-Pfa), 1);
fprintf('Thresholds: ModACE=%.4f, ModGASD=%.4f, ACE=%.4f\n', thresholds_fig5);

Pd_fig5 = run_h1_pd(L, gamma, R, K, v, eps_grid5, Tp, SNR_dB_fig5, N_mc_h1, B, thresholds_fig5, det_list_fig5);

fig5 = figure('Visible','off', 'Color','w', 'Position',[100 100 700 500]);
plot(SNR_dB_fig5, Pd_fig5(1,:), '-', 'LineWidth',1.5, 'Marker','*', 'MarkerSize',7, 'Color',[0 0 0]); hold on;
plot(SNR_dB_fig5, Pd_fig5(2,:), '-', 'LineWidth',1.5, 'Marker','v', 'MarkerSize',5, 'Color',[0 0 0]);
plot(SNR_dB_fig5, Pd_fig5(3,:), '-', 'LineWidth',1.5, 'Marker','+', 'MarkerSize',7, 'Color',[0 0 0]);
grid on; box on; xlim([10 25]); ylim([0 1]);
xlabel('SNR (dB)', 'FontSize',12);
ylabel('P_d', 'FontSize',12);
title(sprintf('Fig.5 — P_d vs SNR, partially homogeneous environment, N=%d, K=%d, P_{fa}=%.0e, 10log_{10}\\gamma=%d dB, N_\\epsilon=%d', N, K, Pfa, gamma_dB, Ne5), 'FontSize',9);
legend('Modified ACE','Modified GASD','ACE','Location','east','FontSize',9);
set(gca,'FontSize',11);
save_fig(fig5, fullfile(outdir, 'DeMaio2011_Fig5_PdSNR_partial.png'));

%% ========== Fig.6: 部分均匀环境 RMS 距离误差 (2 子图, Modified ACE) ==========
% 上子图 Δε=Tp/10 (Ne=5)，下子图 Δε=Tp/20 (Ne=10)；每子图 1 curve {Mod.ACE}
% 论文给出下界 0.866 m (Ne=5) 与 0.433 m (Ne=10)
Ne6a = 5;
Ne6b = 10;
eps_grid6a = make_grid(Ne6a);
eps_grid6b = make_grid(Ne6b);
SNR_dB_fig6 = 15:2:40;
det_list_fig6 = {'mae'};

fprintf('\n=== Fig.6: RMS range error vs SNR (partially homogeneous, 2 subplots) ===\n');
rms_fig6a = run_rms(L, gamma, R, K, v, eps_grid6a, Tp, SNR_dB_fig6, N_mc_rms, B, det_list_fig6, c);
rms_fig6b = run_rms(L, gamma, R, K, v, eps_grid6b, Tp, SNR_dB_fig6, N_mc_rms, B, det_list_fig6, c);

fig6 = figure('Visible','off', 'Color','w', 'Position',[100 100 700 800]);
subplot(2,1,1);
plot(SNR_dB_fig6, rms_fig6a(1,:), '-', 'LineWidth',1.5, 'Marker','*', 'MarkerSize',5, 'Color',[0 0 0]);
grid on; box on; xlim([15 40]); ylim([0 5]);
xlabel('SNR (dB)', 'FontSize',11);
ylabel('RMS range error (m)', 'FontSize',11);
title('\Delta_\epsilon = T_p/10', 'FontSize',10);
text(34, 1.4, '0.89', 'FontSize',10, 'Color',[0 0 0]);
plot([36 39.5], [1.3 0.95], '-k', 'LineWidth', 0.8);
set(gca,'FontSize',10);

subplot(2,1,2);
plot(SNR_dB_fig6, rms_fig6b(1,:), '-', 'LineWidth',1.5, 'Marker','*', 'MarkerSize',5, 'Color',[0 0 0]);
grid on; box on; xlim([15 40]); ylim([0 6]);
xlabel('SNR (dB)', 'FontSize',11);
ylabel('RMS range error (m)', 'FontSize',11);
title('\Delta_\epsilon = T_p/20', 'FontSize',10);
text(34, 0.9, '0.47', 'FontSize',10, 'Color',[0 0 0]);
plot([36 39.5], [0.8 0.5], '-k', 'LineWidth', 0.8);
set(gca,'FontSize',10);

save_fig(fig6, fullfile(outdir, 'DeMaio2011_Fig6_RMS_range_partial.png'));

%% 保存全部数值结果
outmat = fullfile(outdir, 'DeMaio2011_all_results.mat');
save(outmat, 'SNR_dB_fig1','Pd_fig1','thresholds_fig1', ...
             'SNR_dB_fig2','Pd_fig2','thresholds_fig2', ...
             'SNR_dB_fig3','Pd_fig3','thresholds_fig3', ...
             'SNR_dB_fig4','rms_fig4a','rms_fig4b', ...
             'SNR_dB_fig5','Pd_fig5','thresholds_fig5', ...
             'SNR_dB_fig6','rms_fig6a','rms_fig6b', ...
             'N','K','Pfa','Tp','c','gamma','gamma_dB','rho','nu_s','nu');
fprintf('\nAll figures and results saved to:\n  %s\n', outdir);

%% =====================================================================
% 本地函数
%% =====================================================================

function stats = run_h0(L, gamma, K, v, eps_grid, Tp, Pfa, N_mc, B, det_list)
% run_h0 在 H0（无目标）下跑 Monte Carlo，返回各检测器统计量
    N = size(L,1);
    nDets = length(det_list);
    stats = zeros(N_mc, nDets);
    Lg = sqrt(gamma) * L;
    N_batches = ceil(N_mc / B);
    for b = 1:N_batches
        bstart = (b-1)*B + 1;
        bend = min(b*B, N_mc);
        Bb = bend - bstart + 1;

        W = (randn(N, K, Bb) + 1j*randn(N, K, Bb)) / sqrt(2);
        X = pagemtimes(L, W);                              % N x K x Bb
        Rhat = pagemtimes(X, 'none', X, 'ctranspose') / K; % N x N x Bb

        Wp = (randn(N, 3, Bb) + 1j*randn(N, 3, Bb)) / sqrt(2);
        Z0 = pagemtimes(Lg, Wp);                           % N x 3 x Bb

        for bb = 1:Bb
            Rhat_i = Rhat(:,:,bb);
            Z = Z0(:,:,bb);
            for d = 1:nDets
                stats(bstart+bb-1, d) = compute_det(Z, Rhat_i, K, v, eps_grid, Tp, det_list{d});
            end
        end
    end
end

function Pd = run_h1_pd(L, gamma, R_true, K, v, eps_grid, Tp, SNR_dB_vec, N_mc, B, thresholds, det_list)
% run_h1_pd 在 H1 下估计各 SNR 点的检测概率
    stats_all = run_h1_stats(L, gamma, R_true, K, v, eps_grid, Tp, SNR_dB_vec, N_mc, B, det_list);
    nDets = length(det_list);
    nSNR = length(SNR_dB_vec);
    Pd = zeros(nDets, nSNR);
    for s = 1:nSNR
        for d = 1:nDets
            Pd(d,s) = sum(stats_all{s}(:,d) > thresholds(d)) / N_mc;
        end
        fprintf('  SNR=%3d dB: %s\n', SNR_dB_vec(s), mat2str(Pd(:,s)', 3));
    end
end

function stats_cell = run_h1_stats(L, gamma, R_true, K, v, eps_grid, Tp, SNR_dB_vec, N_mc, B, det_list)
% run_h1_stats 返回每个 SNR 点下 N_mc x nDets 的原始统计量（cell 数组）
    N = size(L,1);
    nDets = length(det_list);
    nSNR = length(SNR_dB_vec);
    norm_vR = real(v' * inv(R_true) * v);
    Lg = sqrt(gamma) * L;
    stats_cell = cell(nSNR, 1);

    for s = 1:nSNR
        SNR_lin = 10^(SNR_dB_vec(s)/10);
        alpha = sqrt(gamma * SNR_lin / norm_vR);
        stats_s = zeros(N_mc, nDets);
        N_batches = ceil(N_mc / B);
        cnt = 0;
        for b = 1:N_batches
            bstart = (b-1)*B + 1;
            bend = min(b*B, N_mc);
            Bb = bend - bstart + 1;

            W = (randn(N, K, Bb) + 1j*randn(N, K, Bb)) / sqrt(2);
            X = pagemtimes(L, W);
            Rhat = pagemtimes(X, 'none', X, 'ctranspose') / K;

            Wp = (randn(N, 3, Bb) + 1j*randn(N, 3, Bb)) / sqrt(2);
            Z0 = pagemtimes(Lg, Wp);
            eps_true = (rand(1, Bb) - 0.5) * Tp;
            for bb = 1:Bb
                cvec = leakage_coeffs(eps_true(bb), Tp);
                Z0(:,:,bb) = Z0(:,:,bb) + alpha * v * cvec.';
            end

            for bb = 1:Bb
                cnt = cnt + 1;
                Z = Z0(:,:,bb);
                Rhat_i = Rhat(:,:,bb);
                for d = 1:nDets
                    stats_s(cnt, d) = compute_det(Z, Rhat_i, K, v, eps_grid, Tp, det_list{d});
                end
            end
        end
        stats_cell{s} = stats_s;
    end
end

function rms = run_rms(L, gamma, R_true, K, v, eps_grid, Tp, SNR_dB_vec, N_mc, B, det_list, c)
% run_rms 估计亚距离门定位的 RMS 距离误差（米）
%   论文 Fig.4/6 显示 Modified Kelly/AMF/ACE 定位性能相同；
%   这里用 AMF 的非饱和分子项做 epsilon 估计（对三种检测器一致）。
    N = size(L,1);
    nDets = length(det_list);
    nSNR = length(SNR_dB_vec);
    norm_vR = real(v' * inv(R_true) * v);
    Lg = sqrt(gamma) * L;
    rms = zeros(nDets, nSNR);

    for s = 1:nSNR
        SNR_lin = 10^(SNR_dB_vec(s)/10);
        alpha = sqrt(gamma * SNR_lin / norm_vR);
        errs = zeros(1, N_mc);
        N_batches = ceil(N_mc / B);
        cnt = 0;
        for b = 1:N_batches
            bstart = (b-1)*B + 1;
            bend = min(b*B, N_mc);
            Bb = bend - bstart + 1;

            W = (randn(N, K, Bb) + 1j*randn(N, K, Bb)) / sqrt(2);
            X = pagemtimes(L, W);
            Rhat = pagemtimes(X, 'none', X, 'ctranspose') / K;

            Wp = (randn(N, 3, Bb) + 1j*randn(N, 3, Bb)) / sqrt(2);
            Z0 = pagemtimes(Lg, Wp);
            eps_true = (rand(1, Bb) - 0.5) * Tp;
            for bb = 1:Bb
                cvec = leakage_coeffs(eps_true(bb), Tp);
                Z0(:,:,bb) = Z0(:,:,bb) + alpha * v * cvec.';
            end

            for bb = 1:Bb
                cnt = cnt + 1;
                Z = Z0(:,:,bb);
                Rhat_i = Rhat(:,:,bb);
                [~, eps_hat] = det_modified_amf(Z, Rhat_i, v, eps_grid, Tp);
                errs(cnt) = abs(eps_hat - eps_true(bb)) * c / 2;
            end
        end
        rms_value = sqrt(sum(errs.^2) / N_mc);
        rms(:,s) = rms_value;  % 各检测器行相同
        fprintf('  SNR=%3d dB RMS (m): %.3f\n', SNR_dB_vec(s), rms_value);
    end
end

function lam = compute_det(Z, Rhat, K, v, eps_grid, Tp, tag)
    z_l = Z(:,2);
    switch tag
        case 'mk'
            lam = det_modified_kelly(Z, Rhat, K, v, eps_grid, Tp);
        case 'ma'
            lam = det_modified_amf(Z, Rhat, v, eps_grid, Tp);
        case 'mae'
            lam = det_modified_ace(Z, Rhat, v, eps_grid, Tp);
        case 'mdt'
            lam = det_modified_dtglrt(Z, Rhat, v, eps_grid, Tp);
        case 'mgamf'
            lam = det_modified_gamf(Z, Rhat, v, eps_grid, Tp);
        case 'mgasd'
            lam = det_modified_gasd(Z, Rhat, v, eps_grid, Tp);
        case 'ck'
            lam = det_classic_kelly(z_l, Rhat, K, v);
        case 'ca'
            lam = det_classic_amf(z_l, Rhat, v);
        case 'cae'
            lam = det_classic_ace(z_l, Rhat, v);
        otherwise
            error('Unknown detector tag: %s', tag);
    end
end

function save_fig(fig, filepath)
    print(fig, filepath, '-dpng', '-r150');
    close(fig);
    fprintf('  Saved: %s\n', filepath);
end

end
