function v = generate_steering(Na, Np, nu_s, nu)
%generate_steering 生成空间-时间导向矢量 v = s(nu) \otimes a(nu_s)
%   Na : 阵元数
%   Np : 脉冲数
%   nu_s : 归一化空间频率
%   nu   : 归一化多普勒频率
%   v    : N x 1 复向量, N = Na*Np

s = exp(1j * 2 * pi * nu * (0:Np-1).') / sqrt(Np);   % 时间导向
a = exp(1j * 2 * pi * nu_s * (0:Na-1).') / sqrt(Na); % 空间导向
v = kron(s, a);
end
