/////////////////////////////////////////////////////////////////
// Copyright (c) 2026 local TSN gPTP port (based on OpenTSN PTP_CTRL/RX_PROC)
// 模块: gptp_htsu  —  硬件时间戳单元 (HTSU, Hardware TimeStamp Unit)
// 功能: 在 MAC wire-side (SOF/EOF 边沿) 对 PTP event 报文打标,
//       捕获进出时间戳 t2(收)/t3(出) 与驻留时间 residence = t3 - t2。
// 规范: 端口对齐 / 分组注释 / r_w_ro 前缀 / state_c-state_n / P_ST_ 独热 /
//       跳转条件独立 wire / 三段式 / posedge i_rst / 'd0 / 单信号 always。
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "gptp_defines.v"

module gptp_htsu #(
    parameter PORT_ID = 4'd0
)(
    // ---- 时钟/复位 (与 PHC 同域) ----
    input  wire                         i_clk,
    input  wire                         i_rst,

    // ---- PHC 时间输入 (连续) ----
    input  wire [`GPTT_TIME_W-1:0]      i_phc_time_ns,
    input  wire [31:0]                  i_phc_time_frac,

    // ---- MAC wire-side 边沿 ----
    input  wire                         i_rx_sof,        // 收帧起始
    input  wire                         i_rx_eof,        // 收帧结束
    input  wire                         i_tx_sof,
    input  wire                         i_tx_eof,
    input  wire                         i_is_event_pkt,  // 当前帧为 event 报文

    // ---- 输出: 进出时间戳 + 驻留时间 ----
    output wire [`GPTT_TIME_W-1:0]      o_rx_ts_ns,
    output wire [31:0]                  o_rx_ts_frac,
    output wire [`GPTT_TIME_W-1:0]      o_tx_ts_ns,
    output wire [31:0]                  o_tx_ts_frac,
    output wire [`GPTT_TIME_W-1:0]      o_residence_ns,
    output wire                         o_residence_vld
);

// ----- param -----
// (本模块无 parameter; 状态常量见 FSM 组)

// ----- reg -----
reg [`GPTT_TIME_W-1:0] r_rx_cap_ns;
reg [31:0]             r_rx_cap_frac;
reg [`GPTT_TIME_W-1:0] r_tx_cap_ns;
reg [31:0]             r_tx_cap_frac;
reg                    r_event_latch;
reg [`GPTT_TIME_W-1:0] ro_rx_ts_ns;
reg [31:0]             ro_rx_ts_frac;
reg [`GPTT_TIME_W-1:0] ro_tx_ts_ns;
reg [31:0]             ro_tx_ts_frac;
reg [`GPTT_TIME_W-1:0] ro_residence_ns;
reg                    ro_residence_vld;

// ----- wire -----
wire [`GPTT_TIME_W-1:0] w_residence_calc;

// ----- assign -----
assign o_rx_ts_ns     = ro_rx_ts_ns;
assign o_rx_ts_frac   = ro_rx_ts_frac;
assign o_tx_ts_ns     = ro_tx_ts_ns;
assign o_tx_ts_frac   = ro_tx_ts_frac;
assign o_residence_ns = ro_residence_ns;
assign o_residence_vld= ro_residence_vld;
assign w_residence_calc = r_tx_cap_ns - r_rx_cap_ns;

// ----- FSM -----
// 状态常量 (独热码)
parameter P_ST_IDLE = 4'b0001;
parameter P_ST_RX   = 4'b0010;
parameter P_ST_WAIT = 4'b0100;
parameter P_ST_TX   = 4'b1000;
reg [3:0] state_c;
reg [3:0] state_n;

// 状态跳转条件 (独立 wire, 命名 p_st_<src>2p_st_<dst>_start)
// 注: 进入 P_ST_RX 仅判 rx_sof (不判 event, 因 msgType 在帧中段才解析);
//     event 标志在 P_ST_RX 内由 i_is_event_pkt 锁存 (r_event_latch)。
//     WAIT 期间新 rx_sof 直接进 RX (接管新帧, 弃前一帧), 避免跨拍死锁。
wire p_st_idle2p_st_rx_start   = (state_c==P_ST_IDLE) && i_rx_sof;
wire p_st_rx2p_st_wait_start   = (state_c==P_ST_RX)   && i_rx_eof;
wire p_st_wait2p_st_tx_start   = (state_c==P_ST_WAIT) && i_tx_sof && r_event_latch;
wire p_st_wait2p_st_rx_start   = (state_c==P_ST_WAIT) && i_rx_sof;
wire p_st_tx2p_st_idle_start   = (state_c==P_ST_TX) && (i_tx_eof || i_rx_sof);

// ----- inst -----
// (本模块无实例化)

