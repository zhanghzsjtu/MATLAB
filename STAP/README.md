# STAP 空时二维自适应处理仿真

本仓库是相控阵雷达信号处理系列（近距离相控阵雷达工程实现）中第 23 篇《空时二维自适应处理（STAP）》对应的完整、可独立运行的 MATLAB 仿真与验证包。它把分散在项目各处的 STAP 黄金代码、验证数据与对比工具整合到一个公开、自包含、路径脱敏的目录中，clone 后即可直接运行，不依赖任何 FPGA 工程或本地绝对路径。

## 一、STAP 解决什么问题

运动目标指示（MTI）靠零频陷波滤除静止杂波，但对慢速目标（如 v=1 m/s 的近悬停目标，多普勒频率约 63 Hz）结构性失效：目标多普勒与静止杂波（DC bin）在多普勒域几乎重合，MTI 无法在保留目标的同时抑制杂波。

STAP 的解法是引入空间维自由度。本雷达采用 4 子阵接收，子阵相位中心位于

$x_m = [-3, -1, 1, 3] \cdot d, \quad m = 0,1,2,3$

其中 $d$ 是单元间距（17.4 mm）。来自方位角 $\theta$ 的信号在第 $m$ 个子阵的复增益为

$g_m(\theta) = \exp(j \cdot k \cdot x_m \cdot \sin(\theta)), \quad k = 2\pi / \lambda$

当目标（az=0°，主瓣中心）与强旁瓣杂波（az=+22°~+28°）方位分离大于一个波束宽（约 17.9°）时，两者导向矢量线性无关，STAP 可构造随多普勒 bin 变化的自适应权，使目标方向增益为 1、杂波方向响应置零，从而把旁瓣杂波从目标信号中滤除。

## 二、算法结构

本实现采用**后多普勒 STAP** + **SMI 自适应权**：

1. 4 子阵回波生成（确定性场景：1 慢速目标 + 40 个静止旁瓣散射体）；
2. 每通道时域脉压（LFM 匹配滤波，Hamming 加窗）；
3. 每通道多普勒 FFT（64 点，Hamming 窗）→ 得到 4 通道复数谱 $X_m(d, r)$；
4. 对每个多普勒 bin $d$ 独立求 SMI 权：

   $\hat{R} = \frac{1}{N_{train}} Z Z^H$

   $\hat{R}_{load} = \hat{R} + \epsilon \cdot \frac{\mathrm{tr}(\hat{R})}{N_{CH}} \cdot I, \quad \epsilon = 10^{-2}$

   $w_0(d) = \hat{R}_{load}^{-1} s_{tgt}, \quad w(d) = \frac{w_0(d)}{s_{tgt}^H w_0(d)}$

5. 空时滤波 $Y(d, r) = w(d)^H \cdot z(d, r) = \sum_{m=0}^{3} w_m^*(d) \cdot X_m(d, r)$。

定点口径：输入谱 22 bit 定点 × 权值 16 bit Q15（32768=1.0）→ 乘积 38 bit → 4 项累加 40 bit → 算术右移 15 → 饱和 22 bit 输出（与输入同宽，保证后续 CFAR 接口位宽不膨胀）。

## 三、文件清单

```
STAP/
├── README.md                本说明
├── matlab/
│   └── stap_ref.m           MATLAB 黄金仿真（回波→脉压→FFT→SMI权→空时滤波→定点化→输出）
├── rtl/
│   ├── stap_4ch.v           STAP 空时滤波 RTL（后多普勒，3 级流水定点，XPM SDPRAM 权值）
│   ├── tb_stap_4ch.v        测试台（bin-major 灌入 stap_in.txt，输出 stap_rtl_out.txt）
│   └── run_sim.sh           Vivado xsim 一键仿真 + 逐级对比（路径参数化，不硬编码）
├── data/
│   ├── stap_in.txt          4 通道谱 22bit 定点 hex 激励（64 bin × 192 门，bin-major，每行 8 字段）
│   ├── stap_w_q15.mem       权值 Q15 hex（每 bin 一行 8 字段，供 FPGA $readmemh 加载）
│   ├── stap_w_rom.mem       权值 ROM 镜像（同 stap_w_q15.mem，供 XPM SDPRAM 初始化）
│   ├── stap_gold.txt        黄金定点输出 22bit hex（每行 out_i out_q，顺序同激励）
│   └── stap_rtl_out.txt     RTL 仿真输出（由 run_sim.sh 生成，供逐级对比）
└── tools/
    └── stap_rtl_compare.py  RTL vs 黄金 逐级对比工具（行数/逐点±1LSB/主峰误差/杂波抑制）
```

## 四、运行方法

### 4.1 重新生成黄金数据（需 MATLAB）

```bash
cd matlab
matlab -batch "stap_ref"
```

