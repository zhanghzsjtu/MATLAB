%% check_mgs.m 验证 mgs_qr_fixed 的 j=1 中间值
M = 8; K = 4; Q15 = 2^15;
rng(123);
A_f = randn(M, K); A_f = A_f ./ vecnorm(A_f);
Aint = int16(clamp(round(A_f * Q15), -Q15, Q15 - 1));
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
fprintf('Aint col0: '); fprintf('%d ', Aint(:,1)); fprintf('\n');
fprintf('Aint col1: '); fprintf('%d ', Aint(:,2)); fprintf('\n');

[Qref, Rref] = mgs_qr_fixed(Aint, M, K);
fprintf('Rref(1,2) r_01 = %d\n', Rref(1,2));
fprintf('Rref(2,2) r_11 = %d\n', Rref(2,2));

% 单独复算 j=1
v = int16(Aint(:,2));
acc = int64(0);
for t = 1:M
    acc = acc + int64(Qref(t,1)) * int64(v(t));
end
rij = wrap16(bitshift(acc, -15));
fprintf('手动 r_01 = %d (Qref col1: ', rij);
fprintf('%d ', Qref(:,1)); fprintf(')\n');
for t = 1:M
    prod = int64(rij) * int64(Qref(t,1));
    subv = wrap16(bitshift(prod, -15));
    v(t) = wrap16(int32(v(t)) - int32(subv));
end
fprintf('手动 v_1: '); fprintf('%d ', v'); fprintf('\n');
sq = int64(0);
for t = 1:M
    p = int64(v(t)) * int64(v(t));
    sq = sq + p;
end
fprintf('手动 sq = %d\n', sq);
r11 = sqrt_fixed(uint32(bitand(uint64(sq), uint64(2^32-1))));
fprintf('手动 r_11 = %d\n', r11);

function y = wrap16(x)
    y = int16(bitand(int64(x), int64(2^16-1)));
end
function [Q, R] = mgs_qr_fixed(Aint, M, K)
    Q = zeros(M, K, 'int16');
    R = zeros(K, K, 'int16');
    for j = 0:K-1
        v = Aint(:, j+1);
        for i = 0:j-1
            acc = int64(0);
            for t = 0:M-1
                acc = acc + int64(Q(t+1, i+1)) * int64(v(t+1));
            end
            rij = wrap16(bitshift(acc, -15));
            R(i+1, j+1) = rij;
            for t = 0:M-1
                prod = int64(rij) * int64(Q(t+1, i+1));
                subv = wrap16(bitshift(prod, -15));
                v(t+1) = wrap16(int32(v(t+1)) - int32(subv));
            end
        end
        sq = int64(0);
        for t = 0:M-1
            p = int64(v(t+1)) * int64(v(t+1));
            sq = sq + p;
        end
        val32 = bitand(uint64(sq), uint64(2^32-1));
        rjj = sqrt_fixed(uint32(val32));
        R(j+1, j+1) = rjj;
        for t = 0:M-1
            Q(t+1, j+1) = div_fixed(v(t+1), rjj);
        end
    end
end
function q = div_fixed(v, r)
    if r == 0
        q = int16(0); return;
    end
    vsign = (int32(v) < 0);
    va = abs(int32(v));
    num = uint32(bitshift(uint32(va), 15));
    den = uint32(abs(int32(r)));
    rem = uint32(0); quot = uint32(0);
    for cnt = 0:29
        bit = bitand(bitshift(num, -(29-cnt)), uint32(1));
        rem = bitand(bitshift(rem, 1) + bit, uint32(2^32-1));
        if rem >= den
            rem = rem - den;
            quot = bitand(bitshift(quot, 1) + 1, uint32(2^32-1));
        else
            quot = bitand(bitshift(quot, 1), uint32(2^32-1));
        end
    end
    q = int16(bitand(quot, uint32(2^16-1)));
    if vsign, q = -q; end
end
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
function y = clamp(x, lo, hi)
    y = min(max(x, lo), hi);
end
