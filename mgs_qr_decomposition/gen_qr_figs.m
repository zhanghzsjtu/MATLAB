%% gen_qr_figs.m 生成 QR 分解误差函数与计算过程图
% 依赖 gs_qr.m / gs_qr_update.m（需在同一路径）
clc; clear; close all;

figdir = 'figs';
if ~exist(figdir, 'dir'); mkdir(figdir); end

%% 图1: 误差随支撑集大小 K 的变化（rng(42)）
rng(42);
m = 200; N = 500; Kmax = 50;
D = randn(m, N); D = D ./ vecnorm(D);
support = randperm(N, Kmax);
A = D(:, support);

errQR   = zeros(Kmax, 1);
errOrth = zeros(Kmax, 1);
errQinc = zeros(Kmax, 1);
errRinc = zeros(Kmax, 1);
for K = 1:Kmax
    Ak = A(:, 1:K);
    [Q1, R1] = gs_qr(Ak);
    errQR(K)   = norm(Ak - Q1 * R1, 'fro') / norm(Ak, 'fro');
    errOrth(K) = norm(Q1' * Q1 - eye(K), 'fro');
    if K >= 2
        [Qo, Ro] = gs_qr(Ak(:, 1:K-1));
        [Qi, Ri] = gs_qr_update(Qo, Ro, Ak(:, K));
        [Qd, Rd] = gs_qr(Ak);
        errQinc(K) = norm(Qi - Qd, 'fro');
        errRinc(K) = norm(Ri - Rd, 'fro');
    end
end

fig1 = figure('Position', [100 100 920 380], 'Color', 'w');
subplot(1, 2, 1);
semilogy(1:Kmax, errQR, 'b-o', 'LineWidth', 1.2, 'MarkerSize', 4); hold on;
semilogy(1:Kmax, errOrth, 'r-s', 'LineWidth', 1.2, 'MarkerSize', 4);
grid on; xlabel('Support size K'); ylabel('Frobenius error');
legend('||A-QR||_F / ||A||_F', '||Q^TQ - I||_F', 'Location', 'southeast');
title('MGS QR decomposition error vs K');

subplot(1, 2, 2);
idx = 2:Kmax;
semilogy(idx, errQinc(idx), 'g-o', 'LineWidth', 1.2, 'MarkerSize', 4); hold on;
semilogy(idx, errRinc(idx), 'm-s', 'LineWidth', 1.2, 'MarkerSize', 4);
grid on; xlabel('Support size K'); ylabel('Frobenius error');
legend('||Q_{inc}-Q_{dir}||_F', '||R_{inc}-R_{dir}||_F', 'Location', 'southeast');
title('Incremental update vs direct decomposition');
saveas(fig1, fullfile(figdir, 'fig1_err_vs_K.png'));
fprintf('fig1 saved\n');

%% 图2: MGS 计算过程示例（小矩阵逐步正交化）
rng(5);
m = 10; k = 6;
A2 = randn(m, k); A2 = A2 ./ vecnorm(A2);
[Q2, R2] = gs_qr(A2);

fig2 = figure('Position', [100 100 1200 360], 'Color', 'w');

% 左：每列正交化过程中残差范数下降
subplot(1, 3, 1); hold on;
for jj = 2:5
    v = A2(:, jj);
    rn = zeros(1, jj);
    for i = 1:jj-1
        rn(i) = norm(v);
        v = v - (Q2(:, i)' * v) * Q2(:, i);
    end
    rn(jj) = norm(v);
    plot(0:jj-1, rn, '-o', 'LineWidth', 1.2, 'MarkerSize', 4, ...
        'DisplayName', sprintf('column %d', jj));
end
grid on; xlabel('Orthogonalization step i'); ylabel('Residual norm ||v||');
legend('Location', 'northeast'); title('MGS: residual norm shrinking');

% 中：R 矩阵幅值热力图
subplot(1, 3, 2);
imagesc(abs(R2)); colorbar; axis square;
xlabel('j'); ylabel('i'); title('|R| (upper triangular)');

% 右：Q 正交性检验
subplot(1, 3, 3);
imagesc(abs(Q2' * Q2)); colorbar; axis square;
xlabel('j'); ylabel('i'); title('|Q^TQ| (identity check)');
saveas(fig2, fullfile(figdir, 'fig2_mgs_process.png'));
fprintf('fig2 saved\n');
