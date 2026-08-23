/////////////////////////////////////////////////////////////////
// Copyright (c) 2026 local TSN gPTP port (based on OpenTSN PTP_1588 top)
// 模块: gptp_top  —  802.1AS gPTP 交换机端口时间同步顶层 (单端口)
// 集成: PHC + HTSU + TC + Pdelay。对外暴露 MAC 边沿、PHC 控制、
//       CF 改写握手、Pdelay 收发、HTSU 时间戳 (供上层/测试读取)。
// 规范: 端口对齐 / 分组注释 / r_w_ro 前缀 / i_clk-i_rst / posedge i_rst /
//       'd0 / ro_ 经 assign 接 output / 实例化集中 inst 组且端口括号对齐。
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "gptp_defines.v"

module gptp_top #(
    parameter PORT_ID      = 4'd0,
    parameter CLK_FREQ_HZ  = 125_000_000,
    parameter PDREQ_PERIOD = 32'd100000000
)(
    // ---- 系统时钟/复位 ----
    input  wire                           i_clk,
    input  wire                           i_rst,

    // ---- PHC 控制 (闭环伺服/GM 对齐) ----
    input  wire                           i_adjfine_wr,
    input  wire signed [31:0]             i_adjfine_addend,
    input  wire                           i_adjtime_wr,
    input  wire signed [`GPTT_TIME_W-1:0] i_adjtime_delta_ns,
    input  wire                           i_settime_wr,
    input  wire [`GPTT_TIME_W-1:0]        i_settime_ns,

    // ---- PHC 时间输出 ----
    output wire [`GPTT_TIME_W-1:0]        o_time_ns,
    output wire [31:0]                    o_time_frac,

    // ---- MAC wire-side 边沿 ----
    input  wire                           i_rx_sof,
    input  wire                           i_rx_eof,
    input  wire                           i_tx_sof,
    input  wire                           i_tx_eof,
    input  wire                           i_is_event_pkt,

    // ---- 报文 correctionField 改写握手 ----
    input  wire                           i_pkt_vld,
    input  wire [63:0]                    i_cf_in,
    output wire [63:0]                    o_cf_out,
    output wire                           o_cf_wr,
    output wire                           o_cf_rd,

    // ---- Pdelay 报文收发 ----
    input  wire                           i_pdreq_send,
    input  wire                           i_pdresp_rx,
    input  wire [63:0]                    i_t2_resp,
    input  wire                           i_pdresfu_rx,
    input  wire [63:0]                    i_t3_respfu,
    output wire                           o_pdreq_vld,
    output wire [`GPTT_TIME_W-1:0]        o_peer_delay_ns,
    output wire                           o_peer_delay_vld,

    // ---- HTSU 时间戳输出 (供上层/测试读取, 后续建议⑤) ----
    output wire [`GPTT_TIME_W-1:0]        o_rx_ts_ns,
    output wire [31:0]                    o_rx_ts_frac,
    output wire [`GPTT_TIME_W-1:0]        o_tx_ts_ns,
    output wire [31:0]                    o_tx_ts_frac,
    output wire [`GPTT_TIME_W-1:0]        o_residence_ns,
    output wire                           o_residence_vld,

    // ---- 调试/状态 ----
    output wire [`GPTT_TIME_W-1:0]        o_t1_ns
);

// ----- param -----
// (本模块参数见 module 头)

// ----- reg -----
// (顶层仅做连线与输出打拍, 无额外寄存器)

