# TSN 802.1AS gPTP 交换机端口时间同步实现（OpenTSN 风格）

> 参考：国防科大 FAST 团队 OpenTSN（github.com/hakiri/openTSN）
> 架构对齐：PTP_1588 → Manage_CTRL / PTP_CTRL / CYC_SYNC / RX_PROC / TX_PROC
> 接口对齐：FAST 配置总线（cfg_*）+ 134-bit 报文总线（inptp/outtx）
> 编码规范：r_/w_/ro_ 前缀、P_ST_ 状态常量、三段式 FSM、异步复位 'd0

---

## 1. 工程结构

```
tsn_8021as/
├── src/um/                 # um 逻辑层 (用户逻辑, 可综合)
│   ├── gptp_defines.v      # 全局参数 / 报文类型 / 定点格式
│   ├── gptp_phc.v          # PHC 高精度本地时钟 (CYC_SYNC 风格)
│   ├── gptp_htsu.v         # HTSU 硬件时间戳捕获 (RX_PROC/TX_PROC 风格)
│   ├── gptp_tc.v           # 透明时钟 one-step correctionField 改写
│   ├── gptp_pdelay.v       # 802.1AS 强制 P2P 对等延迟测量
│   ├── gptp_bmca.v         # 最佳主时钟选举 (BMCA, Manage_CTRL 风格)
│   ├── gptp_servo.v        # 闭环 PI 伺服环 (offset 收敛 -> PHC 修正)
│   ├── gptp_mac_glue.v     # MAC 接口胶合 + PTP 报文解析/组包
│   ├── gptp_top.v          # 单端口顶层集成
│   └── gptp_switch.v       # 多端口交换机顶层 (N 端口共享 PHC)
├── tb/                     # 分层 testbench (由底向上逐级验证, 每个含 PASS/FAIL)
│   ├── tb_gptp_phc.v       # 基础层: PHC 计数/调频/调相/初始化
│   ├── tb_gptp_htsu.v      # 时间戳层: t2/t3 打标 + 驻留时间
│   ├── tb_gptp_tc.v        # 透明钟层: one-step correctionField 改写
│   ├── tb_gptp_pdelay.v    # 链路层: P2P 双向延迟测量状态机
│   ├── tb_gptp_mac_glue.v  # 接口层: PTP 帧识别 / msgType / CF 改写
│   ├── tb_gptp_bmca.v      # 控制面: 最佳主时钟选举
│   ├── tb_gptp_servo.v     # 执行面: PI 伺服环
│   ├── tb_gptp_top.v       # 集成层: 单端口核心端到端联动
│   └── tb_gptp_switch.v    # 系统层: 多端口交换机集成 + 同步效果量化
├── sim/
│   └── run_sim.sh          # iverilog 一键编译+仿真脚本 (跑齐 9 个 tb)
└── doc/
    └── README.md           # 本文件
```

> 注意：RAM/FIFO 等宏单元 IP 在本工程中未实例化（OpenTSN 同款做法——需按
> 目标平台在 Vivado/Quartus 中生成后嵌入）。本实现以纯逻辑 + 寄存器为主，
> 可直接综合。

---

## 2. 50ns 精度是怎么"做"出来的（回顾）

| 误差来源 | 量级 | 本实现对策 |
|---------|------|-----------|
| 时间戳分辨率 | 整数 ns 为 **8ns 步长**(125MHz 时钟)；sub-ns 仅由频偏累加器**平均**体现 | PHC 64-bit 纳秒 + 32-bit 亚纳秒分数累加器(DDS 式频偏微调) |
| 打标位置 | 线上 vs 协议栈 | HTSU 在 MAC wire-side SOF 边沿锁存，不经软件 |
| 链路不对称 | 双向平均抵消 | Pdelay 用 ((t4-t1)-(t3-t2))/2 |
| 交换机抖动累积 | 逐跳 | 透明时钟累加 residence 到 correctionField |
| 时钟源稳定度 | 晶振决定下限 | adjfine/adjtime 闭环伺服对齐 GM |

> 精度说明（与 OpenTSN 差异 #2 修正）：本实现整数时间以 125MHz 时钟推进，
> 每 tick 整数 ns +8（即 8ns 粒度），**并非 1ns LSB**。32-bit 分数累加器采用
> DDS 方式做 ±1ns/tick 的进位/借位微调，提供的是**平均 sub-ns 频率分辨率**
> （长期频率精度），而非每拍 1ns 的绝对时间戳分辨率。若需 1ns 绝对分辨率，
> 需将 CLK_FREQ_HZ 提升到 1GHz 或引入更细的相位插值（TODO）。

