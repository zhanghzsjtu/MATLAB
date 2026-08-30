%% gen_rtl_vectors.m 生成 RTL 仿真测试向量与定点参考结果
% 定点规则与 Verilog 模块 qr_decompose_mgs 完全一致（Q1.15, W=16）
% 输出: a_mem.hex (A), q_golden.hex (Q), r_golden.hex (R)
clc; clear; close all;

W = 16; M = 8; K = 4;
Q15 = 2^15;

%% 生成测试矩阵并量化 Q1.15
rng(123);
A_f = randn(M, K);
A_f = A_f ./ vecnorm(A_f);              % 列单位化
Aint = int16(clamp(round(A_f * Q15), -Q15, Q15 - 1));
% 列归一化到 ||Aint|| <= 32767, 避免 sqrt 输出越界(Q1.15 上限)
for jc = 1:K
    ss = int64(0);
    for tc = 1:M
        ss = ss + int64(Aint(tc, jc)) * int64(Aint(tc, jc));
    end
    s_norm = sqrt(double(ss));
    if s_norm > 32767
        sc = 32767 / s_norm;
        for tc = 1:M
            Aint(tc, jc) = int16(floor(double(Aint(tc, jc)) * sc));
        end
    end
end

%% 定点参考：完全模拟 RTL 运算规则
[Qref, Rref] = mgs_qr_fixed(Aint, M, K);

%% 输出文件（写 RTL 目录）
outdir = 'rtl_vec';
if ~exist(outdir, 'dir'); mkdir(outdir); end

% A: 32 个数, 地址 row*K+col, 每行一个 hex
fid = fopen(fullfile(outdir, 'a_mem.hex'), 'w');
for addr = 0:M*K-1
    row = floor(addr / K); col = mod(addr, K);
    fprintf(fid, '%04X\n', bits2signed(int16(Aint(row+1, col+1))));
end
fclose(fid);

% Q: 32 个数, 地址 row*K+col
fid = fopen(fullfile(outdir, 'q_golden.hex'), 'w');
for addr = 0:M*K-1
    row = floor(addr / K); col = mod(addr, K);
    fprintf(fid, '%04X\n', bits2signed(Qref(row+1, col+1)));
end
fclose(fid);

% R: K*(K+1)/2 = 10 个数, 索引 idx = j*(j+1)/2 + i (i<=j)
fid = fopen(fullfile(outdir, 'r_golden.hex'), 'w');
for j = 0:K-1
    for i = 0:j
        idx = j*(j+1)/2 + i;
        fprintf(fid, '%04X\n', bits2signed(Rref(i+1, j+1)));
    end
end
fclose(fid);

fprintf('vectors written to %s\n', outdir);
fprintf('A(first col): '); fprintf('%d ', Aint(:,1)); fprintf('\n');

%% 显示参考结果
fprintf('\nQref (Q1.15 int):\n'); disp(double(Qref));
fprintf('Rref (Q1.15 int):\n'); disp(double(Rref));

%% ================= 定点 MGS 参考 =================
function [Q, R] = mgs_qr_fixed(Aint, M, K)
    Q = zeros(M, K, 'int16');
    R = zeros(K, K, 'int16');
    for j = 0:K-1
        v = Aint(:, j+1);   % int16 列
        for i = 0:j-1
            % --- MAC: r_ij = sum(q_i'*v), 36 位累加, 取 [30:15] ---
            acc = int64(0);
            for t = 0:M-1
                acc = acc + int64(Q(t+1, i+1)) * int64(v(t+1));
            end
            rij = wrap16(bitshift(acc, -15));
            R(i+1, j+1) = rij;
            % --- SUB: v = v - (r_ij * q_i)>>15 ---
            for t = 0:M-1
                prod = int64(rij) * int64(Q(t+1, i+1));      % Q2.30
                subv = wrap16(bitshift(prod, -15));          % Q1.15
                v(t+1) = wrap16(int32(v(t+1)) - int32(subv));
            end
        end
        % --- NORM: sq = sum(v.^2), 34 位累加, 取低 32 位开方 ---
        sq = int64(0);
        for t = 0:M-1
            p = int64(v(t+1)) * int64(v(t+1));
            sq = sq + p;
        end
        val32 = bitand(uint64(sq), uint64(2^32-1));
        rjj = sqrt_fixed(uint32(val32));
        R(j+1, j+1) = rjj;
        % --- DIV: q_new = v / rjj, 16 拍逐位除法 ---
        for t = 0:M-1
            Q(t+1, j+1) = div_fixed(v(t+1), rjj);
        end
    end
end

%% ================= 逐位开方（32 位 -> 16 位, 16 拍） =================
function s = sqrt_fixed(val32)
    rem = uint32(0); res = uint32(0);
    for cnt = 0:15
        shift = 30 - 2*cnt;
        two = bitand(bitshift(val32, -shift), uint32(3));
        rem = bitand(bitshift(rem, 2) + two, uint32(2^32-1));
        trial = bitshift(res, 2) + 1;
        if rem >= trial
            rem = rem - trial;
            res = bitshift(res, 1) + 1;
        else
            res = bitshift(res, 1);
        end
    end
    s = int16(res);
end

%% ================= 逐位除法（16 拍恢复除法） =================
function q = div_fixed(v, r)
    if r == 0
        q = int16(0); return;
    end
    vsign = (int32(v) < 0);
    va = abs(int32(v));
    num = uint32(bitshift(uint32(va), 15));   % 31 位
    den = uint32(abs(int32(r)));
    rem = uint32(0); quot = uint32(0);
    for cnt = 0:15
        bit = bitand(bitshift(num, -(15-cnt)), uint32(1));
        rem = bitand(bitshift(rem, 1) + bit, uint32(2^32-1));
        if rem >= den
            rem = rem - den;
            quot = bitand(bitshift(quot, 1) + 1, uint32(2^32-1));
        else
            quot = bitand(bitshift(quot, 1), uint32(2^32-1));
        end
    end
    q = int16(quot);
    if vsign, q = -q; end
end

%% ================= 工具 =================
function y = wrap16(x)   % 取低 16 位并按有符号解释
    y = int16(bitand(int64(x), int64(2^16-1)));
end

function h = bits2signed(x)   % int16 -> uint16 位模式重解释(numeric, 供 fprintf %04X)
    h = typecast(int16(x), 'uint16');
end

function y = clamp(x, lo, hi)
    y = min(max(x, lo), hi);
end
