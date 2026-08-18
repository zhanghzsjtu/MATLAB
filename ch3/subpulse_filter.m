function rx_sub = subpulse_filter(rx, fs, p, a, guard)
% subpulse_filter  式 3-18 窄带带通滤波器组分离子脉冲
%   对回波 FFT 后在频域进行带通滤波 (带宽 B_BPF), 再 IFFT 得到
%   对应不同频率编码的子脉冲回波 s_R_sub(t,n,k) = s_r + j + n2
%
%   输入: rx    回波信号 (1 x n)
%         fs    采样率
%         p     参数结构体
%         a     频率码字 (1xK)
%         guard 滤波器带宽扩展比例 (相对 B_sub), 默认 0.1
%   输出: rx_sub  (K x n) 子脉冲回波矩阵, 每行一个子载波

if nargin < 5
    guard = 0.1;
end

K     = p.K;
df    = p.df;
B_sub = p.B_sub;
B_BPF = B_sub * (1 + 2 * guard);          % 带通滤波器带宽

n     = numel(rx);
nfft  = 2^nextpow2(n);
R     = fft(rx, nfft);

% 频率轴 (中心化, 与 fftshift 对应)
f = (0:nfft-1) / nfft * fs;
f(f > fs/2) = f(f > fs/2) - fs;

rx_sub = zeros(K, n);
for k = 1:K
    fc   = a(k) * df;                     % 第 k 个子脉冲中心频率
    mask = abs(f - fc) <= B_BPF / 2;      % 频域矩形带通窗
    Y = R;
    Y(~mask) = 0;
    y_full = ifft(Y);                     % nfft 点
    rx_sub(k, :) = y_full(1:n);           % 截断回原长度
end

end
