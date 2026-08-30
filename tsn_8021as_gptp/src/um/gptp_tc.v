/////////////////////////////////////////////////////////////////
// Copyright (c) 2026 local TSN gPTP port (based on OpenTSN TX_PROC correction)
// 模块: gptp_tc  —  透明时钟 (Transparent Clock, one-step / two-step)
// 功能: 将本跳驻留时间 residence 与 P2P 链路延迟 peerDelay 累加,
//       在线改写出端口 PTP 报文的 correctionField (64-bit, ns*2^16 定点)。
// 说明: TC_MODE=0 one-step 直接改报文; TC_MODE=1 two-step 需回读原 CF。
// 规范: 端口对齐 / 分组注释 / r_w_ro 前缀 / i_clk-i_rst / posedge i_rst /
//       'd0 / 单信号 always / ro_ 经 assign 接 output。
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "gptp_defines.v"

module gptp_tc #(
    parameter PORT_ID = 4'd0,
    parameter TC_MODE = 1'd0   // 0 = one-step, 1 = two-step
)(
    // ---- 时钟/复位 ----
    input  wire                         i_clk,
    input  wire                         i_rst,

    // ---- 来自 HTSU 的驻留时间 (本跳) ----
    input  wire [`GPTT_TIME_W-1:0]      i_residence_ns,
    input  wire                         i_residence_vld,

    // ---- 本端口 P2P 链路延迟 ----
    input  wire [`GPTT_TIME_W-1:0]      i_peer_delay_ns,
    input  wire                         i_peer_delay_vld,

    // ---- 报文流 (简化: 仅暴露 CF 相关握手) ----
    input  wire                         i_pkt_vld,
    input  wire [63:0]                  i_cf_in,
    output wire [63:0]                  o_cf_out,
    output wire                         o_cf_wr,
    output wire                         o_cf_rd
);

// ----- param -----
localparam [63:0] NS_TO_CF = 64'd65536;   // 1ns = 2^16

// ----- reg -----
reg [`GPTT_TIME_W-1:0] r_residence_ns;
reg [`GPTT_TIME_W-1:0] r_peer_delay_ns;
reg [63:0]             ro_cf_out;
reg                    ro_cf_wr;
reg                    ro_cf_rd;

// ----- wire -----
wire [`GPTT_TIME_W-1:0] w_total_ns;
wire                    w_cf_rd_en;

// ----- assign -----
assign o_cf_out = ro_cf_out;
assign o_cf_wr  = ro_cf_wr;
assign o_cf_rd  = ro_cf_rd;
assign w_total_ns = r_residence_ns + r_peer_delay_ns;
// two-step 模式且报文有效时回读原 CF; one-step 不回读
assign w_cf_rd_en = (TC_MODE == 1'd1) && i_pkt_vld;

// ----- FSM -----
// (本模块无状态机)

// ----- inst -----
// (本模块无实例化)

// ----- combine_Logic -----
// (次态/组合已并入 wire assign 与单信号 always)

// ----- always -----
// residence 锁存 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_residence_ns <= 'd0;
    else if (i_residence_vld)
        r_residence_ns <= i_residence_ns;
    else
        r_residence_ns <= r_residence_ns;
end

// peerDelay 锁存 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_peer_delay_ns <= 'd0;
    else if (i_peer_delay_vld)
        r_peer_delay_ns <= i_peer_delay_ns;
    else
        r_peer_delay_ns <= r_peer_delay_ns;
end

// CF 输出 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_cf_out <= 'd0;
    else if (i_pkt_vld)
        ro_cf_out <= i_cf_in + (w_total_ns * NS_TO_CF);
    else
        ro_cf_out <= ro_cf_out;
end

// CF 改写脉冲 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_cf_wr <= 'd0;
    else if (i_pkt_vld)
        ro_cf_wr <= 1'b1;
    else
        ro_cf_wr <= 1'b0;
end

// CF 回读脉冲 (单信号, 仅 two-step)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_cf_rd <= 'd0;
    else if (w_cf_rd_en)
        ro_cf_rd <= 1'b1;
    else
        ro_cf_rd <= 1'b0;
end

endmodule
