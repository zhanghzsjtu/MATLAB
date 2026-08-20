%% ============================================================================
%  stap_ref.m — STAP 空时二维自适应滤波 MATLAB 黄金标准
%  ----------------------------------------------------------------------------
%  场景：确定性——1 个慢速目标（v=1m/s，az=0°，主瓣中心）+ 强静止旁瓣杂波
%        （方位 +22°..+28°，多普勒 DC bin 附近）。目标与杂波在多普勒域重叠、
%        在空间域分离，是展示 STAP 空时抑制价值的标准场景（MTI 对慢速目标失效）。
%  链路：4 子阵回波生成（子阵相位中心 [-3,-1,1,3]×d）
%        → 每通道脉压（时域匹配滤波）→ 每通道多普勒 FFT（Hamming 窗）
%        → SMI 自适应权（训练区协方差 + 对角加载 + 求逆 + 导向矢量）
%        → 空时滤波 y(d,r) = w(d)^H·z(d,r)
%  输出（data/）：
%        stap_in.txt      4 通道谱 22bit 定点 hex（bin-major，每行 ch0_i ch0_q .. ch3_q）
%        stap_w_q15.mem   权值 Q15 hex（每 bin 一行，同 8 字段序）——FPGA $readmemh
%        stap_gold.txt    MATLAB 定点模拟 STAP 输出 22bit hex（每行 out_i out_q）
%  运行：matlab -batch "cd('matlab'); stap_ref"
%  对比：python tools/stap_rtl_compare.py
% ============================================================================
function stap_ref
clc;
addpath(genpath(pwd));

%% ===== 雷达参数（与项目 target_physics / doppler_fft 一致）=====
F_C     = 9.5e9;   C_LIGHT = 2.99792458e8;  LAMBDA  = C_LIGHT/F_C;
F_S     = 100e6;   PRF     = 22e3;          CPI     = 64;
N_RANGE = 192;     B_LFM   = 30e6;          T_PW    = 0.48e-6;
LFM_N   = 48;      CLUT_N  = 8;             R_REF   = 100.0;
GATE_M  = C_LIGHT/(2*F_S);
D_ELE   = 17.4e-3;                          % 单元间距
AZ_SCAN = 0;                                % 波束指向（电扫中心）
N_CH    = 4;
X_SUB   = [-3, -1, 1, 3] * D_ELE;           % 子阵相位中心（列偏移 × d）

% 发射 LFM + 匹配滤波加窗参考
t_lfm = (0:LFM_N-1)/F_S;   k_lfm = B_LFM/T_PW;
ref   = exp(1j*2*pi*0.5*k_lfm*t_lfm.^2);
win_lfm = 0.54 - 0.46*cos(2*pi*(0:LFM_N-1)/(LFM_N-1));
ref_w   = ref .* win_lfm;
win_dop = (0.54 - 0.46*cos(2*pi*(0:CPI-1)/(CPI-1))).';

%% ===== 确定性场景：1 慢速目标 + 强旁瓣杂波（空时分离）=====
% 目标：v=1m/s（近悬停，多普勒≈DC bin，与静止杂波重叠——MTI 失效点）、
%       az=0°（主瓣中心）、R=135m（门 90）、RCS=0.005
% 杂波：静止（v=0，DC bin），方位 +22°..+28°（旁瓣区，与目标空间分离 >1 波束宽
%       17.9°），40 个散射体，R=20m，强幅度 → STAP 用空间自由度抑制旁瓣杂波
TGT.r0   = 135;   TGT.v_rad = 1;    TGT.az  = 0;
TGT.el   = 5;     TGT.rcs   = 0.005;
CLUT.n   = 40;
CLUT.r0  = 20;    CLUT.az  = linspace(22, 28, CLUT.n);
CLUT.amp = 6;     CLUT.v   = 0;

