/////////////////////////////////////////////////////////////////
// Copyright (c) 2026 local TSN gPTP port (based on OpenTSN RX_PROC)
// 模块: gptp_frame_parser  —  PTP 报文解析 (GMII 字节流 -> 字段)
// 功能: 接收 MAC 侧 8-bit 字节流 + sof/eop/vld (已是 glue 使用的接口),
//       识别 0x88F7 以太网类型, 提取:
//         - msgType (PTP 头 byte0[3:0], DA 起算偏移 14)
//         - sequenceId (DA 起算偏移 40..41, 大端)
//         - correctionField (DA 起算偏移 22..29, 8 字节大端, 单位 ns<<CF_FRAC_W)
//         - originTimestamp 纳秒 (Follow_Up 专用, DA 起算偏移 48..51, 大端)
//       并在帧尾 EOF 产生按消息类型的 valid 脉冲, 供 Servo/BMCA 消费。
// 协议依据: IEEE 1588 / 802.1AS PTP 头布局 (DA(6)+SA(6)+ET(2)+PTP header)。
// 规范: 端口对齐 / 分组注释 / r_w_ro 前缀 / state_c-state_n / P_ST_ 独热 /
//       跳转条件独立 wire / 三段式 / i_clk-i_rst / posedge i_rst / 'd0。
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "gptp_defines.v"

module gptp_frame_parser #(
    parameter PORT_ID = 4'd0
)(
    // ---- 系统时钟/复位 ----
    input  wire                     i_clk,
    input  wire                     i_rst,

    // ---- MAC RX 字节流 (GMII 风格 8-bit, 已由 switch 做 CDC 同步) ----
    input  wire [7:0]               i_rx_data,
    input  wire                     i_rx_vld,
    input  wire                     i_rx_sop,
    input  wire                     i_rx_eop,

    // ---- 解析输出 (组合/打拍) ----
    output wire [3:0]               o_msg_type,        // 当前/最后解析的 msgType
    output wire [15:0]              o_seq_id,          // 当前帧 sequenceId
    output wire [63:0]              o_cf_ns,           // 解析出的 correctionField (ns<<CF_FRAC_W)
    output wire [`GPTT_TIME_W-1:0]  o_origin_ts_ns,    // Follow_Up 的 originTimestamp 纳秒

    // ---- 按消息类型的 EOF 脉冲 (帧结束时各闪一下) ----
    output wire                     o_sync_vld,        // msgType==SYNC
    output wire                     o_follow_up_vld,   // msgType==FOLLOW_UP
    output wire                     o_pdreq_vld,       // msgType==PDELAY_REQ
    output wire                     o_pdresp_vld,      // msgType==PDELAY_RESP
    output wire                     o_pdresfu_vld,     // msgType==PDELAY_RESP_FU
    output wire                     o_announce_vld,    // msgType==ANNOUNCE
    // ---- Announce 优先级向量 (BMCA 用) ----
    output wire [7:0]               o_ann_priority1,
    output wire [`GPTT_TIME_W-1:0]  o_ann_clock_id,
    output wire [7:0]               o_ann_priority2,
    output wire [15:0]              o_ann_steps_removed
);

// ----- param -----
// DA(6)+SA(6)=12; 之后 ET(2) 在偏移 12..13, PTP 头从偏移 14 起
// 注: byte_cnt 在首字节(SOP)被清零但不计入, 故实际采样偏移整体 -1 (byte[N] 出现在 cnt=N-1)
localparam OFF_ET       = 11;   // EtherType 高字节 (frame[12])
localparam OFF_MSG      = 13;   // msgType (frame[14])
localparam OFF_SEQ      = 39;   // sequenceId 首字节 (frame[40])
localparam OFF_CF_LO    = 21;   // correctionField 首字节 (frame[22])
localparam OFF_CF_HI    = 28;   // correctionField 末字节 (frame[29])
localparam OFF_ORIG_LO  = 47;   // originTimestamp 纳秒首字节 (frame[48])
localparam OFF_ORIG_HI  = 50;   // originTimestamp 纳秒末字节 (frame[51])