// ----- combine_Logic -----
// 次态计算 (仅 case 语句, default -> P_ST_IDLE)
always @* begin
    case (state_c)
        P_ST_IDLE: if (p_st_idle2p_st_rx_start)   state_n = P_ST_RX;   else state_n = state_c;
        P_ST_RX:   if (p_st_rx2p_st_wait_start)   state_n = P_ST_WAIT; else state_n = state_c;
        P_ST_WAIT: if (p_st_wait2p_st_tx_start)   state_n = P_ST_TX;
                   else if (p_st_wait2p_st_rx_start) state_n = P_ST_RX;
                   else state_n = state_c;
        P_ST_TX:   if (p_st_tx2p_st_idle_start)   state_n = P_ST_IDLE; else state_n = state_c;
        default:   state_n = P_ST_IDLE;
    endcase
end

// ----- always -----
// 状态寄存器 (仅更新 state_c)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        state_c <= 'd0;
    else
        state_c <= state_n;
end

// 收帧 t2 纳秒锁存 (单信号): 在 P_ST_RX 期间若本帧为 event 报文, 锁存 PHC 时间。
// 非 event 帧不锁存 t2 (单元 tb 检查1 期望 ro_rx_ts_ns=0)。
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_rx_cap_ns <= 'd0;
    else if ((state_c==P_ST_RX) && i_is_event_pkt)
        r_rx_cap_ns <= i_phc_time_ns;
    else
        r_rx_cap_ns <= r_rx_cap_ns;
end

// 收帧 t2 分数锁存 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_rx_cap_frac <= 'd0;
    else if ((state_c==P_ST_RX) && i_is_event_pkt)
        r_rx_cap_frac <= i_phc_time_frac;
    else
        r_rx_cap_frac <= r_rx_cap_frac;
end

// 发帧 t3 纳秒锁存 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_tx_cap_ns <= 'd0;
    else if ((state_c==P_ST_WAIT) && i_tx_sof && r_event_latch)
        r_tx_cap_ns <= i_phc_time_ns;
    else
        r_tx_cap_ns <= r_tx_cap_ns;
end

// 发帧 t3 分数锁存 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_tx_cap_frac <= 'd0;
    else if ((state_c==P_ST_WAIT) && i_tx_sof && r_event_latch)
        r_tx_cap_frac <= i_phc_time_frac;
    else
        r_tx_cap_frac <= r_tx_cap_frac;
end

// event 锁存 (单信号): 在 P_ST_RX 期间 (msgType 已解析) 锁存 event 标志,
// 用于 P_ST_WAIT->P_ST_TX 判定; P_ST_TX 收尾 (tx_eof) 时清零。
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_event_latch <= 'd0;
    else if ((state_c==P_ST_RX) && i_is_event_pkt)
        r_event_latch <= 1'b1;
    else if ((state_c==P_ST_TX) && i_tx_eof && r_event_latch)
        r_event_latch <= 1'b0;
    else
        r_event_latch <= r_event_latch;
end

// 输出 rx ts ns (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_rx_ts_ns <= 'd0;
    else if ((state_c==P_ST_TX) && i_tx_eof && r_event_latch)
        ro_rx_ts_ns <= r_rx_cap_ns;
    else
        ro_rx_ts_ns <= ro_rx_ts_ns;
end

// 输出 rx ts frac (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_rx_ts_frac <= 'd0;
    else if ((state_c==P_ST_TX) && i_tx_eof && r_event_latch)
        ro_rx_ts_frac <= r_rx_cap_frac;
    else
        ro_rx_ts_frac <= ro_rx_ts_frac;
end

// 输出 tx ts ns (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_tx_ts_ns <= 'd0;
    else if ((state_c==P_ST_TX) && i_tx_eof && r_event_latch)
        ro_tx_ts_ns <= r_tx_cap_ns;
    else
        ro_tx_ts_ns <= ro_tx_ts_ns;
end

// 输出 tx ts frac (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_tx_ts_frac <= 'd0;
    else if ((state_c==P_ST_TX) && i_tx_eof && r_event_latch)
        ro_tx_ts_frac <= r_tx_cap_frac;
    else
        ro_tx_ts_frac <= ro_tx_ts_frac;
end

// 输出 residence ns (单信号): 在 P_ST_TX 期间 (发帧 CF 域字节到达时)
// 用已锁存的 t3 - t2 实时输出, 保证 TC 在改写 CF 时 residence 已非零。
// 注: 不在 tx_eof 才计算, 否则 CF 域字节 (tx_eof 前) 到达时 residence 仍为 0。
// 出帧后保持锁存值 (不清零), 供上层/测试在帧结束后读取。
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_residence_ns <= 'd0;
    else if ((state_c==P_ST_TX) && r_event_latch)
        ro_residence_ns <= r_tx_cap_ns - r_rx_cap_ns;
    else
        ro_residence_ns <= ro_residence_ns;
end

// 输出 residence valid 脉冲 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_residence_vld <= 'd0;
    else if ((state_c==P_ST_TX) && r_event_latch)
        ro_residence_vld <= 1'b1;
    else
        ro_residence_vld <= 1'b0;
end

endmodule
