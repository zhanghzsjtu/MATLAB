/////////////////////////////////////////////////////////////////
// Copyright (c) 2026 local TSN gPTP port (Sync/Follow_Up generator)
// 模块: gptp_tx_gen  —  GM/owner 端口同步报文生成器
// 功能: 当本端口被仲裁为 owner(GM) 时, 周期性主动构造并发送
//       Sync 帧 (originTimestamp = 当前 PHC 时间 t1) 与 Follow_Up 帧,
//       输出 GMII 风格字节流 (o_tx_data/vld/sop/eop)。
//       真正闭环: 不再依赖上游 RX 透传, 由本地 PHC 驱动出帧。
// 协议布局参考 gptp_frame_parser 偏移表 (DA6+SA6+ET2+PTP header)。
// 规范: 端口对齐 / 分组注释 / r_w_ro 前缀 / state_c-state_n / P_ST_ 独热 /
//       跳转条件独立 wire / 三段式 / i_clk-i_rst / posedge i_rst / 'd0。
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "gptp_defines.v"

module gptp_tx_gen #(
    parameter PORT_ID = 4'd0
)(
    // ---- 系统时钟/复位 ----
    input  wire                     i_clk,
    input  wire                     i_rst,

    // ---- 使能与时间源 ----
    input  wire                     i_enable,        // 本端口为 owner(GM) 时为 1
    input  wire [`GPTT_TIME_W-1:0]  i_phc_ns,        // 当前 PHC 时间 (作 t1)

    // ---- 发送节奏 (Sync 帧周期, 单位 clk) ----
    input  wire [31:0]              i_period,

    // ---- GMII 发送字节流 ----
    output reg  [7:0]               o_tx_data,
    output reg                      o_tx_vld,
    output reg                      o_tx_sop,
    output reg                      o_tx_eop
);

// ----- param -----
localparam SYNC_LEN = 8'd56;   // Sync 帧总字节数
localparam FU_LEN   = 8'd20;   // Follow_Up 帧总字节数 (DA6+SA6+ET2+HDR6=20 最小)
localparam ANN_LEN  = 8'd64;   // Announce 帧总字节数 (含优先级向量字段)
localparam OFF_ORIG_LO = 8'd47;// originTimestamp 纳秒首字节采样偏移 (DA 起算)
localparam OFF_ORIG_HI = 8'd50;// originTimestamp 纳秒末字节采样偏移
// Announce 优先级向量偏移 (DA 起算): P1@33, ClockID@34-41, P2@42, Steps@43-44
localparam OFF_ANN_P1  = 8'd33;
localparam OFF_ANN_CID = 8'd34;
localparam OFF_ANN_P2  = 8'd42;
localparam OFF_ANN_SR  = 8'd43;

// ----- reg -----
reg [7:0]              r_byte_cnt;     // 当前帧内字节计数 (0..LEN-1)
reg [31:0]             r_tick;         // 发送周期计时
reg [`GPTT_TIME_W-1:0] r_t1_hold;      // 锁存的 t1 (出 Sync 时采样)
reg [15:0]             r_seq;          // 当前 sequenceId
reg [1:0]               r_tx_phase;    // 0=Sync, 1=Follow_Up, 2=Announce
// 状态常量 (独热码)
reg [1:0]              state_c;
reg [1:0]              state_n;

// ----- wire -----
wire                    w_is_idle;
wire                    w_start;        // 启动一帧 (组合, 进入拍即生效)
wire                    w_byte_at_orig; // 当前字节落在 originTimestamp 区间

// ----- assign -----
assign w_is_idle = (state_c == P_ST_IDLE);
// 启动: IDLE 且使能且计时到 -> 进入发送 (组合基于旧 state_c, 进入拍即输出 byte0)
assign w_start   = w_is_idle && i_enable && (r_tick >= i_period);
assign w_byte_at_orig = (r_byte_cnt >= OFF_ORIG_LO) && (r_byte_cnt <= OFF_ORIG_HI);

// FSM 状态常量 (独热码)
parameter P_ST_IDLE = 2'b01;   // 等待下一发送周期
parameter P_ST_SEND = 2'b10;   // 发送 Sync / Follow_Up / Announce

// 状态跳转条件 (独立 wire)
wire p_st_idle2p_st_send_start = w_start;
wire p_st_send2p_st_idle_start = (state_c==P_ST_SEND) && (r_tx_phase==2'd2) && (r_byte_cnt==(ANN_LEN-8'd1));