// ----- wire -----
wire [`GPTT_TIME_W-1:0] w_phc_ns;
wire [31:0]             w_phc_frac;
wire [`GPTT_TIME_W-1:0] w_res_ns;
wire                     w_res_vld;
wire [`GPTT_TIME_W-1:0] w_peer_ns;
wire                     w_peer_vld;
wire [`GPTT_TIME_W-1:0] w_rx_ts_ns;
wire [31:0]             w_rx_ts_frac;
wire [`GPTT_TIME_W-1:0] w_tx_ts_ns;
wire [31:0]             w_tx_ts_frac;
// TC CF 改写握手内部连线 (u_tc 输出必须接到这些 wire, 再对外输出)
wire [63:0]             w_tc_cf_out;
wire                     w_tc_cf_wr;
wire                     w_tc_cf_rd;

// ----- assign -----
assign o_time_ns        = w_phc_ns;
assign o_time_frac      = w_phc_frac;
assign o_cf_out         = w_tc_cf_out;
assign o_cf_wr          = w_tc_cf_wr;
assign o_cf_rd          = w_tc_cf_rd;
assign o_pdreq_vld      = u_pdelay.o_pdreq_vld;
assign o_peer_delay_ns  = w_peer_ns;
assign o_peer_delay_vld = u_pdelay.o_peer_delay_vld;
assign o_rx_ts_ns       = w_rx_ts_ns;
assign o_rx_ts_frac     = w_rx_ts_frac;
assign o_tx_ts_ns       = w_tx_ts_ns;
assign o_tx_ts_frac     = w_tx_ts_frac;
assign o_residence_ns   = w_res_ns;
assign o_residence_vld  = w_res_vld;
assign o_t1_ns          = u_pdelay.o_t1_ns;

// ----- FSM -----
// (本模块为组合集成层, 无状态机)

// ----- inst -----
gptp_phc #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) u_phc (
    .i_clk              (i_clk),
    
            .i_rst              (i_rst),
    .w_adjfine_wr       (i_adjfine_wr),
    .w_adjfine_addend   (i_adjfine_addend),
    .w_adjtime_wr       (i_adjtime_wr),
    .w_adjtime_delta_ns (i_adjtime_delta_ns),
    .w_settime_wr       (i_settime_wr),
    .w_settime_ns       (i_settime_ns),
    .o_time_ns          (w_phc_ns),
    .o_time_frac        (w_phc_frac)
);

gptp_htsu #(.PORT_ID(PORT_ID)) u_htsu (
    .i_clk              (i_clk),
    
            .i_rst              (i_rst),
    .i_phc_time_ns      (w_phc_ns),
    .i_phc_time_frac    (w_phc_frac),
    .i_rx_sof           (i_rx_sof),
    .i_rx_eof           (i_rx_eof),
    .i_tx_sof           (i_tx_sof),
    .i_tx_eof           (i_tx_eof),
    .i_is_event_pkt     (i_is_event_pkt),
    .o_rx_ts_ns         (w_rx_ts_ns),
    .o_rx_ts_frac       (w_rx_ts_frac),
    .o_tx_ts_ns         (w_tx_ts_ns),
    .o_tx_ts_frac       (w_tx_ts_frac),
    .o_residence_ns     (w_res_ns),
    .o_residence_vld    (w_res_vld)
);

gptp_pdelay #(.PORT_ID(PORT_ID), .PDREQ_PERIOD(PDREQ_PERIOD)) u_pdelay (
    .i_clk              (i_clk),
    
            .i_rst              (i_rst),
    .i_phc_time_ns      (w_phc_ns),
    .i_pdreq_send       (i_pdreq_send),
    .i_pdresp_rx        (i_pdresp_rx),
    .i_t2_resp          (i_t2_resp),
    .i_pdresfu_rx       (i_pdresfu_rx),
    .i_t3_respfu        (i_t3_respfu),
    .o_pdreq_vld        (),
    .o_peer_delay_ns    (w_peer_ns),
    .o_peer_delay_vld   (),
    .o_t1_ns            (),
    .o_t4_ns            ()
);

gptp_tc #(.PORT_ID(PORT_ID)) u_tc (
    .i_clk              (i_clk),
    
            .i_rst              (i_rst),
    .i_residence_ns     (w_res_ns),
    .i_residence_vld    (w_res_vld),
    .i_peer_delay_ns    (w_peer_ns),
    .i_peer_delay_vld   (w_peer_vld),
    .i_pkt_vld          (i_pkt_vld),
    .i_cf_in            (i_cf_in),
    .o_cf_out           (w_tc_cf_out),
    .o_cf_wr            (w_tc_cf_wr),
    .o_cf_rd            (w_tc_cf_rd)
);

// ----- combine_Logic -----
// (本模块无独立组合逻辑)

// ----- always -----
// (本模块无独立时序逻辑)

endmodule
