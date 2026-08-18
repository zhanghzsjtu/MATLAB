function a = freq_codes(K, seed)
% freq_codes  式 3-1 频率码字 a_m
%   输入: K    子脉冲数(编码种类)
%         seed 随机种子 (固定排列, 保证可复现)
%   输出: a    1xK 频率码字向量
%
%   式 3-1: M 为偶数时 a_m ∈ {±1/2, ±3/2, ..., ±(M-1)/2}
%           M 为奇数时 a_m ∈ {0, ±1, ±2, ..., ±(M-1)/2}
%   这里 K=10 (偶数), 码字 = {±0.5, ±1.5, ±2.5, ±3.5, ±4.5}
%   经随机排列后作为子脉冲频率编码序列。

if mod(K, 2) == 0
    vals = (1:2:K-1) / 2;          % 0.5, 1.5, ..., (K-1)/2
    a = [vals, -vals];             % 正负成对, 共 K 个
else
    vals = 0:(K-1)/2;
    a = [vals(1), vals(2:end), -vals(2:end)];
end

rng(seed);
a = a(randperm(K));

end
