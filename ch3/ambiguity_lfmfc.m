function [chi2, tau, fd] = ambiguity_lfmfc(s, fs, n_fd, fd_os)
% ambiguity_lfmfc  数值模糊函数 式 3-3
%   χ(τ,f_d) = ∫ s(t) s*(t-τ) e^{j2π f_d t} dt
%   频域实现: 对每个 f_d, χ(τ) = IFFT( fftshift(S)·conj(S(f-f_d)) )
%
%   输入: s     复基带信号 (1 x N)
%         fs    采样率
%         n_fd  多普勒轴采样数 (每四分之一的 fd 范围)
%         fd_os 多普勒过采样因子
%   输出: chi2  |χ(τ,f_d)|^2 归一化矩阵 (2N x (n_fd*fd_os+1))
%         tau   τ 轴 (s), 范围 [-N/fs, N/fs]
%         fd    f_d 轴 (Hz), 范围 [-fs/2, fs/2]

if nargin < 3
    n_fd = 96;
end
if nargin < 4
    fd_os = 4;
end

N = numel(s);
n_fft = 2 * N;
S = fft(s, n_fft);
tau = ((0:n_fft-1) - N) / fs;              % τ 轴

fd_max = fs / 2;
fd = linspace(-fd_max, fd_max, n_fd*fd_os + 1);

f = (-n_fft/2:n_fft/2-1) * fs / n_fft;     % 升序频率轴
S_sorted = fftshift(S);

chi2 = zeros(n_fft, numel(fd));
for i = 1:numel(fd)
    S_shift = interp1(f - fd(i), S_sorted, f, 'linear', 0);
    prod = fftshift(S) .* conj(S_shift);
    % ifft 输出为线性时域 (τ=0 在索引 1), fftshift 后与中心对称 τ 轴对齐
    chi_tau = fftshift(ifft(ifftshift(prod)));
    chi2(:, i) = abs(chi_tau).^2;
end
chi2 = chi2 / (max(chi2(:)) + eps);

end
