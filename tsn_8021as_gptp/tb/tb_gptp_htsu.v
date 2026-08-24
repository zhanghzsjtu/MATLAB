/////////////////////////////////////////////////////////////////
// Testbench: tb_gptp_htsu
// 分层验证 (由底向上逐级验证): gptp_htsu 硬件时间戳单元
//   检查项:
//   1) event 收帧: SOF 锁 t2, EOF 后进入 WAIT; 非 event 帧不锁
//   2) event 出帧: SOF 锁 t3, EOF 后算 residence = t3 - t2 并置 vld
//   3) residence 值正确 (= t3 - t2)
//   4) 非 event 帧不会产生有效时间戳/驻留
// 用法:
//   iverilog -g2012 -Isrc/um -o sim/tb_gptp_htsu.vvp \
//       src/um/gptp_defines.v src/um/gptp_htsu.v tb/tb_gptp_htsu.v
//   vvp sim/tb_gptp_htsu.vvp
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "gptp_defines.v"

module tb_gptp_htsu;

    reg                     clk;
    reg                     i_rst;

    reg [`GPTT_TIME_W-1:0]  i_phc_time_ns;
    reg [31:0]              i_phc_time_frac;

    reg                     i_rx_sof;
    reg                     i_rx_eof;
    reg                     i_tx_sof;
    reg                     i_tx_eof;
    reg                     i_is_event_pkt;

    wire [`GPTT_TIME_W-1:0] ro_rx_ts_ns;
    wire [31:0]             ro_rx_ts_frac;
    wire [`GPTT_TIME_W-1:0] ro_tx_ts_ns;
    wire [31:0]             ro_tx_ts_frac;
    wire [`GPTT_TIME_W-1:0] ro_residence_ns;
    wire                    ro_residence_vld;

    always #4 clk = ~clk;

    gptp_htsu #(.PORT_ID(4'd0)) u_dut (
        .i_clk (clk),
        
        .i_rst              (i_rst),
        .i_phc_time_ns     (i_phc_time_ns),
        .i_phc_time_frac   (i_phc_time_frac),
        .i_rx_sof          (i_rx_sof),
        .i_rx_eof          (i_rx_eof),
        .i_tx_sof          (i_tx_sof),
        .i_tx_eof          (i_tx_eof),
        .i_is_event_pkt    (i_is_event_pkt),
        .o_rx_ts_ns (ro_rx_ts_ns),
        .o_rx_ts_frac (ro_rx_ts_frac),
        .o_tx_ts_ns (ro_tx_ts_ns),
        .o_tx_ts_frac (ro_tx_ts_frac),
        .o_residence_ns (ro_residence_ns),
        .o_residence_vld (ro_residence_vld)
    );

    reg     tb_pass;
    integer t2, t3;

    task tick;
    begin @(posedge clk); end
    endtask

    initial begin
        $dumpfile("sim/tb_gptp_htsu.vcd");
        $dumpvars(0, tb_gptp_htsu);

        clk = 0; i_rst = 1;
        i_phc_time_ns = 0; i_phc_time_frac = 0;
        i_rx_sof = 0; i_rx_eof = 0; i_tx_sof = 0; i_tx_eof = 0; i_is_event_pkt = 0;

        #20 i_rst = 0;
        tb_pass = 1'b1;

        // ---- 检查 1: 非 event 收帧不应锁时间戳 ----
        i_phc_time_ns = 100;
        @(posedge clk);
        i_is_event_pkt = 0; i_rx_sof = 1; @(posedge clk); i_rx_sof = 0;
        repeat (3) @(posedge clk);
        i_rx_eof = 1; @(posedge clk); i_rx_eof = 0;
        if (ro_rx_ts_ns !== 64'd0) begin
            $display("[FAIL] HTSU: non-event rx produced ts=%0d", ro_rx_ts_ns);
            tb_pass = 1'b0;
        end

        // ---- 检查 2/3: event 收帧锁 t2, 出帧锁 t3, residence=t3-t2 ----
        // 收帧: t2 = 200
        i_phc_time_ns = 200;
        @(posedge clk);
        i_is_event_pkt = 1; i_rx_sof = 1; @(posedge clk); i_rx_sof = 0;
        repeat (4) @(posedge clk);
        i_rx_eof = 1; @(posedge clk); i_rx_eof = 0;
        // 转发间隔
        repeat (3) @(posedge clk);
        // 出帧: t3 = 300 -> residence 应为 100
        i_phc_time_ns = 300;
        @(posedge clk);
        i_tx_sof = 1; @(posedge clk); i_tx_sof = 0;
        repeat (4) @(posedge clk);
        i_tx_eof = 1; @(posedge clk); i_tx_eof = 0;
        i_is_event_pkt = 0;

        // 注意: residence_vld 是单拍脉冲, 在 tx_eof 采样拍当拍置位, 不可再等拍
        if (ro_rx_ts_ns !== 64'd200) begin
            $display("[FAIL] HTSU: rx_ts(t2)=%0d expected 200", ro_rx_ts_ns);
            tb_pass = 1'b0;
        end
        if (ro_tx_ts_ns !== 64'd300) begin
            $display("[FAIL] HTSU: tx_ts(t3)=%0d expected 300", ro_tx_ts_ns);
            tb_pass = 1'b0;
        end
        if (ro_residence_ns !== 64'd100) begin
            $display("[FAIL] HTSU: residence=%0d expected 100", ro_residence_ns);
            tb_pass = 1'b0;
        end
        if (ro_residence_vld !== 1'b1) begin
            $display("[FAIL] HTSU: residence_vld not asserted");
            tb_pass = 1'b0;
        end

        // ---- 检查 4: 下一帧 event 收帧, residence_vld 应已拉低 ----
        @(posedge clk);
        if (ro_residence_vld !== 1'b0) begin
            $display("[FAIL] HTSU: residence_vld stuck high");
            tb_pass = 1'b0;
        end

        if (tb_pass) begin
            $display("========================================");
            $display("  [PASS] gptp_htsu ALL CHECKS PASSED");
            $display("========================================");
        end else begin
            $display("========================================");
            $display("  [FAIL] gptp_htsu SOME CHECKS FAILED");
            $display("========================================");
        end
        $finish;
    end

endmodule