// ----- inst -----
// (本模块无实例化)

// ----- combine_Logic -----
// 次态计算 (仅 case, default -> P_ST_IDLE)
always @* begin
    case (state_c)
        P_ST_IDLE: if (p_st_idle2p_st_send_start) state_n = P_ST_SEND; else state_n = state_c;
        P_ST_SEND: if (p_st_send2p_st_idle_start) state_n = P_ST_IDLE; else state_n = state_c;
        default:   state_n = P_ST_IDLE;
    endcase
end

// ----- always -----
// 状态寄存器 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        state_c <= P_ST_IDLE;
    else
        state_c <= state_n;
end

// 发送周期计时 (单信号)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_tick <= 'd0;
    else if (w_is_idle && !w_start && (r_tick < i_period))
        r_tick <= r_tick + 32'd1;
    else if (!w_is_idle)
        r_tick <= 'd0;
    else
        r_tick <= 'd0;
end

// 字节计数 (单信号)
// 注: w_start 拍预置为 1 (下一拍发 byte1), 避免进入 SEND 首拍 state_c 旧值错位
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_byte_cnt <= 'd0;
    else if (w_start)
        r_byte_cnt <= 8'd1;
    else if (state_c==P_ST_SEND) begin
        if ((r_tx_phase==2'd0) && (r_byte_cnt==(SYNC_LEN-8'd1))) begin
            r_byte_cnt <= 'd0;   // Sync 末字节 -> 切 FU, 计数归零 (FU byte0 由相位分支输出)
        end else if ((r_tx_phase==2'd1) && (r_byte_cnt==(FU_LEN-8'd1))) begin
            r_byte_cnt <= 'd0;   // FU 末字节 -> 切 Announce
        end else if ((r_tx_phase==2'd2) && (r_byte_cnt==(ANN_LEN-8'd1))) begin
            r_byte_cnt <= 'd0;
        end else
            r_byte_cnt <= r_byte_cnt + 8'd1;
    end else
        r_byte_cnt <= 'd0;
end

// 发送相位 (单信号): Sync -> FU -> Announce 循环
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_tx_phase <= 2'd0;
    else if (w_start)
        r_tx_phase <= 2'd0;
    else if ((state_c==P_ST_SEND) && (r_tx_phase==2'd0) && (r_byte_cnt==(SYNC_LEN-8'd1)))
        r_tx_phase <= 2'd1;   // Sync -> FU
    else if ((state_c==P_ST_SEND) && (r_tx_phase==2'd1) && (r_byte_cnt==(FU_LEN-8'd1)))
        r_tx_phase <= 2'd2;   // FU -> Announce
    else
        r_tx_phase <= r_tx_phase;
end

// t1 锁存 (单信号): 启动首字节时采样 PHC 作为 originTimestamp
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_t1_hold <= 'd0;
    else if (w_start)
        r_t1_hold <= i_phc_ns;
    else
        r_t1_hold <= r_t1_hold;
end

// sequenceId 递增 (单信号): 每个 Sync 帧 +1
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_seq <= 'd0;
    else if ((state_c==P_ST_SEND) && (r_tx_phase==1'b0) && (r_byte_cnt==(SYNC_LEN-8'd1)))
        r_seq <= r_seq + 16'd1;
    else
        r_seq <= r_seq;
end

