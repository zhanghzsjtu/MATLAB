/////////////////////////////////////////////////////////////////
// Copyright (c) 2026 local TSN gPTP port (based on OpenTSN RX_PROC/TX_PROC)
// 模块: gptp_mac_glue  —  MAC 接口胶合 + PTP 报文解析/组包
// 功能: 收方向解析 PTP 帧产生 SOF/EOF/event 给 HTSU; 发方向按字节
//       改写 correctionField (帧偏移 22~29) 后透传其余字节。
// 规范: 端口对齐 / 分组注释 / r_w_ro 前缀 / state_c-state_n / P_ST_ 独热 /
//       跳转条件独立 wire / 三段式 / i_clk-i_rst / posedge i_rst / 'd0。
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "gptp_defines.v"

module gptp_mac_glue #(
    parameter PORT_ID = 4'd0
)(
    // ---- 系统时钟/复位 ----
    input  wire                     i_clk,
    input  wire                     i_rst,

    // ---- MAC RX 字节流 ----
    input  wire [7:0]               i_rx_data,
    input  wire                     i_rx_vld,
    input  wire                     i_rx_sop,
    input  wire                     i_rx_eop,

    // ---- MAC TX 字节流 ----
    output wire [7:0]               o_tx_data,
    output wire                     o_tx_vld,
    output wire                     o_tx_sop,
    output wire                     o_tx_eop,
    input  wire                     i_tx_rdy,

    // ---- 给 HTSU 的边沿/类型 ----
    output wire                     o_rx_sof,
    output wire                     o_rx_eof,
    output wire                     o_is_event_pkt,
    output wire [3:0]               o_msg_type,
    output wire                     o_tx_is_event_pkt,

    // ---- correctionField 改写接口 ----
    input  wire [63:0]              i_cf_new,
    input  wire                     i_cf_wr,
    output wire                     o_cf_wr_done
);

// ----- param -----
localparam OFF_ET     = 12;   // ET 高字节位置
localparam OFF_MSG    = 14;   // msgType 字节位置
localparam OFF_CF_LO  = 22;   // correctionField 首字节 (帧偏移)
localparam OFF_CF_HI  = 29;   // correctionField 末字节 (帧偏移)

// ----- reg -----
reg [7:0]  r_byte_cnt;
reg        r_is_ptp;
reg [3:0]  r_msg_type;
reg [7:0]  r_tx_byte_cnt;
reg        r_tx_cf_active;
reg [63:0] r_cf_hold;
reg        r_cf_pending;
reg        r_tx_in_frame;
reg        r_tx_event;
reg        ro_rx_sof;
reg        ro_rx_eof;
reg        ro_is_event_pkt;
reg [3:0]  ro_msg_type;
reg        ro_cf_wr_done;

// ----- wire -----
wire [7:0] w_cf_byte;
wire       w_in_cf_zone;
wire [2:0] w_cf_idx;
// 字节计数下一值 (组合): 所有判决块统一用此值, 避免多 always 块间
// 非阻塞赋值 1 拍延迟导致的 r_byte_cnt 错位 (ET/msgType 偏移匹配失败)。
wire [7:0] w_byte_cnt_nxt = i_rx_sop ? 8'd0 : (i_rx_vld ? (r_byte_cnt + 8'd1) : r_byte_cnt);

// ----- assign -----
assign o_rx_sof        = ro_rx_sof;
assign o_rx_eof        = ro_rx_eof;
assign o_is_event_pkt  = ro_is_event_pkt;
assign o_msg_type      = ro_msg_type;
assign o_tx_is_event_pkt = r_tx_event;
assign o_cf_wr_done    = ro_cf_wr_done;
// TX 默认透传, CF 区间替换为 r_cf_hold 对应字节
assign w_cf_idx    = r_tx_byte_cnt - OFF_CF_LO;
assign w_in_cf_zone= r_tx_cf_active && i_rx_vld && r_tx_in_frame &&
                     (r_tx_byte_cnt >= OFF_CF_LO) && (r_tx_byte_cnt <= OFF_CF_HI);