脚本会重新生成 `../data/` 下的三个文件并打印抑制统计。

### 4.2 验证已给出的黄金数据

`data/` 中已包含一次确定性运行的黄金输出。运行对比工具可自检数据完整性（默认对比 golden 与 golden，返回 PASS）：

```bash
cd STAP
python tools/stap_rtl_compare.py
```

若你有 FPGA 仿真输出的 `stap_rtl_out.txt`，可传入做逐级验证（也可直接运行 4.3 的 RTL 仿真生成）：

```bash
python tools/stap_rtl_compare.py data/stap_rtl_out.txt data/stap_gold.txt
```

判据：行数一致（12288 = 64 bin × 192 门）、逐点绝对误差 ≤ 1 LSB、主峰相对误差 ≤ 1e-2、杂波区输出幅度远小于目标门。

### 4.3 RTL 仿真与逐级验证（需 Vivado xsim）

RTL 实现 `rtl/stap_4ch.v` 为后多普勒 STAP 的定点硬件结构：3 级流水（乘 → 累加 → 截位饱和），权值由 XPM SDPRAM 加载（`data/stap_w_rom.mem`，与黄金同源），输入谱 22 bit × 权值 16 bit Q15 → 输出饱和 22 bit。

运行需 Vivado 仿真工具链。脚本已参数化路径（不硬编码本地目录）：

```bash
cd rtl
# 可选：指定 Vivado 安装位置（默认 /d/Xilinx/Vivado/2022.1）
export VIVADO=/path/to/Vivado/2022.1
# 准备 glbl.v（从 Vivado 安装目录取，放本目录）
cp "$VIVADO/data/verilog/src/glbl.v" ./glbl.v
bash run_sim.sh
```

`run_sim.sh` 会：编译 xpm_memory + stap_4ch + tb_stap_4ch → 链接运行（生成 `data/stap_rtl_out.txt`）→ 自动调用 `stap_rtl_compare.py` 与黄金对比。

预期结果（来自项目实测）：RTL 输出与黄金逐点 ±1 LSB 内 12288/12288 点（100%），主峰相对误差 ≤ 1e-2。

注意：XPM `MEMORY_INIT_FILE` 与 tb 的 `$readmemh` 均使用相对路径 `../data/`，仿真工作目录须为 `rtl/sim_work`（脚本已处理）。若在你自己的工程里集成，按实际目录调整该相对路径即可。

## 五、验证结论（来自项目实测）

在确定性场景（慢速目标 v=1 m/s + 强静止旁瓣杂波）下：

| 指标 | 黄金浮点 | 定点/RTL | 结果 |
|------|----------|----------|------|
| 杂波抑制增益 | 64.0 dB | — | 通过 |
| 目标/杂波比 | 34.7 dB | 33.6 dB | 一致（差 1.1 dB，定点量化所致） |
| 逐点 ±1 LSB | — | 12288/12288（100%） | 通过 |
| 主峰相对误差 | — | 4.29e-5 | ≤1e-2 通过 |

结论：STAP 在多普勒域重叠、空间域分离的场景下，相对 MTI 零频旁路额外提供约 51.9 dB 的目标/杂波比提升（从 −17.2 dB 升到 34.7 dB）。MTI、STAP 与 RAW 零频旁路是检测前三道互补的预处理防线。

## 六、说明

- 本目录路径已脱敏，不依赖任何本地绝对路径，clone 到任意位置均可运行。
- 场景参数确定性（杂波散射体相位用质数序列 `mod(c*7919,1e9)/1e9*2π` 固定），保证 RTL 与黄金对比可重复。
- RTL 实现（`rtl/stap_4ch.v` + `rtl/tb_stap_4ch.v`）已包含在 `rtl/` 目录，配套 `rtl/run_sim.sh` 一键仿真。
- 本 STAP 模块在整条雷达处理链中的位置：多普勒 FFT 之后、CFAR 检测之前，是检测前的一道空时预处理，只做杂波抑制、不改距离-多普勒二维结构。
- 若需把本模块集成进完整 FPGA 工程（含 DDC、脉压、多普勒 FFT、转置等前级），见仓库根 `fpga/` 目录；STAP 的输入格式（4 通道 22 bit 定点复数谱）与前级多普勒 FFT 输出直接对接。

## 七、参考文献与延伸

- 后多普勒 STAP 与全维 STAP 的对比、SMI 权收敛性（$\frac{SINR_{out}}{SINR_{opt}} \approx \frac{N_{train}-p+1}{N_{train}+1}$）、对角加载与自由度等理论细节，见博客系列第 23 篇《空时二维自适应处理（STAP）》。
- MTI 失效边界、RAW 零频旁路与 STAP 的三道防线分工，见同系列第 6 篇（MTI）与第 19 篇（悬停专项）。