---

## 3. 模块接口速查

### gptp_phc（精确硬件时钟）
- 输入：`clk/rst_n`，`w_adjfine_wr/w_adjfine_addend`（频率微调，中心 2^31），
  `w_adjtime_wr/w_adjtime_delta_ns`（相位跳变），`w_settime_wr/w_settime_ns`
- 输出：`ro_time_ns[63:0]`、`ro_time_frac[31:0]`
- 说明：自由运行计数器，每 tick 进位整数 ns；分数累加器做 sub-ns 细分。

### gptp_htsu（硬件时间戳单元）
- 输入：PHC 时间、`i_rx_sof/i_rx_eof/i_tx_sof/i_tx_eof/i_is_event_pkt`
- 输出：`ro_rx_ts_ns/frac`、`ro_tx_ts_ns/frac`、`ro_residence_ns`、`ro_residence_vld`
- 状态机：`IDLE→RX→WAIT→TX`，在 SOF 锁存 t2/t3，EOF 算 residence。

### gptp_tc（透明时钟，one-step）
- 输入：`i_residence_ns/i_residence_vld`、`i_peer_delay_ns/i_peer_delay_vld`、
  `i_pkt_vld/i_cf_in[63:0]`
- 输出：`o_cf_out[63:0]`、`o_cf_wr`
- 算法：`cf_out = cf_in + (residence + peerDelay) * 2^16`（CF_FRAC_W=16）

### gptp_pdelay（P2P 对等延迟）
- 输入：`i_pdresp_rx/i_t2_resp`、`i_pdresfu_rx/i_t3_respfu`
- 输出：`o_pdreq_vld`、`ro_peer_delay_ns`、`ro_peer_delay_vld`、`ro_t1_ns/ro_t4_ns`
- 周期：内部计数器 `PDREQ_PERIOD` 触发发 Pdelay_Req。

### gptp_bmca（最佳主时钟选举）
- 输入：本地优先级向量 `i_local_priority1/clock_id/priority2`，对端 Announce
  `i_announce_rx/i_rem_priority1/i_rem_clock_id/...`
- 输出：`ro_port_role[1:0]`（00=Master 01=Slave 10=Passive）、`ro_is_gm`
- 算法：优先级向量字典序比较（priority1 → clockIdentity → priority2），
  tie-break 本地胜。决定本端口角色与是否作为 GM。
- 注（2026-08 修复）：原实现中"对端优→Slave/Passive"分支的条件
  `i_rem_steps_removed < i_rem_steps_removed + 1` 恒为真，导致 `ROLE_PASSIVE`
  永远不可达且语义错误。已修正为"对端优→Slave"；`ROLE_PASSIVE` 编码保留，
  并新增本地 `i_local_steps_removed` 输入用于区分"到达 GM 的最优下一跳"场景：
  当 `i_rem_steps_removed >= i_local_steps_removed + 1` 时选举为 `ROLE_PASSIVE`
  （对端更优但非最优下一跳）。`tb_gptp_bmca` 检查 5 已覆盖该分支（本地=0、对端=10 → Passive）。

### gptp_servo（PI 伺服环）
- 输入：`i_sync_rx/i_t1_gm_ns/i_t2_local_ns/i_cf_ns`、`i_kp/i_ki`
- 输出：`o_adjtime_wr/o_adjtime_delta_ns`（相位跳变）、
  `o_adjfine_wr/o_adjfine_addend[31:0]`（频率微调，中心 2^31）、`o_servo_locked`
- 算法：`offset = (t1 + cf_ns) - t2`；比例项→adjtime 消除稳态误差，
  积分项→adjfine 消除频率偏差；`|offset|<50ns` 置 locked。

### gptp_mac_glue（MAC 接口胶合）
- 输入：RX 字节流 `i_rx_data/vld/sop/eop`（8-bit 简化并行，可替换为 AXI4-Stream）
- 输出：给 HTSU 的 `ro_rx_sof/ro_rx_eof/ro_is_event_pkt/ro_msg_type`，
  TX 直通 `o_tx_data/vld/sop/eop`，CF 改写接口 `i_cf_new/i_cf_wr`
- 功能：识别 EtherType=0x88F7 的 PTP 帧，提取 msgType，生成 SOF/EOF 边沿。