// ----- reg -----
reg [7:0]              r_byte_cnt;
reg                     r_is_ptp;
reg [3:0]              r_msg_type;
reg [15:0]             r_seq_id;
reg [63:0]             r_cf_hold;       // 已拼好的 CF
reg [`GPTT_TIME_W-1:0] r_orig_hold;     // 已拼好的 originTimestamp 纳秒
reg                     r_fu_seen;      // 本帧是否为 FU (用于 EOF 选择 origin)
reg [3:0]              ro_msg_type;
reg [15:0]             ro_seq_id;
reg [63:0]             ro_cf_ns;
reg [`GPTT_TIME_W-1:0] ro_origin_ts_ns;
reg                     ro_sync_vld;
reg                     ro_follow_up_vld;
reg                     ro_pdreq_vld;
reg                     ro_pdresp_vld;
reg                     ro_pdresfu_vld;
reg                     ro_announce_vld;
reg [7:0]               ro_ann_priority1;
reg [`GPTT_TIME_W-1:0]  ro_ann_clock_id;
reg [7:0]               ro_ann_priority2;
reg [15:0]              ro_ann_steps_removed;

// ----- wire -----
wire       w_is_eof;
wire [3:0] w_msg_hit;

// ----- assign -----
assign o_msg_type       = ro_msg_type;
assign o_seq_id         = ro_seq_id;
assign o_cf_ns          = ro_cf_ns;
assign o_origin_ts_ns   = ro_origin_ts_ns;
assign o_sync_vld       = ro_sync_vld;
assign o_follow_up_vld  = ro_follow_up_vld;
assign o_pdreq_vld      = ro_pdreq_vld;
assign o_pdresp_vld     = ro_pdresp_vld;
assign o_pdresfu_vld    = ro_pdresfu_vld;
assign o_announce_vld   = ro_announce_vld;
assign o_ann_priority1  = ro_ann_priority1;
assign o_ann_clock_id   = ro_ann_clock_id;
assign o_ann_priority2  = ro_ann_priority2;
assign o_ann_steps_removed = ro_ann_steps_removed;
assign w_is_eof         = i_rx_vld && i_rx_eop;

// 各消息类型命中 (用于 EOF 脉冲)
assign w_msg_hit = ro_msg_type;  // 锁存的 msgType 在 EOF 时有效

// ----- FSM -----
// 解析状态常量 (独热码)
parameter P_ST_IDLE = 3'b001;
parameter P_ST_HDR  = 3'b010;
parameter P_ST_BODY = 3'b100;
reg [2:0] state_c;
reg [2:0] state_n;

// 状态跳转条件 (独立 wire)
wire p_st_idle2p_st_hdr_start  = (state_c==P_ST_IDLE) && i_rx_vld && i_rx_sop;
wire p_st_hdr2p_st_idle_start  = (state_c==P_ST_HDR)  && w_is_eof;
wire p_st_hdr2p_st_body_start  = (state_c==P_ST_HDR)  && i_rx_vld && !i_rx_eop && (r_byte_cnt > OFF_MSG);
wire p_st_body2p_st_idle_start = (state_c==P_ST_BODY) && w_is_eof;

// ----- inst -----
// (本模块无实例化)

// ----- combine_Logic -----
// 次态计算 (仅 case, default -> P_ST_IDLE)
always @* begin
    case (state_c)
        P_ST_IDLE: if (p_st_idle2p_st_hdr_start) state_n = P_ST_HDR;  else state_n = state_c;
        P_ST_HDR:  if (p_st_hdr2p_st_idle_start) state_n = P_ST_IDLE;
                   else if (p_st_hdr2p_st_body_start) state_n = P_ST_BODY;
                   else state_n = state_c;
        P_ST_BODY: if (p_st_body2p_st_idle_start) state_n = P_ST_IDLE; else state_n = state_c;
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

// 字节计数 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_byte_cnt <= 'd0;
    else if (i_rx_vld && i_rx_sop)
        r_byte_cnt <= 'd0;
    else if (i_rx_vld)
        r_byte_cnt <= r_byte_cnt + 8'd1;
    else
        r_byte_cnt <= r_byte_cnt;
end

// 是否 PTP 帧 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_is_ptp <= 'd0;
    else if (i_rx_vld && i_rx_sop)
        r_is_ptp <= 1'b0;
    else if (i_rx_vld && (r_byte_cnt==OFF_ET)   && (i_rx_data==8'h88))
        r_is_ptp <= 1'b1;
    else if (i_rx_vld && (r_byte_cnt==OFF_ET+1) && (i_rx_data==8'hF7))
        r_is_ptp <= r_is_ptp;
    else
        r_is_ptp <= r_is_ptp;
end

// msgType 锁存 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_msg_type <= 'd0;
    else if (i_rx_vld && (r_byte_cnt==OFF_MSG))
        r_msg_type <= i_rx_data[3:0];
    else
        r_msg_type <= r_msg_type;
end

// sequenceId 拼装 (单信号): 偏移 40 为高位, 41 为低位 (大端)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_seq_id <= 'd0;
    else if (i_rx_vld && (r_byte_cnt==OFF_SEQ))
        r_seq_id[15:8] <= i_rx_data;
    else if (i_rx_vld && (r_byte_cnt==OFF_SEQ+1))
        r_seq_id[7:0]  <= i_rx_data;
    else
        r_seq_id <= r_seq_id;
end

// correctionField 拼装 (单信号): 偏移 22..29, 字节顺序保持大端原值
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_cf_hold <= 'd0;
    else if (i_rx_vld && (r_byte_cnt==OFF_CF_LO))
        r_cf_hold[63:56] <= i_rx_data;
    else if (i_rx_vld && (r_byte_cnt==OFF_CF_LO+1))
        r_cf_hold[55:48] <= i_rx_data;
    else if (i_rx_vld && (r_byte_cnt==OFF_CF_LO+2))
        r_cf_hold[47:40] <= i_rx_data;
    else if (i_rx_vld && (r_byte_cnt==OFF_CF_LO+3))
        r_cf_hold[39:32] <= i_rx_data;
    else if (i_rx_vld && (r_byte_cnt==OFF_CF_LO+4))
        r_cf_hold[31:24] <= i_rx_data;
    else if (i_rx_vld && (r_byte_cnt==OFF_CF_LO+5))
        r_cf_hold[23:16] <= i_rx_data;
    else if (i_rx_vld && (r_byte_cnt==OFF_CF_LO+6))
        r_cf_hold[15:8]  <= i_rx_data;
    else if (i_rx_vld && (r_byte_cnt==OFF_CF_LO+7))
        r_cf_hold[7:0]   <= i_rx_data;
    else
        r_cf_hold <= r_cf_hold;
end

// originTimestamp 纳秒拼装 (单信号): 仅 Follow_Up 携带, 偏移 48..51 大端
// 字段本身为 32 位纳秒值, 拼接到 r_orig_hold 的低 32 位 [31:0]
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_orig_hold <= 'd0;
    else if (i_rx_vld && (r_byte_cnt==OFF_ORIG_LO))
        r_orig_hold[31:24] <= i_rx_data;
    else if (i_rx_vld && (r_byte_cnt==OFF_ORIG_LO+1))
        r_orig_hold[23:16] <= i_rx_data;
    else if (i_rx_vld && (r_byte_cnt==OFF_ORIG_LO+ 2))
        r_orig_hold[15:8]  <= i_rx_data;
    else if (i_rx_vld && (r_byte_cnt==OFF_ORIG_LO+ 3))
        r_orig_hold[7:0]   <= i_rx_data;
    else
        r_orig_hold <= r_orig_hold;
end

// Follow_Up 标记 (单信号): 仅当本帧是 FU 时, EOF 输出 origin
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_fu_seen <= 'd0;
    else if (i_rx_vld && (r_byte_cnt==OFF_MSG) && (i_rx_data[3:0]==`MT_FOLLOW_UP))
        r_fu_seen <= 1'b1;
    else if (w_is_eof)
        r_fu_seen <= 1'b0;
    else
        r_fu_seen <= r_fu_seen;
