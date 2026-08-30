function j = isrj_noise_mod(n_total, fs, T_j, T_s, G, tau_j, A_j, seed, s_tx)
% isrj_noise_mod  式 3-14 ~ 3-16 基于噪声调制的间歇采样转发干扰
%   每个采样时隙内填充一段相互独立的宽带复高斯信号, 作为噪声调频
%   干扰 (式 3-14) 的宽带等效形式, 对应式 3-15 (ISRJ-DF, G=1) 与
%   式 3-16 (ISRJ-RF, G>=2) 的时隙结构。干扰能量覆盖全部子脉冲频带,
%   使被干扰子脉冲时窗内 |rx|^2 方差显著大于干净子脉冲, Otsu 方差判别
%   可稳定工作 (与既有 Python 复现一致的模型)。
%
%   输入: n_total 输出信号长度
%         fs      采样率
%         T_j     干扰采样宽度
%         T_s     间歇采样重复周期
%         G       重复转发次数 (G=1 直接转发; G>=2 重复转发)
%         tau_j   干扰时延
%         A_j     干扰幅值 (10^(JSR/20))
%         seed    随机种子
%         s_tx    发射信号 (1 x n_pulse, 兼容签名, 宽带模型下不使用)
%   输出: j       干扰信号 (1 x n_total)

rng(seed);
n_j = round(T_j * fs);
n_s = round(T_s * fs);

j = zeros(1, n_total);
P = floor(n_total / fs / T_s) + 1;

for n = 0:P-1
    for g = 0:G-1
        pos = round((tau_j + n*T_s + g*T_j) * fs) + 1;
        if pos + n_j - 1 <= n_total
            % 宽带复噪声 (噪声调频干扰的宽带等效)
            seg = (randn(1, n_j) + 1j * randn(1, n_j)) / sqrt(2);
            j(pos:pos+n_j-1) = j(pos:pos+n_j-1) + A_j * seg;
        end
    end
end

end
