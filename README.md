# MATLAB

复现代码仓库。

## ch3 - 脉内频率编码雷达

《捷变雷达抗干扰与信号处理技术》第 3 章 MATLAB 复现: 脉内频率编码信号数学建模与时域抗间歇采样转发干扰 (ISRJ-DF / ISRJ-RF)。

- 运行: `cd ch3` 后执行 `run_ch3` (100 次蒙特卡罗约 8 分钟)
- 详见 ch3/README.md

## STAP - 空时二维自适应处理

相控阵雷达第 23 篇《空时二维自适应处理（STAP）》完整 MATLAB 仿真与 RTL 验证: 4 子阵回波 → 脉压 → 多普勒 FFT → SMI 自适应权 → 空时滤波 → 定点化，解决 MTI 对慢速目标结构性失效问题（目标与杂波多普勒重叠、空间分离时靠空间零陷抑制旁瓣杂波）。

- 黄金仿真: `cd STAP/matlab` 后执行 `stap_ref`（重新生成验证数据）
- 数据自检: `cd STAP` 后执行 `python tools/stap_rtl_compare.py`
- RTL 验证: `cd STAP/rtl` 后执行 `bash run_sim.sh`（需 Vivado xsim）
- 验证结论: 杂波抑制 64.0 dB、目标/杂波比 34.7 dB、RTL 与黄金逐点 ±1 LSB 内 100%
- 详见 STAP/README.md

## 许可 License

本仓库代码采用 MIT 许可证，详见 [LICENSE](LICENSE) 文件。