% 子阵对 (az) 的复增益：g_m = exp(j·k·x_m·sin(az-az_scan))
k0 = 2*pi/LAMBDA;
g_sub = @(az) exp(1j*k0*X_SUB.'*sind(az - AZ_SCAN));   % 4×1

%% ===== 4 子阵回波生成（[ch][pulse][gate]）=====
sig = zeros(N_CH, CPI, N_RANGE);
rbin_t = round(TGT.r0/GATE_M) + 1;           % 1 基目标门
g4t = g_sub(TGT.az);
rb_c = round(CLUT.r0/GATE_M) + 1;            % 1 基杂波门
rg_c = rb_c : rb_c+CLUT_N-1;
rg_c = rg_c(rg_c>=1 & rg_c<=N_RANGE);
for m = 1:N_CH
    sig_m = zeros(CPI, N_RANGE);             % 每通道独立 2D 累加
    % 目标
    for p = 1:CPI
        R  = TGT.r0 - TGT.v_rad*((p-1)-(CPI-1)*0.5)/PRF;
        A  = 10*sqrt(TGT.rcs/0.01)*(R_REF/R)^2;
        env = A*exp(1j*4*pi*R/LAMBDA);
        rg  = rbin_t : rbin_t+LFM_N-1;
        rg  = rg(rg>=1 & rg<=N_RANGE);
        sig_m(p, rg) = sig_m(p, rg) + g4t(m)*env*ref(1:numel(rg));
    end
    % 杂波（40 个静止散射体，确定性相位 → 协方差含杂波空间谱）
    for c = 1:CLUT.n
        g4c = g_sub(CLUT.az(c));
        ph_c = mod(c*7919, 1e9)/1e9*2*pi;    % 确定性随机相位
        amp = CLUT.amp*(R_REF/CLUT.r0)^2;
        for p = 1:CPI
            seg = amp*exp(1j*ph_c) * ref(1:numel(rg_c));
            sig_m(p, rg_c) = sig_m(p, rg_c) + g4c(m)*seg;
        end
    end
    sig(m,:,:) = sig_m;
end

%% ===== 每通道脉压 → 多普勒 FFT（[ch][bin][gate]）=====
X = zeros(N_CH, CPI, N_RANGE);
for m = 1:N_CH
    sm = squeeze(sig(m,:,:));          % CPI×N_RANGE（2D 中间，避免 3D 赋值）
    for p = 1:CPI
        sm(p,:) = pc_conv(sm(p,:), ref_w);
    end
    for r = 1:N_RANGE
        X(m,:,r) = fft(sm(:,r) .* win_dop, CPI);
    end
end

%% ===== SMI 自适应权（每多普勒 bin 独立）=====
RT = round(TGT.r0/GATE_M) + 1;              % 1 基目标门
GUARD = 8;
train_r = setdiff(1:N_RANGE, (RT-GUARD):(RT+GUARD));
train_r = train_r(train_r >= 1 & train_r <= N_RANGE);
N_TRAIN = min(24, numel(train_r));
train_r = train_r(1:N_TRAIN);
s_tgt = g_sub(TGT.az);                       % 4×1 导向（指向目标）
W = zeros(4, CPI);                           % [ch][bin] 复数权
for d = 1:CPI
    Z = squeeze(X(:, d, train_r));           % 4×N_TRAIN 快拍
    Rhat = (Z * Z') / N_TRAIN;               % 4×4 采样协方差
    Rhat = Rhat + 1e-2*trace(Rhat)/N_CH * eye(N_CH);   % 对角加载（数值稳定）
    w0 = Rhat \ s_tgt;                       % SMI 最优权
    W(:, d) = w0 / (s_tgt' * w0);            % MVDR 归一：目标方向增益=1（防整体下溢）
end

%% ===== 空时滤波 y(d,r) = w(d)^H·z(d,r)（黄金 float）=====
Y_float = zeros(CPI, N_RANGE);
for d = 1:CPI
    Y_float(d, :) = W(:, d)' * squeeze(X(:, d, :));
end

%% ===== 定点化（与 FPGA stap_4ch 一致：22bit 复数谱 × Q15 复数权）=====
Xmax = max(abs(X(:)));
Xq = round(X / Xmax * (2^21 - 1));
Xq = max(-2^21, min(2^21-1, real(Xq))) + 1j*max(-2^21, min(2^21-1, imag(Xq)));
Wmax = max(abs(W(:)));
Wq = round(W / Wmax * 32767);
Wq = max(-32768, min(32767, real(Wq))) + 1j*max(-32768, min(32767, imag(Wq)));
Yq = zeros(CPI, N_RANGE);                    % 定点模拟（round >>15 饱和，复 I/Q）
% 注意：y = w^H·x = Σ conj(w_m)·x_m（与浮点 Y_float 同口径，RTL 复乘同公式）
for d = 1:CPI
    acc = zeros(1, N_RANGE);
    for m = 1:N_CH
        acc = acc + conj(Wq(m,d)) * squeeze(Xq(m,d,:)).';
    end
    acc = round(acc / 32768);
    acc = max(-2^21, min(2^21-1, real(acc))) + 1j*max(-2^21, min(2^21-1, imag(acc)));
    Yq(d, :) = acc;
end

%% ===== 抑制统计（浮点谱幅度）=====
c0 = 1;                                       % 静止杂波 bin（fft 后 0 频率）
r_clut = rb_c;                                % 杂波门（1 基）
% 以 4 通道同相合成（单位权）作为"抑制前"参考（= 全阵和通道）
Y_uni = zeros(CPI, N_RANGE);
for d = 1:CPI
    Y_uni(d, :) = ones(1, N_CH) * squeeze(X(:, d, :));
end
amp_before_clut = abs(Y_uni(c0, r_clut));
amp_after_clut  = abs(Y_float(c0, r_clut));
amp_tgt_before  = abs(Y_uni(c0, RT));
amp_tgt         = abs(Y_float(c0, RT));
fprintf('===== STAP 黄金（慢速目标 v=1m/s + 强静止杂波）=====\n');
fprintf('  杂波区(门%d) 抑制前 |Y_uni|=%.1f → 抑制后 |Y_stap|=%.1f  增益 %.1f dB\n', ...
    r_clut, amp_before_clut, amp_after_clut, 20*log10((amp_before_clut+1e-9)/(amp_after_clut+1e-9)));
fprintf('  目标门(%d)  抑制前 |Y_uni|=%.1f → 抑制后 |Y_stap|=%.1f\n', ...
    RT, amp_tgt_before, amp_tgt);
fprintf('  STAP 后目标/杂波比 = %.1f dB（抑制前 %.1f dB）\n', ...
    20*log10((amp_tgt+1e-9)/(amp_after_clut+1e-9)), ...
    20*log10((amp_tgt_before+1e-9)/(amp_before_clut+1e-9)));
% 诊断（定点域自洽性）：Yq 应为 Y_float × C（C = 2^21/Xmax × 32767/Wmax / 32768）
fprintf('  [diag] Xmax=%.4e Wmax=%.4e C=%.2f\n', Xmax, Wmax, 2^21/Xmax*32767/Wmax/32768);
fprintf('  [diag] 杂波门 Y_float=%.1f Yq=%d  目标门 Y_float=%.1f Yq=%d\n', ...
    abs(Y_float(c0,r_clut)), Yq(c0,r_clut), abs(Y_float(c0,RT)), Yq(c0,RT));

%% ===== 输出文件（data/）=====
outdir = fullfile(pwd, '..', 'data');
if ~exist(outdir, 'dir'), mkdir(outdir); end
% 22bit/16bit 补码 hex 辅助
to_hex6 = @(v) sprintf('%06X', mod(double(v), 2^22));
to_hex4 = @(v) sprintf('%04X', mod(double(v), 2^16));

% 1) 激励 stap_in.txt：4 通道复数谱 22bit 补码 hex，bin-major
%    每行 8 字段：ch0_i ch0_q ch1_i ch1_q ch2_i ch2_q ch3_i ch3_q
fid = fopen(fullfile(outdir, 'stap_in.txt'), 'w');
for d = 0:CPI-1
    for r = 1:N_RANGE
        for m = 1:N_CH
            v = squeeze(Xq(m, d+1, r));
            fprintf(fid, '%s %s ', to_hex6(real(v)), to_hex6(imag(v)));
        end
        fprintf(fid, '\n');
    end
end
fclose(fid);

% 2) 权值 stap_w_q15.mem：Q15 补码 hex，每 bin 一行 8 字段（同序）
fid = fopen(fullfile(outdir, 'stap_w_q15.mem'), 'w');
for d = 0:CPI-1
    for m = 1:N_CH
        w = Wq(m, d+1);
        fprintf(fid, '%s %s ', to_hex4(real(w)), to_hex4(imag(w)));
    end
    fprintf(fid, '\n');
end
fclose(fid);

% 3) 黄金输出 stap_gold.txt：22bit 补码 hex，每行 out_i out_q，顺序同激励
fid = fopen(fullfile(outdir, 'stap_gold.txt'), 'w');
for d = 0:CPI-1
    for r = 1:N_RANGE
        v = Yq(d+1, r);
        fprintf(fid, '%s %s\n', to_hex6(real(v)), to_hex6(imag(v)));
    end
end
fclose(fid);
fprintf('  saved data/（stap_in.txt / stap_w_q15.mem / stap_gold.txt）\n');
end

%% ===== 局部：脉压（时域匹配滤波）=====
function y = pc_conv(x, ref_w)
L = numel(ref_w);
y = zeros(size(x));
for r = 1:numel(x)
    hi = min(numel(x), r+L-1);
    n  = hi-r+1;
    y(r) = sum(conj(ref_w(1:n)) .* x(r:hi));
end
end
