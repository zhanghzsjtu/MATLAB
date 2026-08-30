# 802.1AS gPTP 时间同步 RTL 原型：从 MAC 字节流到伺服校正的帧驱动闭环

> 基于国防科大 OpenTSN 的 RX_PROC / TX_PROC 思路重写，用纯 Verilog 在 FPGA 上实现 802.1AS gPTP 时间同步的完整链路，14 个模块、12 个分层测试台一键回归通过。

## 一、背景

以太网原本是异步网络，没有统一时钟。IEEE 1588 用 PTP 报文在网络里传递时间信息，802.1AS（gPTP）则针对时间敏感网络做了裁剪：强制使用点对点（P2P）链路延迟测量，全网选出一个总时钟源（Grandmaster，GM），其余节点向它对齐。

在 FPGA 上落地 gPTP，真正的难点有三个：

1. 时间戳必须从真实 MAC 字节流的帧边沿打标，而不是测试台喂一个理想值。
2. 报文每过一台交换机，设备内部的驻留时间（residence）要实时累加到 correctionField，否则下游算出的链路延迟是错的。
3. 多端口共用一个本地时钟 PHC，只有被选举为 GM 的端口才能写它，否则全网各写各的、越调越乱。

本工程针对这三点给出了完整的 RTL 实现，并把同步链路做成帧驱动闭环：从收包解析、时间戳打标、伺服校正、PHC 累积，到 GM 端口主动出帧，全程跑在真实报文的字节流上，不是测试台注入时间戳的演示。

## 二、功能点

### 1. 帧驱动报文解析

`gptp_frame_parser` 以 GMII 风格 8 位字节流为输入，识别 EtherType 0x88F7，从 PTP 头提取 msgType、sequenceId、correctionField（偏移 22 到 29）、originTimestamp（Follow_Up 专用），并在帧尾按消息类型产生有效脉冲供伺服与 BMCA 消费。originTimestamp 拼装修正为低 32 位，修复了位域拼错的经典问题。

### 2. 跨时钟域异步 FIFO

`gptp_rx_fifo` 是真正意义上的 CDC：每端口 MAC 接收时钟 `i_rx_clk` 是独立异步域，字节流先入异步 FIFO 跨到系统时钟域再做解析。写读指针各维护二进制和格雷码两套，格雷码两级触发器跨域同步，空满基于跨域格雷码比较，深度 64。这一步决定了工程能否对接真实 MAC IP，而不只是仿真玩具。

### 3. 硬件时间戳单元（HTSU）

`gptp_htsu` 在帧边沿对 event 类报文打标：接收时刻 t2、发送时刻 t3，并算出驻留时间 residence = t3 - t2。非 event 报文不打标。residence 在发帧期间实时输出并保持，出帧后不清零，供透明钟改写 CF 时引用。

### 4. 透明钟（TC）在线改写 correctionField

`gptp_tc` 把本跳驻留时间加上 P2P 链路延迟，累加进报文的 correctionField（64 位定点，1ns 对应 2^16），one-step 直接改写，two-step 模式预留了 CF 回读脉冲。多级交换机链式累积后，下游拿到的延迟值包含每一跳的贡献。

### 5. P2P 链路延迟测量

`gptp_pdelay` 周期发 Pdelay_Req，收 Pdelay_Resp 和 Resp_Follow_Up，用双向四个时间戳求对等延迟，把链路的不对称性平均掉。

### 6. 最佳主时钟选举（BMCA）

`gptp_bmca` 比较本地与对端 Announce 携带的优先级向量（priority1、clockIdentity、priority2、stepsRemoved），按字典序选出本端口角色 Master / Slave / Passive，并输出本端口是否 GM。Announce 由 GM 端口周期发出，闭环了选举过程。

### 7. PI 伺服环与共享 PHC

`gptp_servo` 用 Sync 的 offset = (t1 + cf) - t2 做 PI 闭环，输出相位修正 adjtime 和频率修正 adjfine。`gptp_phc` 是 64 位纳秒自由运行计数器加 32 位亚纳秒分数累加器，支持调频、调相、初始化。多端口下所有 servo 共写一个 PHC，但仲裁逻辑保证只有 owner 端口的写请求透传，其余屏蔽。

### 8. 真实 TX 转发

`gptp_tx_gen` 让 GM（owner）端口由本地 PHC 主动周期构造并发送 Sync、Follow_Up 和 Announce 出帧，Sync 的 originTimestamp 取发送瞬间锁存的 t1。非 owner 端口经 `gptp_mac_glue` 透传上游 Sync。收包到发包完全自洽，不再依赖上游 RX 复用。

