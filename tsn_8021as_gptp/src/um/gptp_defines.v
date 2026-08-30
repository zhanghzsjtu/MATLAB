/////////////////////////////////////////////////////////////////
// Copyright (c) 2018-2026 FAST Group (style reference)
// 参考: 国防科大 OpenTSN (github.com/hakiri/openTSN)
// 架构: PTP_1588 -> Manage_CTRL/PTP_CTRL/CYC_SYNC/RX_PROC/TX_PROC
// 本文件: 802.1AS gPTP 全局参数 / 报文类型 / 定点格式定义
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`ifndef GPTT_DEFINES_V
`define GPTT_DEFINES_V

// ----- param -----
`define GPTT_TIME_W   64    // 时间计数器位宽 (纳秒整数)
`define GPTT_FRAC_W   32    // 亚纳秒分数累加器位宽 (sub-ns, 用于频偏细分)
`define CF_FRAC_W     16    // correctionField 定点小数位宽 (1ns = 2^16)

// ----- reg -----
// (本文件仅宏定义, 无寄存器)

// ----- wire -----
// (本文件仅宏定义, 无线网)

// ----- assign -----
// (本文件仅宏定义, 无连续赋值)

// ----- FSM -----
// (本文件仅宏定义, 无状态机)

// ----- inst -----
// (本文件仅宏定义, 无实例化)

// ----- combine_Logic -----
// (本文件仅宏定义, 无组合逻辑)

// ----- always -----
// (本文件仅宏定义, 无时序逻辑)

// ----- param: 报文类型 (PTP 头 byte0[3:0]) -----
`define MT_SYNC           4'd0
`define MT_DELAY_REQ      4'd1   // 1588 E2E 用, 802.1AS 不使用
`define MT_PDELAY_REQ     4'd2   // 802.1AS P2P 强制
`define MT_PDELAY_RESP    4'd3
`define MT_FOLLOW_UP      4'd8
`define MT_PDELAY_RESP_FU 4'd10  // 0xA  Pdelay_Resp_Follow_Up
`define MT_ANNOUNCE       4'd11  // 0xB  BMCA

`endif
