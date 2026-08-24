/////////////////////////////////////////////////////////////////
// Copyright (c) 2026 local TSN gPTP port (based on OpenTSN PTP_CTRL P2P)
// 模块: gptp_pdelay  —  802.1AS 强制 P2P 对等延迟测量
// 功能: 周期性发 Pdelay_Req, 收 Pdelay_Resp + Resp_Follow_Up, 计算
//       peerDelay = ((t4-t1)-(t3-t2))/2 (双向不对称取平均)。
// 规范: 端口对齐 / 分组注释 / r_w_ro 前缀 / state_c-state_n / P_ST_ 独热 /
//       跳转条件独立 wire / 三段式 / i_clk-i_rst / posedge i_rst / 'd0。
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "gptp_defines.v"

module gptp_pdelay #(
    parameter PORT_ID      = 4'd0,
    parameter PDREQ_PERIOD = 32'd100000000  // Pdelay_Req 周期 (clk ticks)
)(
    // ---- 时钟/复位 ----
    input  wire                         i_clk,
    input  wire                         i_rst,

    // ---- PHC 时间 (用于打 t1/t4 本地戳) ----
    input  wire [`GPTT_TIME_W-1:0]      i_phc_time_ns,

    // ---- 报文收发握手 ----
    input  wire                         i_pdreq_send,
    input  wire                         i_pdresp_rx,
    input  wire [63:0]                  i_t2_resp,
    input  wire                         i_pdresfu_rx,
    input  wire [63:0]                  i_t3_respfu,

    output wire                         o_pdreq_vld,
    output wire [`GPTT_TIME_W-1:0]      o_peer_delay_ns,
    output wire                         o_peer_delay_vld,
    output wire [`GPTT_TIME_W-1:0]      o_t1_ns,
    output wire [`GPTT_TIME_W-1:0]      o_t4_ns
);

// ----- param -----
// (状态常量见 FSM 组)

// ----- reg -----
reg [31:0]             r_per_cnt;
reg signed [`GPTT_TIME_W-1:0] r_t1;
reg signed [`GPTT_TIME_W-1:0] r_t2;
reg signed [`GPTT_TIME_W-1:0] r_t3;
reg signed [`GPTT_TIME_W-1:0] r_t4;
reg                    ro_pdreq_vld;
reg [`GPTT_TIME_W-1:0] ro_peer_delay_ns;
reg                    ro_peer_delay_vld;
reg [`GPTT_TIME_W-1:0] ro_t1_ns;
reg [`GPTT_TIME_W-1:0] ro_t4_ns;

// ----- wire -----
wire [`GPTT_TIME_W-1:0] w_peer_delay_calc;

// ----- assign -----
assign o_pdreq_vld       = ro_pdreq_vld;
assign o_peer_delay_ns   = ro_peer_delay_ns;
assign o_peer_delay_vld  = ro_peer_delay_vld;
assign o_t1_ns           = ro_t1_ns;
assign o_t4_ns           = ro_t4_ns;
assign w_peer_delay_calc = (r_t4 - r_t1 - (r_t3 - r_t2)) >>> 1;

// ----- FSM -----
// 状态常量 (独热码)
parameter P_ST_IDLE   = 5'b00001;
parameter P_ST_SEND   = 5'b00010;
parameter P_ST_WAIT_R = 5'b00100;
parameter P_ST_WAIT_F = 5'b01000;
parameter P_ST_CALC   = 5'b10000;
reg [4:0] state_c;
reg [4:0] state_n;

// 状态跳转条件 (独立 wire)
wire p_st_idle2p_st_send_start   = (state_c==P_ST_IDLE)   && (i_pdreq_send || (r_per_cnt >= PDREQ_PERIOD));
wire p_st_send2p_st_wait_r_start = (state_c==P_ST_SEND)   && 1'b1;
wire p_st_wait_r2p_st_wait_f_start = (state_c==P_ST_WAIT_R) && i_pdresp_rx;
wire p_st_wait_f2p_st_calc_start = (state_c==P_ST_WAIT_F) && i_pdresfu_rx;
wire p_st_calc2p_st_idle_start   = (state_c==P_ST_CALC)   && 1'b1;

// ----- inst -----
// (本模块无实例化)

// ----- combine_Logic -----
// 次态计算 (仅 case, default -> P_ST_IDLE)
always @* begin
    case (state_c)
        P_ST_IDLE:   if (p_st_idle2p_st_send_start)     state_n = P_ST_SEND;   else state_n = state_c;
        P_ST_SEND:   if (p_st_send2p_st_wait_r_start)   state_n = P_ST_WAIT_R; else state_n = state_c;
        P_ST_WAIT_R: if (p_st_wait_r2p_st_wait_f_start) state_n = P_ST_WAIT_F; else state_n = state_c;
        P_ST_WAIT_F: if (p_st_wait_f2p_st_calc_start)   state_n = P_ST_CALC;   else state_n = state_c;
        P_ST_CALC:   if (p_st_calc2p_st_idle_start)     state_n = P_ST_IDLE;   else state_n = state_c;
        default:     state_n = P_ST_IDLE;
    endcase
end

// ----- always -----
// 周期计数器 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_per_cnt <= 'd0;
    else if (r_per_cnt >= PDREQ_PERIOD)
        r_per_cnt <= 'd0;
    else
        r_per_cnt <= r_per_cnt + 32'd1;
end

// 状态寄存器 (单信号, 仅更新 state_c)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        state_c <= 'd0;
    else
        state_c <= state_n;
end

// t1 锁存 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_t1 <= 'd0;
    else if (state_c==P_ST_SEND)
        r_t1 <= i_phc_time_ns;
    else
        r_t1 <= r_t1;
end

// t2 锁存 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_t2 <= 'd0;
    else if ((state_c==P_ST_WAIT_R) && i_pdresp_rx)
        r_t2 <= i_t2_resp;
    else
        r_t2 <= r_t2;
end

// t3 锁存 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_t3 <= 'd0;
    else if ((state_c==P_ST_WAIT_F) && i_pdresfu_rx)
        r_t3 <= i_t3_respfu;
    else
        r_t3 <= r_t3;
end

// t4 锁存 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_t4 <= 'd0;
    else if ((state_c==P_ST_WAIT_F) && i_pdresfu_rx)
        r_t4 <= i_phc_time_ns;
    else
        r_t4 <= r_t4;
end

// Pdelay_Req 发出脉冲 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_pdreq_vld <= 'd0;
    else if (state_c==P_ST_SEND)
        ro_pdreq_vld <= 1'b1;
    else
        ro_pdreq_vld <= 1'b0;
end

// t1 输出 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_t1_ns <= 'd0;
    else if (state_c==P_ST_SEND)
        ro_t1_ns <= i_phc_time_ns;
    else
        ro_t1_ns <= ro_t1_ns;
end

// t4 输出 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_t4_ns <= 'd0;
    else if ((state_c==P_ST_WAIT_F) && i_pdresfu_rx)
        ro_t4_ns <= i_phc_time_ns;
    else
        ro_t4_ns <= ro_t4_ns;
end

// peerDelay 输出 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_peer_delay_ns <= 'd0;
    else if (state_c==P_ST_CALC)
        ro_peer_delay_ns <= w_peer_delay_calc;
    else
        ro_peer_delay_ns <= ro_peer_delay_ns;
end

// peerDelay 有效脉冲 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_peer_delay_vld <= 'd0;
    else if (state_c==P_ST_CALC)
        ro_peer_delay_vld <= 1'b1;
    else
        ro_peer_delay_vld <= 1'b0;
end

endmodule
