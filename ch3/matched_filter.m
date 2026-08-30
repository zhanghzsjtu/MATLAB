function y = matched_filter(rx_sub, ref, fs)
% matched_filter  式 3-19 分段脉冲压缩 (匹配滤波)
%   y(t) = s_R_sub(t) ⊗ s*_T_sub(-t)
%   频域实现: Y = IFFT( FFT(rx_sub) .* conj(FFT(ref)) )
%   归一化: 峰值 = 子脉冲能量 (与 Python 实现一致)
%
%   输入: rx_sub 某子载波对应的时域回波 (1 x n)
%         ref    对应子脉冲的发射参考信号 (1 x n_ref)
%         fs     采样率
%   输出: y      脉冲压缩结果 (1 x n), 与 rx_sub 等长 ('same' 对齐)

n     = numel(rx_sub);
n_ref = numel(ref);
nfft  = 2^nextpow2(n + n_ref - 1);

Y = fft(rx_sub, nfft) .* conj(fft(ref, nfft));
y = ifft(Y);

% 线性卷积: 目标峰位于 rx_sub 中目标分量起点处, 直接截取前 n 点
% (若做 circshift(-n_ref/2) 会把峰向左偏移 n_ref/2 个样本, 造成
%  脉压峰位置偏离真实时延, 故不做该移位)
y = y(1:n);

% 归一化使峰值等于子脉冲能量
ref_e = sum(abs(ref).^2) + eps;
y = y * fs / ref_e;

end