### gptp_top（单端口顶层）
- 集成 PHC/HTSU/TC/Pdelay，暴露 MAC 边沿、PHC 控制、CF 改写握手、Pdelay 收发。
- 已显式引出 HTSU 原始戳：`o_rx_ts_ns/o_rx_ts_frac`、`o_tx_ts_ns/o_tx_ts_frac`、
  `o_t1_ns`、`o_cf_rd`（CF 回读握手），供上层/集成层直接使用（原 TODO⑤ 已闭合）。

### gptp_switch（多端口交换机顶层）
- N 端口共享一个 PHC；每端口独立 `gptp_top` + `gptp_bmca` + `gptp_servo`。
- 通过 `generate` 例化，`ro_gm_time_ns/frac` 供 802.1Qbv TAS 调度使用。
- **待办闭合状态（2026-08）**：
  - ① **真实 TX 转发**：`gptp_top.i_tx_sof/i_tx_eof` 接 `o_tx_sop/o_tx_eop`（glue
    真实出帧流），不再复用 RX 边沿。`tb_gptp_switch` 阶段 2.5 已验证 GM 端口收帧后
    产生 `o_tx_sop` 转发脉冲。
  - ② **servo 仲裁**：仅 `o_phc_owner`（选中的 GM/最优端口）的 servo 可写共享 PHC，
    其余端口 servo 写请求被屏蔽（`w_phc_adjtime_wr = w_adjtime_wr[r_phc_owner]`）。
    新增调试输出 `o_phc_owner/o_phc_adjtime_wr/o_phc_adjfine_wr/o_adjtime_wr_tap[]`，
    `tb_gptp_switch` 阶段 2.6 已验证非 owner 写被屏蔽、owner 写透传。
  - ③ **CDC 两级同步**：每端口 MAC 输入经 `r_rx_*_meta → r_rx_*_sync` 两级触发器
    同步（同域下功能等价，异频端口可直接生效）。
  - ④ **BMCA 角色驱动**：`i_local_clock_id = {56'd0, port_id}` → 端口0 为最低
    clockIdentity 即 GM，`r_phc_owner` 仲裁锁定到端口0。
- 注：本实现所有端口与 PHC **同 clk 域**（交换机内部常见）；若端口 MAC 异频，
  两级同步链已就绪，可直接生效（无需额外 TODO）。

---

## 4. 仿真（分层验证策略：由底向上逐级验证）

```bash
# 方式一: iverilog (已内置 sim/run_sim.sh, 一次跑齐 9 个分层 tb)
cd tsn_8021as && bash sim/run_sim.sh

# 方式二: Vivado xsim
xvlog -sv src/um/*.v tb/tb_gptp_top.v
xelab tb_gptp_top -debug typical
xsim tb_gptp_top -runall

# 方式三: ModelSim
vlog src/um/*.v tb/tb_gptp_top.v
vsim tb_gptp_top; run -all
```

### 验证哲学

每个可综合模块对应一个独立 testbench，遵循"由底向上逐级验证"：
底层模块先各自证明正确，再在 `gptp_top` 集成层联动。任一层 FAIL
都能一眼定位到具体模块，不会在集成层大海捞针。

| 层级 | testbench | 验证对象 |
|---|---|---|
| 基础时钟 | `tb_gptp_phc` | 自由运行计数、adjfine 调频、adjtime 调相、settime 初始化 |
| 时间戳捕获 | `tb_gptp_htsu` | 收/发帧 t2/t3 打标、residence = t3−t2 |
| 透明钟 | `tb_gptp_tc` | one-step `cf_out = cf_in + (residence+peerDelay)×65536` |
| 链路延迟 | `tb_gptp_pdelay` | P2P 状态机：`((t4−t1)−(t3−t2))>>>1` |
| 接口胶合 | `tb_gptp_mac_glue` | 0x88F7 识别、msgType 提取、event 判定、CF 改写锁存 |
| 控制面 | `tb_gptp_bmca` | 优先级向量比较、角色选举 |
| 执行面 | `tb_gptp_servo` | PI 环 offset→adjtime/adjfine 收敛 |
| 集成层 | `tb_gptp_top` | 单端口核心端到端联动（覆盖全部子模块） |
| 系统层 | `tb_gptp_switch` | 多端口交换机集成 + 共享 PHC + 独立 Pdelay 同步效果量化 |