// 发送字节流 (单信号): 组合 w_start + 时序 state_c 对齐, 进入拍即出 byte0
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst) begin
        o_tx_vld  <= 1'b0;
        o_tx_sop  <= 1'b0;
        o_tx_eop  <= 1'b0;
        o_tx_data <= 8'd0;
    end else if (w_start) begin
        // 进入拍: 输出 Sync 帧 byte0, sop=1, eop=0
        o_tx_vld  <= 1'b1;
        o_tx_sop  <= 1'b1;
        o_tx_eop  <= 1'b0;
        o_tx_data <= 8'h01;
    end else if (state_c==P_ST_SEND && r_tx_phase==1'b0) begin
        // Sync 帧 (msgType=0), byte0 已由 w_start 输出, 此处 byte1..55
        o_tx_vld <= 1'b1;
        o_tx_sop <= 1'b0;
        o_tx_eop <= (r_byte_cnt == (SYNC_LEN-8'd1));
        case (r_byte_cnt)
            8'd1:   o_tx_data <= 8'h80;
            8'd2:   o_tx_data <= 8'hC2;
            8'd3:   o_tx_data <= 8'h00;
            8'd4:   o_tx_data <= 8'h00;
            8'd5:   o_tx_data <= 8'h0E;
            8'd6:   o_tx_data <= 8'hAA;
            8'd7:   o_tx_data <= 8'hBB;
            8'd8:   o_tx_data <= 8'hCC;
            8'd9:   o_tx_data <= 8'hDD;
            8'd10:  o_tx_data <= 8'hEE;
            8'd11:  o_tx_data <= 8'hFF;
            8'd12:  o_tx_data <= 8'h88;   // EtherType 高
            8'd13:  o_tx_data <= 8'hF7;   // EtherType 低
            8'd14:  o_tx_data <= `MT_SYNC; // msgType = Sync
            8'd15:  o_tx_data <= 8'h02;   // version
            8'd16:  o_tx_data <= 8'h00;
            8'd17:  o_tx_data <= 8'h2C;   // messageLength
            8'd18:  o_tx_data <= 8'h00;
            8'd19:  o_tx_data <= 8'h00;
            8'd20:  o_tx_data <= 8'h02;
            8'd21:  o_tx_data <= 8'h00;   // flags
            // 22..29 correctionField = 0 (GM 无累积)
            8'd22,8'd23,8'd24,8'd25,8'd26,8'd27,8'd28,8'd29: o_tx_data <= 8'd0;
            // 30..39 保留/字段填 0
            8'd30,8'd31,8'd32,8'd33,8'd34,8'd35,8'd36,8'd37,8'd38,8'd39: o_tx_data <= 8'd0;
            8'd40:  o_tx_data <= r_seq[15:8];  // sequenceId 高
            8'd41:  o_tx_data <= r_seq[7:0];   // sequenceId 低
            default: o_tx_data <= 8'd0;
        endcase
    end     else if (state_c==P_ST_SEND && r_tx_phase==2'd1) begin
        // Follow_Up 帧 (msgType=8), 携带 t1
        o_tx_vld <= 1'b1;
        o_tx_sop <= (r_byte_cnt == 8'd0);
        o_tx_eop <= (r_byte_cnt == (FU_LEN-8'd1));
        case (r_byte_cnt)
            8'd0:  o_tx_data <= 8'h01;
            8'd1:  o_tx_data <= 8'h80;
            8'd2:  o_tx_data <= 8'hC2;
            8'd3:  o_tx_data <= 8'h00;
            8'd4:  o_tx_data <= 8'h00;
            8'd5:  o_tx_data <= 8'h0E;
            8'd6:  o_tx_data <= 8'hAA;
            8'd7:  o_tx_data <= 8'hBB;
            8'd8:  o_tx_data <= 8'hCC;
            8'd9:  o_tx_data <= 8'hDD;
            8'd10: o_tx_data <= 8'hEE;
            8'd11: o_tx_data <= 8'hFF;
            8'd12: o_tx_data <= 8'h88;
            8'd13: o_tx_data <= 8'hF7;
            8'd14: o_tx_data <= `MT_FOLLOW_UP; // msgType = Follow_Up
            8'd15: o_tx_data <= 8'h02;
            8'd16: o_tx_data <= 8'h00;
            8'd17: o_tx_data <= 8'h2C;
            8'd18: o_tx_data <= 8'h00;
            8'd19: o_tx_data <= 8'h00;
            // 22..29 cf = 0
            8'd22,8'd23,8'd24,8'd25,8'd26,8'd27,8'd28,8'd29: o_tx_data <= 8'd0;
            8'd40: o_tx_data <= r_seq[15:8];   // sequenceId 与对应 Sync 相同
            8'd41: o_tx_data <= r_seq[7:0];
            // 48..51 originTimestamp.ns = t1 (大端)
            8'd48: o_tx_data <= r_t1_hold[63:56];
            8'd49: o_tx_data <= r_t1_hold[55:48];
            8'd50: o_tx_data <= r_t1_hold[47:40];
            8'd51: o_tx_data <= r_t1_hold[39:32];
            default: o_tx_data <= 8'd0;
        endcase
    end else if (state_c==P_ST_SEND && r_tx_phase==2'd2) begin
        // Announce 帧 (msgType=11), 携带本地优先级向量 (BMCA 用)
        o_tx_vld <= 1'b1;
        o_tx_sop <= (r_byte_cnt == 8'd0);
        o_tx_eop <= (r_byte_cnt == (ANN_LEN-8'd1));
        case (r_byte_cnt)
            8'd0:  o_tx_data <= 8'h01;
            8'd1:  o_tx_data <= 8'h80;
            8'd2:  o_tx_data <= 8'hC2;
            8'd3:  o_tx_data <= 8'h00;
            8'd4:  o_tx_data <= 8'h00;
            8'd5:  o_tx_data <= 8'h0E;
            8'd6:  o_tx_data <= 8'hAA;
            8'd7:  o_tx_data <= 8'hBB;
            8'd8:  o_tx_data <= 8'hCC;
            8'd9:  o_tx_data <= 8'hDD;
            8'd10: o_tx_data <= 8'hEE;
            8'd11: o_tx_data <= 8'hFF;
            8'd12: o_tx_data <= 8'h88;
            8'd13: o_tx_data <= 8'hF7;
            8'd14: o_tx_data <= `MT_ANNOUNCE; // msgType = Announce
            8'd15: o_tx_data <= 8'h02;
            8'd16: o_tx_data <= 8'h00;
            8'd17: o_tx_data <= 8'h2C;
            8'd18: o_tx_data <= 8'h00;
            8'd19: o_tx_data <= 8'h00;
            // 22..29 cf = 0
            8'd22,8'd23,8'd24,8'd25,8'd26,8'd27,8'd28,8'd29: o_tx_data <= 8'd0;
            // 33: priority1 = 128 (GM 典型值)
            8'd33: o_tx_data <= 8'h80;
            // 34..41: clockIdentity (用 PORT_ID 构造, 高位填 0)
            8'd34: o_tx_data <= 8'h00;
            8'd35: o_tx_data <= 8'h00;
            8'd36: o_tx_data <= 8'h00;
            8'd37: o_tx_data <= 8'h00;
            8'd38: o_tx_data <= 8'h00;
            8'd39: o_tx_data <= 8'h00;
            8'd40: o_tx_data <= 8'h00;
            8'd41: o_tx_data <= PORT_ID[7:0];
            // 42: priority2 = 128
            8'd42: o_tx_data <= 8'h80;
            // 43..44: stepsRemoved = 0 (GM 本身)
            8'd43: o_tx_data <= 8'h00;
            8'd44: o_tx_data <= 8'h00;
            // 45: timeSource = 0x10 (atomic clock)
            8'd45: o_tx_data <= 8'h10;
            default: o_tx_data <= 8'd0;
        endcase
    end else begin
        o_tx_vld  <= 1'b0;
        o_tx_sop  <= 1'b0;
        o_tx_eop  <= 1'b0;
        o_tx_data <= 8'd0;
    end
end

endmodule
