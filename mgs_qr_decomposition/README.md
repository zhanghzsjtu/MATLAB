# MGS-QR 分解：原子支撑集 QR 分解与增量更新（MATLAB 与 Verilog 实现）

基于修正 Gram-Schmidt（MGS）的 QR 分解及其在匹配追踪类算法（OMP）支撑集维护中的应用。包含 MATLAB 参考实现、增量更新函数、完整测试，以及 Q1.15 定点的 Verilog 状态机实现。iverilog 12.0 与 Vivado 2022.1 xsim 双工具链验证，Q（32 项）与 R（10 项）全部逐位一致（ALL MATCH PASS）。

## 目录结构

```
mgs_qr_decomposition/
├── gs_qr.m              MGS QR 分解函数 [Q,R] = gs_qr(A)
├── gs_qr_update.m       增量 QR 更新 [Q,R] = gs_qr_update(Q_old,R_old,a_new)
├── test_gs_qr.m         分解正确性/正交性/增量一致性/QR 最小二乘测试
├── gen_qr_figs.m        误差随支撑集大小变化、MGS 计算过程示意图
├── gen_rtl_vectors.m    生成 RTL 测试向量与定点参考（与 RTL 逐位对齐）
├── check_mgs.m          参考模型中间值核对脚本
├── CSDN_GramSchmidt_QR_博客.md   配套博客全文
├── figs/                图 1/图 2/图 3（Vivado 波形）
└── rtl/
    ├── qr_decompose_mgs.v   三段式状态机 MGS-QR（W=16, M=8, K=4 参数化）
    ├── tb_qr_decompose_mgs.v  testbench，全量打印 Q/R 与 golden 对照
    └── rtl_vec/              测试向量（a_mem/q_golden/r_golden.hex）
```

## 运行方法

### MATLAB（R2025b 实测）

```matlab
run test_gs_qr.m        % 主测试
run gen_qr_figs.m       % 生成 figs/ 下两张图
run gen_rtl_vectors.m   % 生成 rtl/rtl_vec/ 下 hex 与参考值
```

### Verilog 仿真（iverilog）

```bash
cd rtl
iverilog -g2012 -o qr_sim.vvp qr_decompose_mgs.v tb_qr_decompose_mgs.v
vvp qr_sim.vvp
```

### Vivado xsim

1. 新建工程并添加 rtl/ 下两个 .v 文件，仿真顶层选 tb_qr_decompose_mgs；
2. 把 rtl_vec/ 下三个 hex 复制到 xsim 工作目录（`.../behav/xsim/rtl_vec/`），
   `$readmemh` 相对路径基于该目录解析；
3. `run all`，日志输出 Q/R 全量条目与 ALL MATCH 结论。

## 定点设计说明

- 数据格式 Q1.15 有符号（W=16），输入原子要求列单位化（量化后列范数不超过 32767）；
- 投影系数 $r_{ij}=\sum_t q_i(t)v(t)$ 取 36 位乘累加器的高位段；
- 范数开方为 32 位输入逐位恢复法 16 拍；归一化除法为 30 拍 MSB-first 恢复除法；
- MATLAB 参考模型的位宽回绕按位模式重解释，避免 int16 饱和转换，与 RTL 逐位一致。

## 状态机

IDLE -> LOAD -> (PROJ -> SUB)* -> NORM -> SQRT -> DIV -> DONE，8 态独热编码，三段式，跳转条件独立 wire。总拍数 $O(K^2M)$。

## License

仓库根 LICENSE。
