/////////////////////////////////////////////////////////////////
// Copyright (c) 2026 local TSN gPTP port (based on OpenTSN multi-port top)
// 模块: gptp_switch  —  多端口 TSN 交换机 gPTP 时间同步顶层
// 架构: 1 共享 PHC (GM 相位基准) + N 个 gptp_top 端口实例 + 每端口
//       BMCA 角色决策 + PI 伺服环。servo 经仲裁后仅 GM/最优端口写 PHC。
// 已完成: ① 真实 TX 转发 —— owner(GM) 端口由 gptp_tx_gen 主动生成
//         Sync/Follow_Up 出帧; 非 owner 端口经 glue 透传上游 Sync。
//       ② 多端口 servo 共享 PHC 仲裁 —— 仅选中 GM 端口 servo 写 PHC。
//       ③ 跨时钟域 —— 每端口 MAC RX 经 gptp_rx_fifo 异步 FIFO 跨到系统域。
// 规范: 端口对齐 / 分组注释 / r_w_ro 前缀 / i_clk-i_rst / posedge i_rst /
//       'd0 / ro_ 经 assign / 实例化集中 inst 组且端口括号对齐。
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "gptp_defines.v"

module gptp_switch #(
    parameter NPORTS       = 4,
    parameter CLK_FREQ_HZ  = 125_000_000,
    parameter PDREQ_PERIOD = 32'd100000000
)(
    // ---- 系统时钟/复位 ----
    input  wire                           i_clk,
    input  wire                           i_rst,

    // ---- 每端口 MAC 接口 (数组) ----
    input  wire [7:0]                     i_rx_data      [0:NPORTS-1],
    input  wire                           i_rx_vld       [0:NPORTS-1],
    input  wire                           i_rx_sop       [0:NPORTS-1],
    input  wire                           i_rx_eop       [0:NPORTS-1],
    input  wire                           i_rx_clk       [0:NPORTS-1],  // 每端口 MAC 接收时钟 (异步域)
    output wire [7:0]                     o_tx_data      [0:NPORTS-1],
    output wire                           o_tx_vld       [0:NPORTS-1],
    output wire                           o_tx_sop       [0:NPORTS-1],
    output wire                           o_tx_eop       [0:NPORTS-1],

    // ---- 每端口 Pdelay 收发接口 ----
    input  wire                           i_pdreq_send   [0:NPORTS-1],
    input  wire                           i_pdresp_rx    [0:NPORTS-1],
    input  wire [`GPTT_TIME_W-1:0]        i_t2_resp      [0:NPORTS-1],
    input  wire                           i_pdresfu_rx   [0:NPORTS-1],
    input  wire [`GPTT_TIME_W-1:0]        i_t3_respfu    [0:NPORTS-1],
    output wire [`GPTT_TIME_W-1:0]        o_t1_ns        [0:NPORTS-1],

    // ---- 全局 GM 时间输出 ----
    output wire [`GPTT_TIME_W-1:0]        o_gm_time_ns,
    output wire [31:0]                    o_gm_time_frac,

    // ---- 各端口状态 (调试) ----
    output wire [1:0]                     o_port_role    [0:NPORTS-1],
    output wire                           o_servo_locked [0:NPORTS-1],
    output wire [`GPTT_TIME_W-1:0]        o_peer_delay   [0:NPORTS-1],
    output wire                           o_is_gm        [0:NPORTS-1],

    // ---- 每端口 servo 同步触发输入 (调试/集成, 默认 0) ----
    input  wire                           i_port_sync_rx [0:NPORTS-1],

    // ---- 仲裁观测/调试输出 ----
    output wire [$clog2(NPORTS)-1:0]      o_phc_owner,
    output wire                           o_phc_adjtime_wr,
    output wire                           o_phc_adjfine_wr,
    output wire                           o_adjtime_wr_tap [0:NPORTS-1]
);

// ----- param -----
// (本模块参数见 module 头)

// ----- reg -----
// 仲裁选中的 PHC 拥有者端口号 (0..NPORTS-1), 默认 0
reg  [$clog2(NPORTS)-1:0] r_phc_owner;

// ----- wire -----
wire [`GPTT_TIME_W-1:0] w_phc_ns;
wire [31:0]             w_phc_frac;
wire        w_rx_sof    [0:NPORTS-1];
wire        w_rx_eof    [0:NPORTS-1];
wire        w_tx_sop    [0:NPORTS-1];   // 真实转发 TX 流 (owner=tx_gen, 其余=glue 透传)
wire        w_tx_eop    [0:NPORTS-1];
// 每端口 RX 经异步 FIFO 跨域后的系统域字节流
wire [7:0]  w_fifo_rdata [0:NPORTS-1];
wire        w_fifo_rvld  [0:NPORTS-1];
wire        w_fifo_rsop  [0:NPORTS-1];
wire        w_fifo_reop  [0:NPORTS-1];
wire        w_fifo_rempty[0:NPORTS-1];
wire        w_fifo_wfull [0:NPORTS-1];
// 每端口 TX 生成器输出 (owner 端口主动出帧)
wire [7:0]  w_txg_data   [0:NPORTS-1];
wire        w_txg_vld    [0:NPORTS-1];
wire        w_txg_sop    [0:NPORTS-1];
wire        w_txg_eop    [0:NPORTS-1];
// glue 透传 TX 输出 (非 owner 端口用)
wire [7:0]  w_glue_tx_data [0:NPORTS-1];
wire        w_glue_tx_vld  [0:NPORTS-1];
wire        w_glue_tx_sop  [0:NPORTS-1];
wire        w_glue_tx_eop  [0:NPORTS-1];
wire        w_is_event  [0:NPORTS-1];
wire        w_tx_is_event [0:NPORTS-1];
wire [3:0]  w_msg_type  [0:NPORTS-1];
wire [63:0] w_cf_new    [0:NPORTS-1];
wire        w_cf_wr     [0:NPORTS-1];
wire [1:0]  w_role      [0:NPORTS-1];
wire        w_role_vld  [0:NPORTS-1];
wire        w_is_gm     [0:NPORTS-1];
wire        w_adjtime_wr  [0:NPORTS-1];
wire signed [`GPTT_TIME_W-1:0] w_adjtime_delta [0:NPORTS-1];
wire        w_adjfine_wr  [0:NPORTS-1];
wire signed [31:0] w_adjfine_add [0:NPORTS-1];
wire        w_locked    [0:NPORTS-1];
// top 层暴露的 peer_delay / t1 (供 switch 输出)
wire [`GPTT_TIME_W-1:0] w_peer_dly [0:NPORTS-1];
wire [`GPTT_TIME_W-1:0] w_t1      [0:NPORTS-1];
// 每端口帧解析 + Sync/Follow_Up 闭环相关
wire [`GPTT_TIME_W-1:0] w_rx_ts     [0:NPORTS-1];  // 本端口 HTSU 接收时间戳 (t2/t3)
wire [`GPTT_TIME_W-1:0] w_fu_t1     [0:NPORTS-1];  // 本端口 Follow_Up 携带的 t1
wire [63:0]             w_cf        [0:NPORTS-1];  // 本端口解析的 correctionField
wire                     w_sync_vld  [0:NPORTS-1];  // 本端口收到 Sync (EOF)
wire                     w_fu_vld    [0:NPORTS-1];  // 本端口收到 Follow_Up (EOF)
reg  [`GPTT_TIME_W-1:0] r_t2_cap    [0:NPORTS-1];  // 最近一次 Sync 的本地 t2 锁存
// 仲裁: 仅选中端口的 servo 可写 PHC
wire        w_phc_adjtime_wr;
wire signed [`GPTT_TIME_W-1:0] w_phc_adjtime_delta;
wire        w_phc_adjfine_wr;
wire signed [31:0] w_phc_adjfine_add;

// ----- assign -----
assign o_gm_time_ns   = w_phc_ns;
assign o_gm_time_frac = w_phc_frac;
generate
    genvar gp;
    for (gp = 0; gp < NPORTS; gp = gp + 1) begin : GEN_ASSIGN
        assign o_port_role[gp]    = w_role[gp];
        assign o_servo_locked[gp] = w_locked[gp];
        assign o_peer_delay[gp]   = w_peer_dly[gp];
        assign o_is_gm[gp]        = w_is_gm[gp];
        assign o_t1_ns[gp]        = w_t1[gp];
    end
endgenerate

// ----- FSM -----
// (本模块为组合集成层, 无显式状态机)

// ----- inst -----
// 共享 PHC: 仅仲裁选中的端口 servo 可写
gptp_phc #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) u_phc (
    .i_clk              (i_clk),
    
            .i_rst              (i_rst),
    .w_adjfine_wr       (w_phc_adjfine_wr),
    .w_adjfine_addend   (w_phc_adjfine_add),
    .w_adjtime_wr       (w_phc_adjtime_wr),
    .w_adjtime_delta_ns (w_phc_adjtime_delta),
    .w_settime_wr       (1'b0),
    .w_settime_ns       ({`GPTT_TIME_W{1'b0}}),
    .o_time_ns          (w_phc_ns),
    .o_time_frac        (w_phc_frac)
);

generate
    genvar p;
    for (p = 0; p < NPORTS; p = p + 1) begin : GEN_PORT
        // 跨时钟域异步 FIFO: 写口 MAC 接收时钟域, 读口系统时钟域
        gptp_rx_fifo #(.DEPTH_W(6)) u_rxfifo (
            .i_wclk      (i_rx_clk[p]),
            .i_rst       (i_rst),
            .i_wdata     (i_rx_data[p]),
            .i_wvld      (i_rx_vld[p]),
            .i_wsop      (i_rx_sop[p]),
            .i_weop      (i_rx_eop[p]),
            .o_wfull     (w_fifo_wfull[p]),
            .i_rclk      (i_clk),
            .o_rdata     (w_fifo_rdata[p]),
            .o_rvld      (w_fifo_rvld[p]),
            .o_rsop      (w_fifo_rsop[p]),
            .o_reop      (w_fifo_reop[p]),
            .o_rempty    (w_fifo_rempty[p])
        );

        gptp_mac_glue #(.PORT_ID(p[3:0])) u_glue (
            .i_clk          (i_clk),

            .i_rst              (i_rst),
            .i_rx_data      (w_fifo_rdata[p]),
            .i_rx_vld       (w_fifo_rvld[p]),
            .i_rx_sop       (w_fifo_rsop[p]),
            .i_rx_eop       (w_fifo_reop[p]),
            .o_tx_data      (w_glue_tx_data[p]),
            .o_tx_vld       (w_glue_tx_vld[p]),
            .o_tx_sop       (w_glue_tx_sop[p]),
            .o_tx_eop       (w_glue_tx_eop[p]),
            .i_tx_rdy       (1'b1),
            .o_rx_sof       (w_rx_sof[p]),
            .o_rx_eof       (w_rx_eof[p]),
            .o_is_event_pkt (w_is_event[p]),
            .o_msg_type     (w_msg_type[p]),
            .o_tx_is_event_pkt (w_tx_is_event[p]),
            .i_cf_new       (w_cf_new[p]),
            .i_cf_wr        (w_cf_wr[p]),
            .o_cf_wr_done   ()
        );

        // 真实 TX 转发: owner(GM) 端口由 tx_gen 主动生成 Sync/Follow_Up;
        // 非 owner 端口透传上游 Sync (glue o_tx_* 已为透传)
        gptp_tx_gen #(.PORT_ID(p[3:0])) u_txgen (
            .i_clk      (i_clk),
            .i_rst      (i_rst),
            .i_enable   (r_phc_owner == p[$clog2(NPORTS)-1:0]),
            .i_phc_ns   (w_phc_ns),
            .i_period   (32'd200),
            .o_tx_data  (w_txg_data[p]),
            .o_tx_vld   (w_txg_vld[p]),
            .o_tx_sop   (w_txg_sop[p]),
            .o_tx_eop   (w_txg_eop[p])
        );

        gptp_top #(.PORT_ID(p[3:0]), .CLK_FREQ_HZ(CLK_FREQ_HZ),
                   .PDREQ_PERIOD(PDREQ_PERIOD)) u_top (
            .i_clk              (i_clk),

            .i_rst              (i_rst),
            .i_adjfine_wr       (1'b0),
            .i_adjfine_addend   (32'sd0),
            .i_adjtime_wr       (w_adjtime_wr[p]),
            .i_adjtime_delta_ns (w_adjtime_delta[p]),
            .i_settime_wr       (1'b0),
            .i_settime_ns       ({`GPTT_TIME_W{1'b0}}),
            .o_time_ns          (),
            .o_time_frac        (),
            .i_rx_sof           (w_rx_sof[p]),
            .i_rx_eof           (w_rx_eof[p]),
            .i_tx_sof           (w_tx_sop[p]),
            .i_tx_eof           (w_tx_eop[p]),
            .i_is_event_pkt     (w_is_event[p]),
            .i_pkt_vld          (w_tx_is_event[p]),
            .i_cf_in            (w_cf[p]),
            .o_cf_out           (w_cf_new[p]),
            .o_cf_wr            (w_cf_wr[p]),
            .o_cf_rd            (),
            .i_pdreq_send       (i_pdreq_send[p]),
            .i_pdresp_rx        (i_pdresp_rx[p]),
            .i_t2_resp          (i_t2_resp[p]),
            .i_pdresfu_rx       (i_pdresfu_rx[p]),
            .i_t3_respfu        (i_t3_respfu[p]),
            .o_pdreq_vld        (),
            .o_peer_delay_ns    (w_peer_dly[p]),
            .o_peer_delay_vld   (),
            .o_rx_ts_ns         (w_rx_ts[p]),
            .o_rx_ts_frac       (),
            .o_tx_ts_ns         (),
            .o_tx_ts_frac       (),
            .o_residence_ns     (),
            .o_residence_vld    (),
            .o_t1_ns            (w_t1[p])
        );

        // 帧解析: 从 MAC 字节流抽取 PTP 字段 (Sync/Follow_Up/Pdelay 等)
        gptp_frame_parser #(.PORT_ID(p[3:0])) u_parser (
            .i_clk          (i_clk),
            .i_rst          (i_rst),
            .i_rx_data      (w_fifo_rdata[p]),
            .i_rx_vld       (w_fifo_rvld[p]),
            .i_rx_sop       (w_fifo_rsop[p]),
            .i_rx_eop       (w_fifo_reop[p]),
            .o_msg_type     (),
            .o_seq_id       (),
            .o_cf_ns        (w_cf[p]),
            .o_origin_ts_ns (w_fu_t1[p]),
            .o_sync_vld     (w_sync_vld[p]),
            .o_follow_up_vld(w_fu_vld[p]),
            .o_pdreq_vld    (),
            .o_pdresp_vld   (),
            .o_pdresfu_vld  (),
            .o_announce_vld (w_ann_vld[p]),
            .o_ann_priority1(w_ann_p1[p]),
            .o_ann_clock_id (w_ann_cid[p]),
            .o_ann_priority2(w_ann_p2[p]),
            .o_ann_steps_removed(w_ann_sr[p])
        );

        // Announce 优先级向量 (供 BMCA)
        wire [7:0]               w_ann_p1 [0:NPORTS-1];
        wire [`GPTT_TIME_W-1:0]  w_ann_cid [0:NPORTS-1];
        wire [7:0]               w_ann_p2 [0:NPORTS-1];
        wire [15:0]              w_ann_sr [0:NPORTS-1];
        wire                     w_ann_vld [0:NPORTS-1];

        gptp_bmca #(.PORT_ID(p[3:0])) u_bmca (
            .i_clk              (i_clk),
            
            .i_rst              (i_rst),
            .i_local_priority1  (8'd128),
            .i_local_clock_id   ({56'd0, p[7:0]}),
            .i_local_priority2  (8'd128),
            .i_announce_rx      (w_ann_vld[p]),
            .i_rem_priority1    (w_ann_p1[p]),
            .i_rem_clock_id     (w_ann_cid[p]),
            .i_rem_priority2    (w_ann_p2[p]),
            .i_rem_steps_removed(w_ann_sr[p]),
            .i_rem_port_id      (64'd0),
            .o_port_role        (w_role[p]),
            .o_role_vld         (w_role_vld[p]),
            .o_is_gm            (w_is_gm[p])
        );

        gptp_servo u_servo (
            .i_clk              (i_clk),

            .i_rst              (i_rst),
            .i_sync_rx          (w_fu_vld[p] | i_port_sync_rx[p]),
            .i_t1_gm_ns         (w_fu_t1[p]),
            .i_t2_local_ns      (r_t2_cap[p]),
            .i_cf_ns            (w_cf[p]),
            .i_kp               (32'sd1024),
            .i_ki               (32'sd64),
            .o_adjtime_wr       (w_adjtime_wr[p]),
            .o_adjtime_delta_ns (w_adjtime_delta[p]),
            .o_adjfine_wr       (w_adjfine_wr[p]),
            .o_adjfine_addend   (w_adjfine_add[p]),
            .o_servo_locked     (w_locked[p])
        );

        // TX 出帧多路: owner 端口用 tx_gen 主动出帧, 其余用 glue 透传
        assign o_tx_data[p] = (r_phc_owner == p[$clog2(NPORTS)-1:0]) ? w_txg_data[p]   : w_glue_tx_data[p];
        assign o_tx_vld[p]  = (r_phc_owner == p[$clog2(NPORTS)-1:0]) ? w_txg_vld[p]    : w_glue_tx_vld[p];
        assign o_tx_sop[p]  = (r_phc_owner == p[$clog2(NPORTS)-1:0]) ? w_txg_sop[p]    : w_glue_tx_sop[p];
        assign o_tx_eop[p]  = (r_phc_owner == p[$clog2(NPORTS)-1:0]) ? w_txg_eop[p]    : w_glue_tx_eop[p];
        assign w_tx_sop[p]  = o_tx_sop[p];
        assign w_tx_eop[p]  = o_tx_eop[p];
    end
endgenerate

// ----- combine_Logic -----
// 待办②: servo 仲裁 —— 选中端口可写 PHC, 其余屏蔽
assign w_phc_adjtime_wr    = w_adjtime_wr[r_phc_owner];
assign w_phc_adjtime_delta = w_adjtime_delta[r_phc_owner];
assign w_phc_adjfine_wr    = w_adjfine_wr[r_phc_owner];
assign w_phc_adjfine_add   = w_adjfine_add[r_phc_owner];

// 仲裁观测/调试
assign o_phc_owner      = r_phc_owner;
assign o_phc_adjtime_wr = w_phc_adjtime_wr;
assign o_phc_adjfine_wr = w_phc_adjfine_wr;
generate
    genvar gt;
    for (gt = 0; gt < NPORTS; gt = gt + 1) begin : GEN_TAP
        assign o_adjtime_wr_tap[gt] = w_adjtime_wr[gt];
    end
endgenerate

// ----- always -----
integer k;
// PHC 拥有者仲裁: 选 is_gm 端口; 若多个则取最低号; 否则取首个 Slave
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_phc_owner <= 'd0;
    else begin
        // 简化仲裁: 遍历端口, 优先选中 is_gm==1 者
        integer j;
        reg found;
        found = 1'b0;
        r_phc_owner <= r_phc_owner;
        for (j = 0; j < NPORTS; j = j + 1) begin
            if (!found && w_is_gm[j]) begin
                r_phc_owner <= j[$clog2(NPORTS)-1:0];
                found = 1'b1;
            end
        end
    end
end

// Sync 本地时间戳锁存: 收到 Sync 帧尾时, 锁存 HTSU 接收时间戳作为 t2
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst) begin
        for (k = 0; k < NPORTS; k = k + 1)
            r_t2_cap[k] <= 'd0;
    end else begin
        for (k = 0; k < NPORTS; k = k + 1) begin
            if (w_sync_vld[k])
                r_t2_cap[k] <= w_rx_ts[k];
            else
                r_t2_cap[k] <= r_t2_cap[k];
        end
    end
end

endmodule
