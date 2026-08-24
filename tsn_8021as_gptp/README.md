# TSN 802.1AS gPTP 时间同步 RTL 工程

本项目是**真正可用的帧驱动 gPTP（IEEE 802.1AS）时间同步原型**，基于国防科大 OpenTSN 的 RX_PROC 思路重写，覆盖从 MAC 字节流到伺服校正的完整链路。不再是“时间戳由测试台注入”的演示，而是由真实 PTP 报文驱动闭环。

## 1. 工程定位

- **真实可用**：以 GMII 风格 8-bit MAC 字节流（`i_rx_data/i_rx_vld/i_rx_sop/i_rx_eop`）为输入，解析真实 PTP-over-Ethernet 帧（EtherType `0x88F7`），提取字段并驱动伺服校正。
- **纯 FPGA**：本工程是普通 FPGA 功能模型（无 GPU/显控/仿真底座层），按 Verilog 编码铁律实现。
- **原型级**：简化 MAC 接口、时间戳在 HTSU 打标、保留 PHC/BMCA/Servo/TC 完整算法骨架，可作为后续对接真实 MAC IP（如 10G BASE-R）的底座。

## 2. 帧驱动闭环数据流

```
MAC RX 字节流 (i_rx_clk 异步域)
   │ (DA6 + SA6 + ET0x88F7 + PTP header)
   ▼
gptp_rx_fifo        ← 异步 FIFO 跨时钟域 (MAC 接收时钟 -> 系统时钟)
   ▼ (系统时钟域字节流)
gptp_frame_parser    ← 从字节流提取 msgType/seqId/correctionField/originTimestamp
   │  o_sync_vld / o_follow_up_vld / o_cf_ns / o_origin_ts_ns
   ▼
gptp_top (per-port)
   │  ├─ HTSU   : 收/发时间戳 t2/t3 + 驻留时间
   │  ├─ TC     : 透明钟 one-step correctionField 改写
   │  └─ Pdelay : P2P 链路延迟测量
   ▼
gptp_servo          ← 用 t1(origin) / t2(local) / cf 计算相位误差, 输出 adjtime/adjfine
   │
   ▼ (经仲裁: 仅 owner 写)
gptp_phc            ← 共享 PHC: 仅 owner(GM) 端口 servo 可写, 其余屏蔽
   │
   ▼
gptp_tx_gen         ← owner(GM) 端口主动生成 Sync + Follow_Up 出帧 (真实 TX 转发)
   │  o_tx_data/vld/sop/eop
   ▼
MAC TX 字节流 (owner 主动发; 非 owner 由 glue 透传上游 Sync)
```
o_gm_time_ns / o_gm_time_frac   ← 全网统一时间基准
```

## 3. PTP 报文偏移布局（DA 起算）

| 字段 | 偏移 | 字节 | 说明 |
|------|------|------|------|
| DA | 0..5 | 6 | 目的 MAC |
| SA | 6..11 | 6 | 源 MAC |
| EtherType | 12..13 | 2 | `0x88F7` |
| msgType | 14 | 1 | PTP 头 byte0 低 4 位 |
| correctionField | 22..29 | 8 | 大端, 单位 ns<<CF_FRAC_W |
| sequenceId |  40..41 | 2 | 大端 |
| originTimestamp.ns | 48..51 | 4 | 仅 Follow_Up 携带, 大端 |

> 注：`gptp_frame_parser` 内部 `r_byte_cnt` 在 SOP 当拍清零不计入，故采样偏移整体 −1（OFF_ET=11 / OFF_MSG=13 / OFF_SEQ=39 / OFF_CF_LO=21 / OFF_ORIG_LO=47）。

## 4. 模块清单（`src/um/`）

| 文件 | 职责 |
|------|------|
| gptp_defines.v | 消息类型、位宽等全局参数 |
| gptp_phc.v | 相位累积时钟 (PHC) |
| gptp_htsu.v | 时间戳单元 (t2/t3 打标 + 驻留时间) |
| gptp_tc.v | 透明钟 (one-step CF 改写) |
| gptp_pdelay.v | P2P 链路延迟测量状态机 |
| gptp_mac_glue.v | MAC 帧识别 / msgType / CF 改写 |
| gptp_frame_parser.v | 字节流 → PTP 字段解析 |
| gptp_rx_fifo.v | **新增** 异步 FIFO 跨时钟域 (MAC RX → 系统时钟) |
| gptp_tx_gen.v | **新增** owner 端口 Sync/Follow_Up/Announce 出帧生成 |
| gptp_bmca.v | 最佳主时钟选举 |
| gptp_servo.v | PI 伺服环 (adjtime/adjfine) |
| gptp_top.v | 单端口核心集成 |
| gptp_switch.v | 多端口交换机 (共享 PHC + 仲裁 + BMCA + CDC + TX 转发) |
| gptp_mac_adapt.v | **新增** MAC IP 适配层 (GMII 透传 / XGMII / AXI-S 占位) |

## 5. 验证状态（12/12 PASS）

运行 `bash sim/run_sim.sh` 完成分层回归：

| 层级 | 测试台 | 结论 |
|------|--------|------|
| 基础 | tb_gptp_phc | PHC 计数/调频/调相/初始化 |
| 基础 | tb_gptp_htsu | t2/t3 打标 + 驻留时间 (residence 实时输出, 非 event 帧不锁 t2) |
| 基础 | tb_gptp_tc | one-step correctionField 改写 |
| 基础 | tb_gptp_pdelay | P2P 双向延迟测量 |
| 基础 | tb_gptp_mac_glue | PTP 帧识别 / msgType / CF 改写 (Sync/Pdelay_Req/Announce 非 event, FU 计入 event) |
| 基础 | tb_gptp_frame_parser | SYNC/FU/PDELAY_REQ/ANNOUNCE 字段提取 + 非 PTP 抑制 |
| 控制面 | tb_gptp_bmca | 最佳主时钟选举 |
| 执行面 | tb_gptp_servo | PI 伺服环 |
| 集成 | tb_gptp_top | 单端口端到端联动 (residence=40ns, cf_out=2621440) |
| 系统 | tb_gptp_switch | 多端口 / 共享 PHC / 仲裁 / **真实 TX 转发** / **FIFO CDC** |
| 系统 | tb_gptp_cascade | **两级交换机级联**: GM→线缆→Slave, TC 链式累积 CF, BMCA 收敛为 Slave |
| 适配 | tb_gptp_mac_adapt | MAC 适配层 GMII 透传端口连通, XGMII/AXI-S 占位就绪 |

> cascade 验证项：`B 透传 FU 的 cf=e008000000`（非零，透明钟 residence 已叠加 → 链式累积正确）；`B 端口1 BMCA 收敛为 Slave (role=1, is_gm=0)`，Announce 链路打通。

## 6. 已实现功能闭环

1. **帧驱动解析**：`gptp_frame_parser` 从 GMII 字节流提取 PTP 字段（origin 拼装修正到低 32 位）。
2. **跨时钟域 FIFO**：`gptp_rx_fifo` 异步 FIFO（格雷码指针判空满），每端口 MAC RX 经独立 `i_rx_clk` 跨到系统域，写入深度 64，支持异步 MAC（写时钟必须 wire 直连 clk，不可经 reg 延迟一拍）。
3. **真实 TX 转发**：`gptp_tx_gen` 由 owner(GM) 端口主动周期生成 Sync + Follow_Up + Announce 出帧（originTimestamp=t1 取自 PHC）；非 owner 端口经 `gptp_mac_glue` 透传上游 Sync。收包到发包完全自洽。
4. **servo 仲裁**：仅 owner 端口 servo 经 `w_phc_adjtime_wr = w_adjtime_wr[r_phc_owner]` 写共享 PHC，非 owner 屏蔽。
5. **级联端到端同步**：两级交换机（GM A → 线缆 → Slave B）级联验证。B 的透明钟把本机 residence 叠到 correctionField 并转发，实现 CF 跨级链式累积；B 通过 A 的 Announce 收敛为 Slave（role=1, is_gm=0）。
6. **Announce 周期发送 + BMCA 收敛**：`gptp_tx_gen` 在 Sync→FU 周期后补充 Announce 相位（msgType=11，携带 priority1/clock_id/priority2/steps_removed 优先级向量）；`gptp_bmca` 基于 Announce 向量选举 Master/Slave/Passive，输出 `o_is_gm`。
7. **MAC IP 适配层**：`gptp_mac_adapt` 提供 GMII 字节流双向透传（直接 assign），并预留 XGMII（72-bit）/ AXI-S（TVALID/TREADY/TDATA/TLAST）占位接口（当前恒 0），参数 `MAC_IF`（`"GMII"`/`"XGMII"`/`"AXIS"`）+ `NPORTS`，便于对接 10G BASE-R 等真实 MAC IP。

## 7. 已知待办 / 后续

- 真实 MAC IP（如 10G BASE-R PCS/PMA）对接时，将 `MAC_IF` 切到 `"XGMII"`/`"AXIS"` 并实现对应占位接口；异步 FIFO 的 `i_rx_clk` 应接真实 MAC 接收时钟（当前仿真同频）。
- two-step TC 回读原 CF 路径（`TC_MODE=1`）仅在 `gptp_tc` 内预留，未建独立 testbench；如需可补 `tb_gptp_tc` 的 two-step 分支。
- 多跳（>2 级）级联与全网 BMCA 收敛的规模化验证可作为后续压力项。