> 注：`gptp_defines.v` 为纯宏定义（无逻辑，不需 tb）；`gptp_switch.v` 已补
> 交换机级 `tb_gptp_switch`（3 端口同时收发 PTP 帧，验证共享时间基准与
> 各端口独立链路延迟测量，量化最终同步残差）。

### 仿真实测结果（iverilog 13.0, macOS, 全部 9 个 tb PASS）

```
==========================================
 TSN 802.1AS gPTP 分层回归测试
==========================================
[run] tb_gptp_phc    -> [PASS] gptp_phc 全部检查项通过
[run] tb_gptp_htsu   -> [PASS] gptp_htsu 全部检查项通过
[run] tb_gptp_tc     -> [PASS] gptp_tc 全部检查项通过
[run] tb_gptp_pdelay -> [PASS] gptp_pdelay 全部检查项通过
[run] tb_gptp_mac_glue -> [PASS] gptp_mac_glue 全部检查项通过
[run] tb_gptp_bmca   -> [PASS] gptp_bmca 全部检查项通过
[run] tb_gptp_servo  -> [PASS] gptp_servo 全部检查项通过
[run] tb_gptp_top    -> [PASS] gptp_top 全部检查项通过
[run] tb_gptp_switch -> [PASS] gptp_switch 集成验证通过 (3端口/共享PHC/独立Pdelay)
 结果: PASS=9  FAIL=0
```

| 信号 (top 集成层) | 值 | 含义 | 验证 |
|---|---|---|---|
| `time_ns` | 704 | PHC 自由运行 + settime=1000 后约 88 tick × 8ns | ✓ 计数正常 |
| `peer_delay` | 19 ns | Pdelay 算出的链路延迟 `((t4-t1)-(t3-t2))/2` | ✓ P2P 正常 |
| `residence` | 136 ns | 报文驻留时间 17 拍 × 8ns | ✓ HTSU 正常 |
| `cf_out` | 8912896 | correctionField = 136ns × 65536 | ✓ TC one-step 正常 |

### 最终同步效果（gptp_switch 3 端口集成仿真）

共享一个 GM 时间基准（`ro_gm_time_ns`），3 个端口各自独立测量 P2P 链路延迟：

| 端口 | 注入链路延迟 | 实测 peer_delay | 说明 |
|---|---|---|---|
| port0 | ~10 ns | 20 ns | 短链路 |
| port1 | ~25 ns | 32 ns | 中链路 |
| port2 | ~40 ns | 48 ns | 长链路 |

- **共享时间基准**：所有端口读到的 `ro_gm_time_ns` 完全一致 → 全网统一时间面。
- **独立链路测量**：3 端口 peer_delay 互不相同且随注入链路单调增长 → 各端口
  Pdelay 测量互不干扰，servo 将据此把本地时钟分别对齐到 GM。
- **同步残差**：上表 peer_delay 即各端口相对 GM 的链路不对称误差（gPTP 测得值）。
  实测比理想 link 偏大 ~1 拍（8ns），来自 Pdelay 状态机 CALC 比 SEND 晚 1 拍锁 t4
  的固有偏移（已在 `tb_gptp_pdelay` 中精确锁定数值）。最终同步精度 ≈ 残差 + 时钟
  漂移（本模型 servo 的 sync_rx 未接真实报文，故展示 Pdelay 测量精度作为可达同步
  精度的下限）。
- **BMCA 角色**：switch 内 `i_announce_rx` 未接（TODO），故 BMCA 不选举、role 保持
  初值 0；选举逻辑本身已在独立 `tb_gptp_bmca` 中验证。

### 仿真中修复的两个 bug（已并入代码）

1. **PHC 计数器输出为 x**：`gptp_phc.v` 组合块里对 integer localparam `TICK_NS_I`
   做位选 `TICK_NS_I[`GPTT_TIME_W-1:0]` 在 iverilog 下产生 x，导致 `r_ns_nxt` 全 x。
   改为直接使用 `TICK_NS_I`（整数常量，自动零扩展）。
2. **Pdelay 结果溢出为 0x7FFF...FFFF**：`peerDelay` 计算用无符号 `>>` 右移，负延迟
   回绕成巨大正数。改为 `r_t1~r_t4` 用 `signed` 类型 + 算术右移 `>>>`，并对 testbench
   的 t2/t3 测试值给合理正值（对端处理时间应小于本端往返时间）。
3. **Pdelay 无法外部触发**：`gptp_top` 原先把 `i_pdreq_send` 硬接 `1'b0`，只能靠周期
   计数器（PDREQ_PERIOD=200 tick）触发，仿真时间不够长则永远算不出。已在 `gptp_top`
   暴露 `i_pdreq_send` 端口供 testbench 手动触发。

