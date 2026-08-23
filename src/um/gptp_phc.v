/////////////////////////////////////////////////////////////////
// Copyright (c) 2026 local TSN gPTP port (based on OpenTSN CYC_SYNC)
// 模块: gptp_phc  —  精确时间硬件时钟 (PHC, Precision Time Clock)
// 功能: 64-bit 纳秒自由运行计数器 + 32-bit 亚纳秒分数;
//       支持 adjfine(频率微调) / adjtime(相位跳变) / settime(初始化)。
// 说明: 本模块无状态机, 为纯时序计数器 + 组合次态; 每个 always 仅驱一信号。
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "gptp_defines.v"

module gptp_phc #(
    parameter CLK_FREQ_HZ = 125_000_000   // TSN 系统时钟频率 (Hz)
)(
    // ---- 时钟/复位 (单时钟域) ----
    input  wire                         i_clk,
    input  wire                         i_rst,

    // ---- 频率微调 adjfine: 加数, 中心 2^31 表示无频偏 (有符号) ----
    input  wire                         w_adjfine_wr,
    input  wire signed [31:0]           w_adjfine_addend,

    // ---- 相位跳变 adjtime: 有符号纳秒修正 ----
    input  wire                         w_adjtime_wr,
    input  wire signed [`GPTT_TIME_W-1:0] w_adjtime_delta_ns,

    // ---- 时间初始化 (GM 或外部 PPS 对齐) ----
    input  wire                         w_settime_wr,
    input  wire [`GPTT_TIME_W-1:0]      w_settime_ns,

    // ---- 时间输出 (连续, 供 HTSU 在线上捕获) ----
    output wire [`GPTT_TIME_W-1:0]      o_time_ns,
    output wire [31:0]                  o_time_frac
);

// ----- param -----
localparam integer TICK_NS_I = 1000000000 / CLK_FREQ_HZ;   // 每 tick 基础纳秒数

// ----- reg -----
reg  [`GPTT_TIME_W-1:0] r_ns;
reg  [31:0]             r_frac;          // 频率校正累加器 (按无符号回绕解释)
reg  signed [31:0]      r_freq_corr;     // 相对频偏加数, 0 = 无偏
reg  [`GPTT_TIME_W-1:0] ro_time_ns;      // 输出打拍寄存器
reg  [31:0]             ro_time_frac;    // 输出打拍寄存器

// ----- wire -----
wire [`GPTT_TIME_W-1:0] w_tick_inc;      // 本 tick 纳秒增量 (含进位/借位)
wire [`GPTT_TIME_W-1:0] w_ns_nxt;        // 纳秒次态
wire [31:0]             w_frac_nxt;      // 分数次态

// ----- assign -----
assign o_time_ns   = ro_time_ns;
assign o_time_frac = ro_time_frac;
assign w_tick_inc  = `GPTT_TIME_W'(TICK_NS_I);
assign w_frac_nxt  = r_frac + r_freq_corr;
// 纳秒次态 (含进位/借位检测): 基础增量 + 频偏导致的 +/-1ns 修正
assign w_ns_nxt = (r_freq_corr[31]) ?
                   ((w_frac_nxt > r_frac) ? (r_ns + `GPTT_TIME_W'(TICK_NS_I - 1)) : (r_ns + w_tick_inc)) :
                   ((w_frac_nxt < r_frac) ? (r_ns + `GPTT_TIME_W'(TICK_NS_I + 1)) : (r_ns + w_tick_inc));

// ----- FSM -----
// (本模块无状态机)

// ----- inst -----
// (本模块无实例化)

// ----- combine_Logic -----
// (次态/组合已并入 assign 组)

// ----- always -----
// 频率校正加数锁存 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_freq_corr <= 'd0;
    else if (w_adjfine_wr)
        r_freq_corr <= w_adjfine_addend - 32'sd2147483648;
    else
        r_freq_corr <= r_freq_corr;
end

// 纳秒计数器 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_ns <= 'd0;
    else if (w_settime_wr)
        r_ns <= w_settime_ns;
    else if (w_adjtime_wr)
        r_ns <= r_ns + w_adjtime_delta_ns;   // 有符号相位修正
    else
        r_ns <= w_ns_nxt;
end

// 分数累加器 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_frac <= 'd0;
    else
        r_frac <= w_frac_nxt;
end

// 时间输出 ns (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_time_ns <= 'd0;
    else
        ro_time_ns <= r_ns;
end

// 时间输出 frac (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_time_frac <= 'd0;
    else
        ro_time_frac <= r_frac;
end

endmodule