end

// Announce 优先级向量拼装 (单信号): P1@33, CID@34-41(大端), P2@42, Steps@43-44
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_ann_priority1 <= 'd0;
    else if (i_rx_vld && (r_byte_cnt==33))
        ro_ann_priority1 <= i_rx_data;
    else
        ro_ann_priority1 <= ro_ann_priority1;
end
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_ann_clock_id <= 'd0;
    else if (i_rx_vld && (r_byte_cnt>=34) && (r_byte_cnt<=41))
        ro_ann_clock_id <= {ro_ann_clock_id[55:0], i_rx_data};
    else
        ro_ann_clock_id <= ro_ann_clock_id;
end
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_ann_priority2 <= 'd0;
    else if (i_rx_vld && (r_byte_cnt==42))
        ro_ann_priority2 <= i_rx_data;
    else
        ro_ann_priority2 <= ro_ann_priority2;
end
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_ann_steps_removed <= 'd0;
    else if (i_rx_vld && (r_byte_cnt==43))
        ro_ann_steps_removed[15:8] <= i_rx_data;
    else if (i_rx_vld && (r_byte_cnt==44))
        ro_ann_steps_removed[7:0]  <= i_rx_data;
    else
        ro_ann_steps_removed <= ro_ann_steps_removed;
end