### 9. MAC IP 适配层

`gptp_mac_adapt` 在 gPTP 交换机与真实 MAC IP 之间提供适配：GMII 字节流双向直连透传，预留 XGMII（72 位）和 AXI-S（TVALID/TREADY/TDATA/TLAST）接口占位，参数 `MAC_IF` 和 `NPORTS` 可配，为对接 10G BASE-R 等真实 MAC 预留了接口位宽和握手。

### 10. 级联端到端验证

两级交换机 GM 到 Slave 的级联测试台验证了整条链路：Slave 端透传 Follow_Up 的 correctionField 非零，说明透明钟把本机 residence 叠加上去了，CF 跨级链式累积正确；Slave 端口 BMCA 收敛为 Slave（role=1, is_gm=0），Announce 链路打通。

## 三、创新点

### 1. 字节计数统一用组合下一值，兼容直驱与级联双路径

`gptp_mac_glue` 要在帧偏移 12（EtherType）、14（msgType）处判决，但输入可能来自直驱测试台（无 FIFO），也可能来自经 FIFO 的级联路径（读侧延迟一拍）。如果用时序锁存的 `r_byte_cnt`，两条路径偏移差一拍，ET/msgType 识别会错位。实现引入组合下一值 `w_byte_cnt_nxt`，所有判决块统一用它，快一拍补偿 FIFO 读侧延迟，让两种路径都正确。这是整个工程里最隐蔽的一个时序问题，也是直驱测试和真实级联能同时通过的关键。

```
wire [7:0] w_byte_cnt_nxt = i_rx_sop ? 8'd0 : (i_rx_vld ? (r_byte_cnt + 8'd1) : r_byte_cnt);
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst) r_byte_cnt <= 'd0;
    else       r_byte_cnt <= w_byte_cnt_nxt;   // 锁存组合下一值
end
```

### 2. residence 在发帧期间实时计算，不等帧尾

residence 如果等 `tx_eof` 才算，出端口的 correctionField 字节在 `tx_eof` 之前就到了，那时 residence 还是 0，TC 改写就写入了 0。实现让 HTSU 在 P_ST_TX 状态期间用已锁存的 t3 - t2 实时输出并保持，保证 TC 在 CF 域字节到达时 residence 已非零，出帧后保持供上层读取。这是透明钟能链式累积的前提。

### 3. event 标志锁存时机：进 RX 后判，不在进 RX 时判

msgType 在帧中段才解析出来，所以 HTSU 进 RX 状态时还不能判断本帧是不是 event 报文。实现是在 P_ST_RX 状态内、msgType 字节到达时由 `i_is_event_pkt` 锁存 `r_event_latch`，整个帧期间保持，状态机在 WAIT 阶段据此决定是否进 TX。非 event 帧不锁存 t2，避免误打标。

### 4. 出帧生成器的进入拍对齐

GM 端口出帧时，状态机进入 SEND 的首拍 `state_c` 还是旧值（IDLE），按 `state_c==SEND` 输出字节会整体错位一拍。实现用组合启动信号 `w_start` 在进入拍直接输出 byte0 并拉 sop，同时把字节计数预置为 1，下一拍状态稳定后从 byte1 接着发，规避了这 1 拍观察误差。

```
assign w_start = (state_c == P_ST_IDLE) && i_enable && (r_tick >= i_period);
```

### 5. 帧驱动真实闭环，区别于时间戳注入式演示

整条链路由真实 PTP 报文驱动：收包解析字段，伺服用解析出的 t1、t2、cf 算 offset 并写 PHC，GM 端口再由 PHC 主动出帧。时间戳全部来自硬件打标，没有任何测试台注入的理想值，这决定了工程能直接往真实 MAC 上迁移。

### 6. 多端口 servo 仲裁：只有 owner 能写共享 PHC

多端口共用一个 PHC，`w_phc_adjtime_wr = w_adjtime_wr[r_phc_owner]` 一行赋值完成仲裁：只有被选为 owner（GM）端口的伺服写请求透传到 PHC，其余端口即使算出 offset 也被屏蔽，避免多端口互相打架。

## 四、帧驱动闭环数据流

