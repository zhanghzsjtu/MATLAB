/////////////////////////////////////////////////////////////////
// Copyright (c) 2026 local TSN gPTP port (MAC IP adaptation shim)
// 模块: gptp_mac_adapt  —  MAC IP 适配层 (XGMII/AXI-S 占位)
// 功能: 在 gPTP switch 的 GMII 字节流接口与用户 10G MAC IP 之间提供
//       一层适配。当前实现为 GMII 字节流直连透传 (仿真可用)，并预留
//       XGMII (72-bit: 64 数据 + 8 控制) 与 AXI-S (TVALID/TREADY/
//       TDATA/TLAST) 接口位宽与握手占位，便于后续对接 Xilinx 1G/10G
//       MAC IP (如 1G/10G PCS/PMA, AXI Ethernet Subsystem)。
// 规范: 端口对齐 / 分组注释 / r_w_ro 前缀 / i_clk-i_rst / posedge i_rst /
//       'd0 / ro_ 经 assign 接 output / 实例化集中 inst 组且端口括号对齐。
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "gptp_defines.v"

module gptp_mac_adapt #(
    parameter MAC_IF   = "GMII",     // "GMII" | "XGMII" | "AXIS" (占位选择)
    parameter NPORTS  = 4
)(
    // ---- 系统时钟/复位 ----
    input  wire                     i_clk,
    input  wire                     i_rst,

    // ---- 用户 MAC IP 侧 (XGMII/AXI-S 占位, 当前未用) ----
    // XGMII: 72-bit (64 数据 + 8 控制), 此处仅占位
    input  wire [71:0]              i_xgmii_rxd,
    input  wire [7:0]               i_xgmii_rxc,
    output wire [71:0]              o_xgmii_txd,
    output wire [7:0]               o_xgmii_txc,
    // AXI-S (TX): 占位
    input  wire                     i_axis_tready,
    output wire                     o_axis_tvalid,
    output wire [63:0]              o_axis_tdata,
    output wire                     o_axis_tlast,

    // ---- gPTP switch 侧 (GMII 字节流数组, 当前主用) ----
    input  wire [7:0]               i_rx_data [0:NPORTS-1],
    input  wire                     i_rx_vld  [0:NPORTS-1],
    input  wire                     i_rx_sop  [0:NPORTS-1],
    input  wire                     i_rx_eop  [0:NPORTS-1],
    output wire [7:0]               o_rx_data [0:NPORTS-1],
    output wire                     o_rx_vld  [0:NPORTS-1],
    output wire                     o_rx_sop  [0:NPORTS-1],
    output wire                     o_rx_eop  [0:NPORTS-1],

    input  wire [7:0]               i_tx_data [0:NPORTS-1],
    input  wire                     i_tx_vld  [0:NPORTS-1],
    input  wire                     i_tx_sop  [0:NPORTS-1],
    input  wire                     i_tx_eop  [0:NPORTS-1],
    output wire [7:0]               o_tx_data [0:NPORTS-1],
    output wire                     o_tx_vld  [0:NPORTS-1],
    output wire                     o_tx_sop  [0:NPORTS-1],
    output wire                     o_tx_eop  [0:NPORTS-1]
);

// ----- param -----
// (MAC_IF 选择见 module 头; 当前仅 GMII 透传实现)

// ----- reg -----
// (本模块为组合透传, 无状态寄存器)

// ----- wire -----
// XGMII/AXI-S 占位输出 (当前恒 0, 未对接真实 MAC IP)
wire [71:0] w_xgmii_txd;
wire [7:0]  w_xgmii_txc;
wire        w_axis_tvalid;
wire [63:0] w_axis_tdata;
wire        w_axis_tlast;

// ----- assign -----
// GMII 字节流: switch 侧 <-> MAC 侧 直连透传 (双向)
generate
    genvar p;
    for (p = 0; p < NPORTS; p = p + 1) begin : GEN_PORT
        assign o_rx_data[p] = i_rx_data[p];
        assign o_rx_vld[p]  = i_rx_vld[p];
        assign o_rx_sop[p]  = i_rx_sop[p];
        assign o_rx_eop[p]  = i_rx_eop[p];
        assign o_tx_data[p] = i_tx_data[p];
        assign o_tx_vld[p]  = i_tx_vld[p];
        assign o_tx_sop[p]  = i_tx_sop[p];
        assign o_tx_eop[p]  = i_tx_eop[p];
    end
endgenerate

// XGMII/AXI-S 占位: 恒 0 (后续对接时按 MAC_IF 实现序列化/反序列化)
assign w_xgmii_txd  = 72'd0;
assign w_xgmii_txc  = 8'd0;
assign w_axis_tvalid= 1'b0;
assign w_axis_tdata = 64'd0;
assign w_axis_tlast = 1'b0;
assign o_xgmii_txd  = w_xgmii_txd;
assign o_xgmii_txc  = w_xgmii_txc;
assign o_axis_tvalid= w_axis_tvalid;
assign o_axis_tdata = w_axis_tdata;
assign o_axis_tlast = w_axis_tlast;

// ----- FSM -----
// (本模块无状态机)

// ----- inst -----
// (本模块无子实例化)

// ----- combine_Logic -----
// (透传已在 assign 实现)

// ----- always -----
// (本模块无时序逻辑)

endmodule
