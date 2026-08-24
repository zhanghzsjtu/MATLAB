/////////////////////////////////////////////////////////////////
// Copyright (c) 2026 local TSN gPTP port (based on OpenTSN Manage_CTRL)
// 模块: gptp_bmca  —  802.1AS 最佳主时钟选举 (BMCA, 简化版)
// 功能: 比较本地与对端 Announce 优先级向量, 决定本端口 role:
//       Master / Slave / Passive。Passive 判定基于 stepsRemoved 比较。
// 规范: 端口对齐 / 分组注释 / r_w_ro 前缀 / state_c-state_n / P_ST_ 独热 /
//       跳转条件独立 wire / 三段式 / i_clk-i_rst / posedge i_rst / 'd0。
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "gptp_defines.v"

module gptp_bmca #(
    parameter PORT_ID        = 4'd0,
    parameter PRIORITY1      = 8'd128,
    parameter PRIORITY2      = 8'd128,
    parameter [63:0] CLOCK_IDENTITY = 64'd0
)(
    // ---- 时钟/复位 ----
    input  wire                         i_clk,
    input  wire                         i_rst,

    // ---- 本地端口优先级向量 ----
    input  wire [7:0]               i_local_priority1,
    input  wire [63:0]              i_local_clock_id,
    input  wire [7:0]               i_local_priority2,
    input  wire [15:0]              i_local_steps_removed,

    // ---- 对端 Announce 优先级向量 ----
    input  wire                     i_announce_rx,
    input  wire [7:0]               i_rem_priority1,
    input  wire [63:0]              i_rem_clock_id,
    input  wire [7:0]               i_rem_priority2,
    input  wire [15:0]              i_rem_steps_removed,
    input  wire [63:0]              i_rem_port_id,

    // ---- 角色输出 ----
    output wire [1:0]               o_port_role,   // 00=Master 01=Slave 10=Passive
    output wire                     o_role_vld,
    output wire                     o_is_gm
);

// ----- param -----
localparam [1:0] ROLE_MASTER  = 2'd0;
localparam [1:0] ROLE_SLAVE   = 2'd1;
localparam [1:0] ROLE_PASSIVE = 2'd2;

// ----- reg -----
reg [1:0] r_role_nxt;
reg       r_is_gm_nxt;
reg [1:0] r_cmp_latch;
reg [1:0] ro_port_role;
reg       ro_role_vld;
reg       ro_is_gm;

// ----- wire -----
wire [1:0] w_cmp;   // 00=本地 01=对端 10=相等

// ----- assign -----
assign o_port_role = ro_port_role;
assign o_role_vld  = ro_role_vld;
assign o_is_gm     = ro_is_gm;

// ----- FSM -----
// 状态常量 (独热码)
parameter P_ST_IDLE = 3'b001;
parameter P_ST_CMP  = 3'b010;
parameter P_ST_DONE = 3'b100;
reg [2:0] state_c;
reg [2:0] state_n;

// 状态跳转条件 (独立 wire)
wire p_st_idle2p_st_cmp_start  = (state_c==P_ST_IDLE) && i_announce_rx;
wire p_st_cmp2p_st_done_start  = (state_c==P_ST_CMP)  && 1'b1;
wire p_st_done2p_st_idle_start = (state_c==P_ST_DONE) && 1'b1;

// ----- inst -----
// (本模块无实例化)

// ----- combine_Logic -----
// 优先级向量字典序比较 (单信号 wire)
assign w_cmp = (i_announce_rx) ?
               ( (i_local_priority1 != i_rem_priority1) ?
                   ( (i_local_priority1 < i_rem_priority1) ? 2'b00 : 2'b01 ) :
                 (i_local_clock_id != i_rem_clock_id) ?
                   ( (i_local_clock_id < i_rem_clock_id) ? 2'b00 : 2'b01 ) :
                 (i_local_priority2 != i_rem_priority2) ?
                   ( (i_local_priority2 < i_rem_priority2) ? 2'b00 : 2'b01 ) :
                   2'b10 ) : 2'b00;

// 次态计算 (仅 case, default -> P_ST_IDLE)
always @* begin
    case (state_c)
        P_ST_IDLE: if (p_st_idle2p_st_cmp_start)  state_n = P_ST_CMP;  else state_n = state_c;
        P_ST_CMP:  if (p_st_cmp2p_st_done_start)  state_n = P_ST_DONE; else state_n = state_c;
        P_ST_DONE: if (p_st_done2p_st_idle_start) state_n = P_ST_IDLE; else state_n = state_c;
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

// 比较结果锁存 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_cmp_latch <= 'd0;
    else if ((state_c==P_ST_IDLE) && i_announce_rx)
        r_cmp_latch <= w_cmp;
    else
        r_cmp_latch <= r_cmp_latch;
end

// 角色次态 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_role_nxt <= ROLE_MASTER;
    else if (state_c==P_ST_CMP) begin
        if (r_cmp_latch == 2'b01) begin
            // 对端优: stepsRemoved 差判定 Slave/Passive
            if (i_rem_steps_removed >= (i_local_steps_removed + 16'd1))
                r_role_nxt <= ROLE_PASSIVE;
            else
                r_role_nxt <= ROLE_SLAVE;
        end else
            r_role_nxt <= ROLE_MASTER;   // 本地优 / tie-break
    end else
        r_role_nxt <= r_role_nxt;
end

// 是否 GM 次态 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_is_gm_nxt <= 1'b1;
    else if (state_c==P_ST_CMP) begin
        if (r_cmp_latch == 2'b01)
            r_is_gm_nxt <= 1'b0;
        else
            r_is_gm_nxt <= 1'b1;
    end else
        r_is_gm_nxt <= r_is_gm_nxt;
end

// 角色输出 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_port_role <= ROLE_MASTER;
    else if (state_c==P_ST_DONE)
        ro_port_role <= r_role_nxt;
    else
        ro_port_role <= ro_port_role;
end

// 是否 GM 输出 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_is_gm <= 1'b1;
    else if (state_c==P_ST_DONE)
        ro_is_gm <= r_is_gm_nxt;
    else
        ro_is_gm <= ro_is_gm;
end

// 角色有效脉冲 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_role_vld <= 'd0;
    else if (state_c==P_ST_DONE)
        ro_role_vld <= 1'b1;
    else
        ro_role_vld <= 1'b0;
end

endmodule
