function run_ch3(quick)
% run_ch3  第 3 章「脉内频率编码雷达」MATLAB 复现一键入口
%   3.1 节: 脉内频率编码信号数学建模 (信号波形 + 模糊函数) -> 图 3.1, 3.2
%   3.2 节: 时域抗间歇采样转发干扰技术 (Otsu 判决与抑制)
%           实验一 (ISRJ-DF) -> 图 3.3 ~ 3.7
%           实验二 (ISRJ-RF) -> 图 3.8 ~ 3.12
%
% 运行:  run_ch3           完整 100 次蒙特卡罗 (书参数, 需数分钟)
%        run_ch3(true)     快速验证 (10 次 MC, 秒级出图)
%
% 输出:  figs/ch3_fig3_*.png (与书图号一一对应)

if nargin < 1
    quick = false;
end
if quick
    n_mc = 10;
else
    n_mc = 100;
end

fprintf('========== 3.1 脉内频率编码信号数学建模 ==========\n');
ch3_1_modeling();

fprintf('========== 3.2 仿真实验一: ISRJ-DF ==========\n');
ch3_2_exp1_df(n_mc);

fprintf('========== 3.2 仿真实验二: ISRJ-RF ==========\n');
ch3_2_exp2_rf(n_mc);

fprintf('========== 全部完成, 图输出至 figs/ 目录 ==========\n');

end