// 输出打拍: msgType / seqId / cf / origin (单信号批量, 每信号独立 always)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_msg_type <= 'd0;
    else if (i_rx_vld && (r_byte_cnt==OFF_MSG))
        ro_msg_type <= i_rx_data[3:0];
    else
        ro_msg_type <= ro_msg_type;
end

always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_seq_id <= 'd0;
    else
        ro_seq_id <= r_seq_id;
end

always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_cf_ns <= 'd0;
    else if (w_is_eof)
        ro_cf_ns <= r_cf_hold;
    else
        ro_cf_ns <= ro_cf_ns;
end

always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_origin_ts_ns <= 'd0;
    else if (w_is_eof && r_fu_seen)
        ro_origin_ts_ns <= r_orig_hold;
    else if (w_is_eof)
        ro_origin_ts_ns <= 'd0;   // 非 FU 帧不携带真实 origin
    else
        ro_origin_ts_ns <= ro_origin_ts_ns;
end

// EOF 各消息类型脉冲 (单信号集合并: 用单个 always 逐个 if, 保持单信号约束)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst) begin
        ro_sync_vld      <= 1'b0;
        ro_follow_up_vld <= 1'b0;
        ro_pdreq_vld     <= 1'b0;
        ro_pdresp_vld    <= 1'b0;
        ro_pdresfu_vld   <= 1'b0;
        ro_announce_vld  <= 1'b0;
    end
    else if (w_is_eof) begin
        ro_sync_vld      <= (r_is_ptp && (w_msg_hit==`MT_SYNC));
        ro_follow_up_vld <= (r_is_ptp && (w_msg_hit==`MT_FOLLOW_UP));
        ro_pdreq_vld     <= (r_is_ptp && (w_msg_hit==`MT_PDELAY_REQ));
        ro_pdresp_vld    <= (r_is_ptp && (w_msg_hit==`MT_PDELAY_RESP));
        ro_pdresfu_vld   <= (r_is_ptp && (w_msg_hit==`MT_PDELAY_RESP_FU));
        ro_announce_vld  <= (r_is_ptp && (w_msg_hit==`MT_ANNOUNCE));
    end
    else begin
        ro_sync_vld      <= 1'b0;
        ro_follow_up_vld <= 1'b0;
        ro_pdreq_vld     <= 1'b0;
        ro_pdresp_vld    <= 1'b0;
        ro_pdresfu_vld   <= 1'b0;
        ro_announce_vld  <= 1'b0;
    end
end

endmodule
