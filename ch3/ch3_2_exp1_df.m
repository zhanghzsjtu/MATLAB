function ch3_2_exp1_df(n_mc)
% ch3_2_exp1_df  3.2.4 节 仿真实验一: 间歇采样直接转发干扰 (ISRJ-DF)
%   干扰参数: 采样宽度 T_j = 4 us, 采样周期 T_s = 8 us
%   -> 奇数序号子脉冲被干扰, 偶数序号子脉冲未被干扰
%   输出图: 图 3.3 ~ 3.7 (figs/ch3_fig3_*.png)
%
% 运行:  ch3_2_exp1_df          (100 次蒙特卡罗, 书参数)
%        ch3_2_exp1_df(20)      (快速验证)

if nargin < 1
    n_mc = 100;
end

ch3_2_common(1, 4e-6, 8e-6, 'DF', 'ch3_fig3_', n_mc);

end
