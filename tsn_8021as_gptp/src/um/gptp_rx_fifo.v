/////////////////////////////////////////////////////////////////
// Copyright (c) 2026 local TSN gPTP port (CDC async FIFO)
// 模块: gptp_rx_fifo  —  MAC RX 跨时钟域异步 FIFO
// 功能: 写口 (i_wclk, MAC 接收时钟域) 入队 GMII 字节流
//       (data+vld+sop+eop); 读口 (i_rclk, 系统时钟域) 出队。
//       采用格雷码指针跨域判空满, 实现真正的跨时钟域同步。
// 规范: 端口对齐 / 分组注释 / r_w_ro 前缀 / i_clk-i_rst / posedge i_rst /
//       'd0 / ro_ 经 assign / 实例化集中 inst 组且端口括号对齐。
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module gptp_rx_fifo #(
    parameter DEPTH_W = 6              // 深度 = 2^DEPTH_W (默认 64)
)(
    // ---- 写口 (MAC 接收时钟域) ----
    input  wire                     i_wclk,
    input  wire                     i_rst,          // 系统域复位 (跨域同步释放简化为同信号)
    input  wire [7:0]               i_wdata,
    input  wire                     i_wvld,
    input  wire                     i_wsop,
    input  wire                     i_weop,
    output wire                     o_wfull,

    // ---- 读口 (系统时钟域) ----
    input  wire                     i_rclk,
    output wire [7:0]               o_rdata,
    output wire                     o_rvld,
    output wire                     o_rsop,
    output wire                     o_reop,
    output wire                     o_rempty
);

// ----- param -----
localparam DEPTH    = (1 << DEPTH_W);
localparam PTR_W    = DEPTH_W + 1;     // 多 1 位区分空满
localparam FULL_TH  = (1 << DEPTH_W) - 2;  // 接近满阈值 (预留灰度)

// ----- reg -----
// 双端口 RAM (写口写, 读口读)
reg [10:0]             r_mem [0:DEPTH-1];

// 写指针 / 读指针 (二进制 + 格雷码)
reg [PTR_W-1:0]        r_wptr_bin;
reg [PTR_W-1:0]        r_rptr_bin;
reg [PTR_W-1:0]        r_wptr_gray;
reg [PTR_W-1:0]        r_rptr_gray;

// 跨域格雷码指针 (写指针同步到读域, 读指针同步到写域)
reg [PTR_W-1:0]        r_wptr_gray_sync1;
reg [PTR_W-1:0]        r_wptr_gray_sync2;
reg [PTR_W-1:0]        r_rptr_gray_sync1;
reg [PTR_W-1:0]        r_rptr_gray_sync2;

// 输出寄存器
reg [10:0]             ro_rdata;
reg                     ro_rvld;
reg                     ro_rsop;
reg                     ro_reop;

// ----- wire -----
wire                    w_winc;
wire                    w_rinc;
wire [PTR_W-1:0]       w_wptr_bin_next;
wire [PTR_W-1:0]       w_rptr_bin_next;
wire                    w_wfull;
wire                    w_rempty;
wire [PTR_W-1:0]       w_wptr_gray_next;
wire [PTR_W-1:0]       w_rptr_gray_next;

// ----- assign -----
assign w_winc   = i_wvld && !w_wfull;
assign w_rinc   = !w_rempty;
assign w_wptr_bin_next = r_wptr_bin + 1'b1;
assign w_rptr_bin_next = r_rptr_bin + 1'b1;
assign w_wptr_gray_next = (r_wptr_bin + 1'b1) ^ ((r_wptr_bin + 1'b1) >> 1);
assign w_rptr_gray_next = (r_rptr_bin + 1'b1) ^ ((r_rptr_bin + 1'b1) >> 1);

// 空满判断 (基于跨域格雷码比较)
// 满: 写指针比读指针多一圈 (高位相反, 次高位相反, 低位相同)
assign w_wfull  = (r_wptr_gray[PTR_W-1:PTR_W-2] != r_rptr_gray_sync2[PTR_W-1:PTR_W-2]) &&
                  (r_wptr_gray[PTR_W-3:0]        == r_rptr_gray_sync2[PTR_W-3:0]);
// 空: 读写指针相同 (格雷码)
assign w_rempty = (r_rptr_gray == r_wptr_gray_sync2);

assign o_wfull  = w_wfull;
assign o_rempty = w_rempty;
assign o_rdata  = ro_rdata[7:0];
assign o_rvld   = ro_rvld;
assign o_rsop   = ro_rsop;
assign o_reop   = ro_reop;

// ----- FSM -----
// (本模块为 CDC 结构, 无顶层状态机)

// ----- inst -----
// (本模块无子实例化)

// ----- combine_Logic -----
// (空满判断已在 assign 实现)

// ----- always -----
// 写口: 写指针二进制 + 写 RAM (i_wclk 域)
// 注: 格雷码指针仅在 w_winc 时更新, 且基于已 +1 的 bin, 避免指针超前导致误读
always @(posedge i_wclk or posedge i_rst) begin
    if (i_rst) begin
        r_wptr_bin <= 'd0;
        r_wptr_gray <= 'd0;
    end else begin
        if (w_winc) begin
            r_mem[r_wptr_bin[DEPTH_W-1:0]] <= {i_weop, i_wsop, i_wvld, i_wdata};
            r_wptr_bin <= w_wptr_bin_next;
            r_wptr_gray <= w_wptr_gray_next;
        end
    end
end

// 读口: 读指针二进制 + 读 RAM (i_rclk 域)
// 注: 格雷码指针仅在 w_rinc 时更新, 且基于已 +1 的 bin
always @(posedge i_rclk or posedge i_rst) begin
    if (i_rst) begin
        r_rptr_bin <= 'd0;
        r_rptr_gray <= 'd0;
        ro_rdata   <= 'd0;
        ro_rvld    <= 1'b0;
        ro_rsop    <= 1'b0;
        ro_reop    <= 1'b0;
    end else begin
        if (w_rinc) begin
            ro_rdata <= r_mem[r_rptr_bin[DEPTH_W-1:0]];
            ro_rvld  <= 1'b1;
            ro_rsop  <= r_mem[r_rptr_bin[DEPTH_W-1:0]][9];
            ro_reop  <= r_mem[r_rptr_bin[DEPTH_W-1:0]][10];
            r_rptr_bin <= w_rptr_bin_next;
            r_rptr_gray <= w_rptr_gray_next;
        end else begin
            ro_rvld  <= 1'b0;
            ro_rsop  <= 1'b0;
            ro_reop  <= 1'b0;
        end
    end
end

// 跨域同步: 写指针格雷码 -> 读域 (两级触发器)
always @(posedge i_rclk or posedge i_rst) begin
    if (i_rst) begin
        r_wptr_gray_sync1 <= 'd0;
        r_wptr_gray_sync2 <= 'd0;
    end else begin
        r_wptr_gray_sync1 <= r_wptr_gray;
        r_wptr_gray_sync2 <= r_wptr_gray_sync1;
    end
end

// 跨域同步: 读指针格雷码 -> 写域 (两级触发器)
always @(posedge i_wclk or posedge i_rst) begin
    if (i_rst) begin
        r_rptr_gray_sync1 <= 'd0;
        r_rptr_gray_sync2 <= 'd0;
    end else begin
        r_rptr_gray_sync1 <= r_rptr_gray;
        r_rptr_gray_sync2 <= r_rptr_gray_sync1;
    end
end

endmodule