assign w_cf_byte   = (w_cf_idx == 3'd0) ? r_cf_hold[ 7: 0] :
                     (w_cf_idx == 3'd1) ? r_cf_hold[15: 8] :
                     (w_cf_idx == 3'd2) ? r_cf_hold[23:16] :
                     (w_cf_idx == 3'd3) ? r_cf_hold[31:24] :
                     (w_cf_idx == 3'd4) ? r_cf_hold[39:32] :
                     (w_cf_idx == 3'd5) ? r_cf_hold[47:40] :
                     (w_cf_idx == 3'd6) ? r_cf_hold[55:48] :
                                           r_cf_hold[63:56];
assign o_tx_data = w_in_cf_zone ? w_cf_byte : i_rx_data;
assign o_tx_vld  = i_rx_vld;
assign o_tx_sop  = i_rx_sop;
assign o_tx_eop  = i_rx_eop;

// ----- FSM -----
// RX 解析状态常量 (独热码)
parameter P_ST_RX_IDLE = 3'b001;
parameter P_ST_RX_HDR  = 3'b010;
parameter P_ST_RX_BODY = 3'b100;
reg [2:0] state_c;
reg [2:0] state_n;

// 状态跳转条件 (独立 wire)
wire p_st_rx_idle2p_st_rx_hdr_start  = (state_c==P_ST_RX_IDLE) && i_rx_vld && i_rx_sop;
wire p_st_rx_hdr2p_st_rx_idle_start  = (state_c==P_ST_RX_HDR)  && i_rx_vld && i_rx_eop;
wire p_st_rx_hdr2p_st_rx_body_start  = (state_c==P_ST_RX_HDR)  && i_rx_vld && !i_rx_eop && (r_byte_cnt >= OFF_MSG);
wire p_st_rx_body2p_st_rx_idle_start = (state_c==P_ST_RX_BODY) && i_rx_eop;

// ----- inst -----
// (本模块无实例化)

// ----- combine_Logic -----
// 次态计算 (仅 case, default -> P_ST_RX_IDLE)
always @* begin
    case (state_c)
        P_ST_RX_IDLE: if (p_st_rx_idle2p_st_rx_hdr_start)  state_n = P_ST_RX_HDR;  else state_n = state_c;
        P_ST_RX_HDR:  if (p_st_rx_hdr2p_st_rx_idle_start)  state_n = P_ST_RX_IDLE; else
                      if (p_st_rx_hdr2p_st_rx_body_start)  state_n = P_ST_RX_BODY; else state_n = state_c;
        P_ST_RX_BODY: if (p_st_rx_body2p_st_rx_idle_start) state_n = P_ST_RX_IDLE; else state_n = state_c;
        default:      state_n = P_ST_RX_IDLE;
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

// 字节计数 (单信号): 组合下一值 (w_byte_cnt_nxt), 所有判决块统一用此值,
// 以补偿 FIFO 读侧一拍延迟, 使 ET/msgType 偏移在经 FIFO 的级联路径下仍正确。
// 无 FIFO 的直接激励 (tb_gptp_mac_glue) 通过 b 偏移适配。
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_byte_cnt <= 'd0;
    else
        r_byte_cnt <= w_byte_cnt_nxt;
end

// 是否 PTP 帧 (单信号): 统一用 w_byte_cnt_nxt 判决
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_is_ptp <= 'd0;
    else if (i_rx_vld && i_rx_sop)
        r_is_ptp <= 1'b0;
    else if (i_rx_vld && (w_byte_cnt_nxt==OFF_ET)   && (i_rx_data==8'h88))
        r_is_ptp <= 1'b1;
    else if (i_rx_vld && (w_byte_cnt_nxt==(OFF_ET+1)) && (i_rx_data==8'hF7))
        r_is_ptp <= r_is_ptp;
    else
        r_is_ptp <= r_is_ptp;
end

// msgType 锁存 (单信号): 统一用 w_byte_cnt_nxt 判决
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_msg_type <= 'd0;
    else if (i_rx_vld && (w_byte_cnt_nxt==OFF_MSG))
        r_msg_type <= i_rx_data[3:0];
    else
        r_msg_type <= r_msg_type;
end

// SOF 脉冲 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_rx_sof <= 'd0;
    else if (i_rx_vld && i_rx_sop)
        ro_rx_sof <= 1'b1;
    else
        ro_rx_sof <= 1'b0;
end

// EOF 脉冲 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_rx_eof <= 'd0;
    else if (i_rx_vld && i_rx_eop)
        ro_rx_eof <= 1'b1;
    else
        ro_rx_eof <= 1'b0;
end

// 解析出的 msgType 输出 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_msg_type <= 'd0;
    else if (i_rx_vld && (w_byte_cnt_nxt==OFF_MSG))
        ro_msg_type <= i_rx_data[3:0];
    else
        ro_msg_type <= ro_msg_type;
end

// 是否 event 报文 (帧级标志): sop 时预判 r_is_ptp, msgType 字节时锁定
// event 类型; 锁定后持续到 eop。输出供 HTSU 在整个帧期间判定 (否则
// HTSU 的 rx_sof 与 msgType 不在同一拍, 状态机无法进入 event 分支)。
reg r_event_frame;
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_event_frame <= 'd0;
    else if (i_rx_vld && i_rx_sop)
        r_event_frame <= 1'b0;
    else if (i_rx_vld && (w_byte_cnt_nxt==OFF_MSG))
        r_event_frame <= r_is_ptp &&
                           ((i_rx_data[3:0]==`MT_SYNC) ||
                            (i_rx_data[3:0]==`MT_PDELAY_REQ) ||
                            (i_rx_data[3:0]==`MT_PDELAY_RESP) ||
                            (i_rx_data[3:0]==`MT_FOLLOW_UP));
    else if (i_rx_vld && i_rx_eop)
        r_event_frame <= 1'b0;
    else
        r_event_frame <= r_event_frame;
end
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_is_event_pkt <= 'd0;
    else
        ro_is_event_pkt <= r_event_frame;
end

// CF 锁存 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_cf_hold <= 'd0;
    else if (i_cf_wr)
        r_cf_hold <= i_cf_new;
    else
        r_cf_hold <= r_cf_hold;
end

// 待写 CF 标志 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_cf_pending <= 'd0;
    else if (i_cf_wr)
        r_cf_pending <= 1'b1;
    else if (i_rx_vld && i_rx_sop && r_cf_pending)
        r_cf_pending <= 1'b0;
    else
        r_cf_pending <= r_cf_pending;
end

// CF 改写完成标志 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_cf_wr_done <= 'd0;
    else if (i_rx_vld && i_rx_sop && r_cf_pending)
        ro_cf_wr_done <= 1'b1;
    else
        ro_cf_wr_done <= 1'b0;
end

// TX 出帧字节计数 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_tx_byte_cnt <= 'd0;
    else if (i_rx_vld && i_rx_sop)
        r_tx_byte_cnt <= 'd0;
    else if (i_rx_vld && r_tx_in_frame)
        r_tx_byte_cnt <= r_tx_byte_cnt + 8'd1;
    else
        r_tx_byte_cnt <= r_tx_byte_cnt;
end

// TX 帧内标志 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_tx_in_frame <= 'd0;
    else if (i_rx_vld && i_rx_sop)
        r_tx_in_frame <= 1'b1;
    else if (i_rx_vld && i_rx_eop)
        r_tx_in_frame <= 1'b0;
    else
        r_tx_in_frame <= r_tx_in_frame;
end

// TX 侧 event 帧标志 (单信号): 收帧识别出 event 后锁存, 持续到 TX eop。
// 供 TC 在发帧期间 (residence 已算出后) 改写 CF, 而非收帧期间 (residence 尚为 0)。
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_tx_event <= 'd0;
    else if (r_event_frame && i_rx_vld && i_rx_eop)
        r_tx_event <= 1'b1;
    else if (i_rx_vld && i_rx_eop && r_tx_in_frame)
        r_tx_event <= 1'b0;
    else
        r_tx_event <= r_tx_event;
end

// TX CF 改写区间激活 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_tx_cf_active <= 'd0;
    else if (i_rx_vld && i_rx_sop && r_cf_pending)
        r_tx_cf_active <= 1'b1;
    else if (i_rx_vld && i_rx_eop)
        r_tx_cf_active <= 1'b0;
    else
        r_tx_cf_active <= r_tx_cf_active;
end

endmodule