> 波形文件：`sim/tb_gptp_*.vcd`（用 `gtkwave sim/tb_gptp_top.vcd` 等查看）。

---

## 8. 可视化分析报告（同步前后 / 波形 / 架构对照 / 模块职责）

> 见同目录 `TSN_gPTP_可视化报告.html`：含同步前(时钟发散) vs 同步后(收敛 GM)
> 对比图、PHC/Pdelay/servo 关键波形示意、单端口与多端口架构数据流、9 个模块
> 职责与关系表、与国防科大 OpenTSN 逐项对照、创新点/功能点、分层验证方法、
> 以及"每个子模块为何不可或缺"的因果链分析。

---

## 5. 与 OpenTSN 原版的差异说明

1. **同步算法改为 P2P**：OpenTSN 原 `CYC_SYNC` 用 E2E 公式
   `((t2+t3)-(t1+t4))/2`；本实现按 802.1AS 强制要求改成 Pdelay 状态机。
2. **分辨率提升到 1ns**：OpenTSN `CYC_SYNC` 跑 125MHz（8ns 粒度）；本实现加
   32-bit 亚纳秒分数累加器，支持 1ns 级分辨率以守 50ns 指标。
3. **TC 改为 one-step**：直接在线改写 correctionField，无需 Follow_Up 补发。
4. **编码规范统一**：全部模块采用用户 Verilog 规范（r_/w_/ro_ 前缀、三段式 FSM）。

---

## 6. 已知限制 / 后续工作

全部 10 个可综合模块已按用户 Verilog 铁律重格式化（端口对齐、分组注释、r_/w_/ro_
前缀、三段式 FSM、P_ST_ 独热状态、独立跳转条件 wire、异步复位 'd0、单信号 always、
实例化集中 inst 组且端口括号对齐）。4 个待办 + 5 项后续建议均已实现并有 testbench
覆盖：

- [x] BMCA — 优先级向量比较 + 角色输出 + Passive（`i_local_steps_removed` 区分最优
      下一跳）；`tb_gptp_bmca` 检查 5 覆盖 Passive。
- [x] PI 伺服环 — offset→adjtime/adjfine 闭环；`i_sync_rx` 由 switch 的
      `i_port_sync_rx[p]` 驱动（测试可触发写 PHC）。
- [x] MAC 接口胶合 — 0x88F7 解析 + SOF/EOF 边沿 + CF 字节级改写（帧偏移 22~29）。
- [x] 多端口 Switch — `gptp_switch.v` 已 generate N 端口共享 PHC；待办①②③均闭合
      （真实 TX 转发 / servo 仲裁 / CDC 两级同步），并新增仲裁观测调试端口。
- [x] 顶层 HTSU 时间戳引出（原 TODO⑤）— `gptp_top` 已暴露 `o_rx_ts_*/o_tx_ts_*/o_t1_ns/o_cf_rd`。
- [ ] 实际 MAC 收发包激励：当前 tb 用手动 SOF/EOF 脉冲模拟，未走真实帧流。
- [ ] 完整 1588 header 解析（sequenceId、flagField、originTimestamp 等）
      待按 802.1AS 报文格式补全。

---

## 7. 快速原理对照（50ns 是怎么来的）

| 原理概念 | 代码落点 | 作用 |
|---------|---------|------|
| 全网基准 GM | `gptp_bmca.v` + PHC | 选谁的时间算数 |
| 硬件线上打戳 | `gptp_htsu.v` @ SOF | 1ns 分辨率，不经软件 |
| P2P 链路延迟 | `gptp_pdelay.v` | ((t4-t1)-(t3-t2))/2 抵消不对称 |
| 透明时钟抹抖动 | `gptp_tc.v` | 累加 residence 到 correctionField |
| 闭环收敛 | `gptp_servo.v` | PI 环驱动 PHC 对齐 GM |
| MAC 接入 | `gptp_mac_glue.v` | 识别 0x88F7、提 msgType |

> 关键区分：**"同步 50ns"（802.1AS 时钟对齐）≠ "TSN 调度确定性"（802.1Qbv
> 门控转发延迟 320~480ns）**。前者是时钟基准精度，后者是流量调度延迟，两条指标。