```
MAC RX 字节流（i_rx_clk 异步域）
   │  DA(6) + SA(6) + EtherType(0x88F7) + PTP 头
   ▼
gptp_rx_fifo        异步 FIFO 跨时钟域（MAC 接收时钟 → 系统时钟）
   ▼  系统时钟域字节流
gptp_frame_parser   提取 msgType / sequenceId / correctionField / originTimestamp
   ▼
gptp_top（每端口）
   │  ├─ HTSU   t2/t3 打标 + 驻留时间 residence
   │  ├─ TC     透明钟 one-step correctionField 改写
   │  └─ Pdelay P2P 链路延迟测量
   ▼
gptp_servo          offset = (t1 + cf) - t2，PI 输出 adjtime / adjfine
   ▼  经仲裁：仅 owner 端口可写
gptp_phc            共享相位累积时钟
   ▼
gptp_tx_gen         owner（GM）端口主动生成 Sync + Follow_Up + Announce 出帧
   ▼
MAC TX 字节流（owner 主动发；非 owner 由 glue 透传上游 Sync）
```

## 五、关键公式

P2P 对等延迟（t1 发 Req，t2 对端收，t3 对端发 Resp，t4 本端收）：

```
peerDelay = ((t4 - t1) - (t3 - t2)) / 2
```

透明钟改写 correctionField（64 位定点，1ns = 2^16）：

```
cf_out = cf_in + (residence + peerDelay) × 2^16
```

伺服 offset：

```
offset = (t1 + cf) - t2
```

## 六、验证

采用由底向上逐级验证，12 个测试台一次跑齐（`bash sim/run_sim.sh`），全部 PASS：

| 层级 | 测试台 | 验证内容 |
|------|--------|----------|
| 基础 | tb_gptp_phc | PHC 计数 / 调频 / 调相 / 初始化 |
| 基础 | tb_gptp_htsu | t2/t3 打标 + 驻留时间（非 event 帧不锁 t2） |
| 基础 | tb_gptp_tc | one-step correctionField 改写 |
| 基础 | tb_gptp_pdelay | P2P 双向延迟测量 |
| 基础 | tb_gptp_mac_glue | PTP 帧识别 / msgType / CF 改写 |
| 帧解析 | tb_gptp_frame_parser | 各消息类型字段提取 + 非 PTP 抑制 |
| 控制面 | tb_gptp_bmca | 最佳主时钟选举（含 Passive 角色） |
| 执行面 | tb_gptp_servo | PI 伺服环 |
| 集成 | tb_gptp_top | 单端口端到端联动（residence=40ns, cf_out=2621440） |
| 系统 | tb_gptp_switch | 多端口 / 共享 PHC / 仲裁 / 真实 TX 转发 / FIFO CDC |
| 系统 | tb_gptp_cascade | 两级级联：GM→线缆→Slave，CF 链式累积，BMCA 收敛为 Slave |
| 适配 | tb_gptp_mac_adapt | GMII 透传连通，XGMII / AXI-S 占位就绪 |

几个关键数值：单端口集成测试 residence 实测 40ns，cf_out = 2621440 = 40 × 2^16，HTSU 打标、TC 改写、CF 定点格式三处实现数值自洽；级联验证中 Slave 端 Follow_Up 的 correctionField 为 e008000000（非零，residence 已叠加），BMCA 收敛为 Slave（role=1, is_gm=0）。

## 七、后续方向

1. 对接真实 MAC IP：把 `MAC_IF` 切到 XGMII 或 AXI-S 并实现序列化，异步 FIFO 的 `i_rx_clk` 接真实 MAC 接收时钟。
2. two-step 透明钟回读路径（`TC_MODE=1`）已在 `gptp_tc` 预留 `o_cf_rd` 脉冲，可补独立测试台。
3. 多跳（大于 2 级）级联与全网 BMCA 收敛的规模化验证作为压力项。
4. 把 PHC 与时间戳打标思路迁移到多通道采样精确时间对齐场景。

## 收束

这个工程把 802.1AS gPTP 的完整同步链路用纯 Verilog 落了地，核心三点：透明钟实时累积驻留时间、HTSU 在 CF 域字节到达前算好 residence、MAC 胶合用组合下一值兼容直驱与级联双路径。功能点覆盖从帧解析、跨时钟域、时间戳、透明钟、P2P 测延迟、BMCA 选举、PI 伺服到 GM 主动出帧的整条链，创新点集中在几个用仿真逼出来的时序问题的解法上。12 个测试台一键回归通过，级联验证证明 CF 链式累积与 BMCA 收敛都正确，是一个帧驱动、能真正跑同步闭环的 RTL 底座。

（工程源码与仿真脚本见 `tsn_8021as` 仓库，README 含完整模块清单与验证结论，可视化波形与架构图见 `doc/TSN_gPTP_可视化报告.html`。）
