%% 测试脚本 test_gs_qr.m
clc; clear; close all;

% 设置随机种子，保证可重复性
rng(42);

%% 参数设置
m = 200;          % 信号维度
N = 500;          % 字典原子总数
K = 20;           % 选择的支撑集大小

% 生成随机字典（每个原子随机方向）
D = randn(m, N);
D = D ./ vecnorm(D);   % 单位化

% 随机选择支撑集索引
support = randperm(N, K);
A = D(:, support);     % 支撑集矩阵 m x K

fprintf('支撑集大小 K = %d\n', K);

%% 测试 1: 基本 QR 分解
[Q1, R1] = gs_qr(A);

% 检查 A = Q * R
err_QR = norm(A - Q1 * R1, 'fro');
fprintf('误差 ||A - Q*R||_F = %.3e\n', err_QR);

% 检查 Q 的正交性
err_orth = norm(Q1' * Q1 - eye(K), 'fro');
fprintf('误差 ||Q^T Q - I||_F = %.3e\n', err_orth);

% 检查 R 是否为上三角
is_upper = isequal(R1, triu(R1));
fprintf('R 是否上三角: %d\n', is_upper);

%% 测试 2: 增量 QR 更新
% 取前 K-1 个原子作为旧支撑集
K_old = K - 1;
A_old = A(:, 1:K_old);
a_new = A(:, K);    % 新加入的原子

% 对旧支撑集做 QR 分解
[Q_old, R_old] = gs_qr(A_old);

% 增量更新
[Q_inc, R_inc] = gs_qr_update(Q_old, R_old, a_new);

% 直接分解完整矩阵
[Q_dir, R_dir] = gs_qr(A);

% 比较两种方式得到的 Q 和 R
err_Q = norm(Q_inc - Q_dir, 'fro');
err_R = norm(R_inc - R_dir, 'fro');
fprintf('增量更新与直接分解 Q 的误差 = %.3e\n', err_Q);
fprintf('增量更新与直接分解 R 的误差 = %.3e\n', err_R);

% 验证增量更新后的分解
err_QR_inc = norm(A - Q_inc * R_inc, 'fro');
fprintf('增量更新后 ||A - Q_inc*R_inc||_F = %.3e\n', err_QR_inc);

%% 测试 3: 验证在 OMP 中的使用（可选）
% 利用 QR 分解快速求解最小二乘问题
% 观测信号 y
y = D(:, support) * randn(K, 1) + 0.01 * randn(m, 1);

% 直接求解最小二乘
x_direct = A \ y;

% 使用 QR 分解求解
b = Q1' * y;           % Q^T y
x_qr = R1 \ b;         % 回代求解上三角系统

fprintf('QR 求解与直接求解的误差 = %.3e\n', norm(x_direct - x_qr));

%% 显示结果
fprintf('\n所有测试通过！\n');
