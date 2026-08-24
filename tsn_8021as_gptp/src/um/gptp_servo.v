/////////////////////////////////////////////////////////////////
// Copyright (c) 2026 local TSN gPTP port (based on OpenTSN Manage_CTRL servo)
// 模块: gptp_servo  —  闭环时间同步 PI 伺服环
// 功能: 计算本地相对 GM 的 offset = (t1 + cf) - t2, 经 PI 控制产生
//       频率/相位修正量写入 PHC (adjfine + adjtime)。
// 规范: 端口对齐 / 分组注释 / r_w_ro 前缀 / state_c-state_n / P_ST_ 独热 /
//       跳转条件独立 wire / 三段式 / i_clk-i_rst / posedge i_rst / 'd0。
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "gptp_defines.v"

module gptp_servo #(
    parameter Kp_Q  = 16,
    parameter Ki_Q  = 16
)(
    // ---- 时钟/复位 ----
    input  wire                         i_clk,
    input  wire                         i_rst,

    // ---- Sync/Follow_Up 输入 ----
    input  wire                         i_sync_rx,
    input  wire [`GPTT_TIME_W-1:0]      i_t1_gm_ns,
    input  wire [`GPTT_TIME_W-1:0]      i_t2_local_ns,
    input  wire [63:0]                  i_cf_ns,

    // ---- PI 系数 ----
    input  wire signed [31:0]           i_kp,
    input  wire signed [31:0]           i_ki,

    // ---- 输出修正给 PHC ----
    output wire                         o_adjtime_wr,
    output wire signed [`GPTT_TIME_W-1:0] o_adjtime_delta_ns,
    output wire                         o_adjfine_wr,
    output wire signed [31:0]           o_adjfine_addend,
    output wire                         o_servo_locked
);

// ----- param -----
localparam signed [31:0] ADDFINE_CENTER = 32'sd2147483648;  // adjfine 中心无偏

// ----- reg -----
reg signed [`GPTT_TIME_W-1:0] r_offset;
reg signed [63:0]             r_integ;
reg signed [31:0]             r_freq_ppb;
reg                    ro_adjtime_wr;
reg signed [`GPTT_TIME_W-1:0] ro_adjtime_delta_ns;
reg                    ro_adjfine_wr;
reg signed [31:0]      ro_adjfine_addend;
reg                    ro_servo_locked;

// ----- wire -----
wire [`GPTT_TIME_W-1:0] w_cf_ns;
wire signed [`GPTT_TIME_W-1:0] w_offset_nxt;
wire signed [63:0]             w_integ_sum;
wire signed [31:0]             w_freq_ppb;
wire                           w_is_converged;

// ----- assign -----
assign o_adjtime_wr       = ro_adjtime_wr;
assign o_adjtime_delta_ns = ro_adjtime_delta_ns;
assign o_adjfine_wr       = ro_adjfine_wr;
assign o_adjfine_addend   = ro_adjfine_addend;
assign o_servo_locked     = ro_servo_locked;
assign w_cf_ns       = i_cf_ns >> `CF_FRAC_W;
assign w_offset_nxt  = (i_t1_gm_ns + w_cf_ns) - i_t2_local_ns;
assign w_integ_sum   = r_integ + w_offset_nxt;
assign w_freq_ppb    = r_integ >>> Ki_Q;
assign w_is_converged= (r_offset < 50) && (r_offset > -50);

// ----- FSM -----
// 状态常量 (独热码)
parameter P_ST_IDLE = 3'b001;
parameter P_ST_CALC = 3'b010;
parameter P_ST_OUT  = 3'b100;
reg [2:0] state_c;
reg [2:0] state_n;

// 状态跳转条件 (独立 wire)
wire p_st_idle2p_st_calc_start = (state_c==P_ST_IDLE) && i_sync_rx;
wire p_st_calc2p_st_out_start  = (state_c==P_ST_CALC) && 1'b1;
wire p_st_out2p_st_idle_start  = (state_c==P_ST_OUT)  && 1'b1;

// ----- inst -----
// (本模块无实例化)

// ----- combine_Logic -----
// 次态计算 (仅 case, default -> P_ST_IDLE)
always @* begin
    case (state_c)
        P_ST_IDLE: if (p_st_idle2p_st_calc_start) state_n = P_ST_CALC; else state_n = state_c;
        P_ST_CALC: if (p_st_calc2p_st_out_start)  state_n = P_ST_OUT;  else state_n = state_c;
        P_ST_OUT:  if (p_st_out2p_st_idle_start)  state_n = P_ST_IDLE; else state_n = state_c;
        default:   state_n = P_ST_IDLE;
    endcase
end

// ----- always -----
// 状态寄存器 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        state_c <= 'd0;
    else
        state_c <= state_n;
end

// offset 锁存 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_offset <= 'd0;
    else if (state_c==P_ST_CALC)
        r_offset <= w_offset_nxt;
    else
        r_offset <= r_offset;
end

// 积分累加 + 限幅 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_integ <= 'd0;
    else if (state_c==P_ST_CALC) begin
        if (w_integ_sum >  64'sd1000000)      r_integ <=  64'sd1000000;
        else if (w_integ_sum < -64'sd1000000) r_integ <= -64'sd1000000;
        else                                  r_integ <= w_integ_sum;
    end else
        r_integ <= r_integ;
end

// 频率修正 ppb (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_freq_ppb <= 'd0;
    else if (state_c==P_ST_OUT)
        r_freq_ppb <= w_freq_ppb;
    else
        r_freq_ppb <= r_freq_ppb;
end

// adjtime 写脉冲 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_adjtime_wr <= 'd0;
    else if (state_c==P_ST_OUT)
        ro_adjtime_wr <= 1'b1;
    else
        ro_adjtime_wr <= 1'b0;
end

// adjtime 相位修正量 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_adjtime_delta_ns <= 'd0;
    else if (state_c==P_ST_OUT)
        ro_adjtime_delta_ns <= r_offset;
    else
        ro_adjtime_delta_ns <= ro_adjtime_delta_ns;
end

// adjfine 写脉冲 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_adjfine_wr <= 'd0;
    else if (state_c==P_ST_OUT)
        ro_adjfine_wr <= 1'b1;
    else
        ro_adjfine_wr <= 1'b0;
end

// adjfine 加数 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_adjfine_addend <= ADDFINE_CENTER;
    else if (state_c==P_ST_OUT)
        ro_adjfine_addend <= ADDFINE_CENTER + w_freq_ppb;
    else
        ro_adjfine_addend <= ro_adjfine_addend;
end

// 收敛指示 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_servo_locked <= 'd0;
    else if (state_c==P_ST_OUT)
        ro_servo_locked <= w_is_converged;
    else
        ro_servo_locked <= ro_servo_locked;
end

endmodule
