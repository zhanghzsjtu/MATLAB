function ch3_2_exp2_rf(n_mc)
% ch3_2_exp2_rf  3.2.4 节 仿真实验二: 间歇采样重复转发干扰 (ISRJ-RF)
%   干扰参数: 采样宽度 T_j = 4 us, 采样周期 T_s = 12 us,
%   干扰机对采样信号调制后重复转发 2 次 (G=2), 其余条件与实验一相同
%   输出图: 图 3.8 ~ 3.12 (figs/ch3_fig3_*.png)
%
% 运行:  ch3_2_exp2_rf          (100 次蒙特卡罗, 书参数)
%        ch3_2_exp2_rf(20)      (快速验证)

if nargin < 1
    n_mc = 100;
end

ch3_2_common(2, 4e-6, 12e-6, 'RF', 'ch3_fig3_', n_mc);

end
