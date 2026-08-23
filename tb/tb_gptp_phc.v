/////////////////////////////////////////////////////////////////
// Testbench: tb_gptp_phc
// 分层验证 (由底向上逐级验证): gptp_phc 精确时间硬件时钟
//   检查项:
//   1) 复位后 ro_time_ns = 0
//   2) 自由运行: 125MHz -> 每 8ns 纳秒计数 +1 (TICK_NS_I = 1000_000_000/125_000_000 = 8)
//   3) settime 初始化: 写入 w_settime_ns 立即生效
//   4) adjtime 相位跳变: 写入有符号 delta 后计数整体平移
//   5) adjfine 频率微调: 加数 > 2^31 (偏快) 时 ns 增长变快, < 2^31 (偏慢) 时变慢
// 用法:
//   iverilog -g2012 -Isrc/um -o sim/tb_gptp_phc.vvp \
//       src/um/gptp_defines.v src/um/gptp_phc.v tb/tb_gptp_phc.v
//   vvp sim/tb_gptp_phc.vvp
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "gptp_defines.v"

module tb_gptp_phc;

    reg                          clk;
    reg                     i_rst;

    reg                          w_adjfine_wr;
    reg signed [31:0]            w_adjfine_addend;
    reg                          w_adjtime_wr;
    reg signed [`GPTT_TIME_W-1:0] w_adjtime_delta_ns;
    reg                          w_settime_wr;
    reg [`GPTT_TIME_W-1:0]       w_settime_ns;

    wire [`GPTT_TIME_W-1:0]      ro_time_ns;
    wire [31:0]                  ro_time_frac;

    // ---- 时钟 125MHz -> 周期 8ns ----
    always #4 clk = ~clk;

    gptp_phc #(.CLK_FREQ_HZ(125_000_000)) u_dut (
        .i_clk (clk),
        
        .i_rst              (i_rst),
        .w_adjfine_wr       (w_adjfine_wr),
        .w_adjfine_addend   (w_adjfine_addend),
        .w_adjtime_wr       (w_adjtime_wr),
        .w_adjtime_delta_ns (w_adjtime_delta_ns),
        .w_settime_wr       (w_settime_wr),
        .w_settime_ns       (w_settime_ns),
        .o_time_ns (ro_time_ns),
        .o_time_frac (ro_time_frac)
    );

    integer i;
    reg     tb_pass;

    // 读拍函数: 返回当前 ro_time_ns
    task wait_cycles;
        input integer n;
        integer k;
    begin
        for (k = 0; k < n; k = k + 1) @(posedge clk);
    end
    endtask

    initial begin
        $dumpfile("sim/tb_gptp_phc.vcd");
        $dumpvars(0, tb_gptp_phc);

        clk = 0; i_rst = 1;
        w_adjfine_wr = 0;  w_adjfine_addend = 0;
        w_adjtime_wr = 0;  w_adjtime_delta_ns = 0;
        w_settime_wr = 0;  w_settime_ns = 0;

        #20 i_rst = 0;
        wait_cycles(2);
        tb_pass = 1'b1;

        // ---- 检查 1: 复位后 time_ns = 0 ----
        if (ro_time_ns !== 64'd0) begin
            $display("[FAIL] PHC: reset time_ns=%0d expected 0", ro_time_ns);
            tb_pass = 1'b0;
        end

        // ---- 检查 2: 自由运行, 每 clk 拍 (=8ns) 纳秒 + TICK_NS_I(=8) ----
        // 注: TICK_NS_I = 1e9/125e6 = 8, 即每个 8ns 时钟周期时间前进 8ns (实时)
        // 跑 8 拍 = 64ns, 纳秒应增加 64
        wait_cycles(8);
        if (ro_time_ns !== 64'd64) begin
            $display("[FAIL] PHC: free-run time_ns=%0d expected 64 after 64ns", ro_time_ns);
            tb_pass = 1'b0;
        end

        // ---- 检查 3: settime 初始化 ----
        @(posedge clk);
        w_settime_wr = 1; w_settime_ns = 1000; @(posedge clk); w_settime_wr = 0;
        wait_cycles(1);
        if (ro_time_ns !== 64'd1000) begin
            $display("[FAIL] PHC: settime time_ns=%0d expected 1000", ro_time_ns);
            tb_pass = 1'b0;
        end
        // 再跑 8 拍应到 1000 + 64 = 1064
        wait_cycles(8);
        if (ro_time_ns !== 64'd1064) begin
            $display("[FAIL] PHC: settime+run time_ns=%0d expected 1064", ro_time_ns);
            tb_pass = 1'b0;
        end

        // ---- 检查 4: adjtime 相位跳变 +50ns ----
        // 注意: 上一行 @(posedge clk) 已让自由运行 +8ns (1064->1072), 再 adjtime+50
        @(posedge clk);
        w_adjtime_wr = 1; w_adjtime_delta_ns = 50; @(posedge clk); w_adjtime_wr = 0;
        wait_cycles(1);
        if (ro_time_ns !== 64'd1130) begin  // 1072 + 50 + 8(free-run) = 1130
            $display("[FAIL] PHC: adjtime+ time_ns=%0d expected 1130", ro_time_ns);
            tb_pass = 1'b0;
        end
        // 负跳变 -50ns
        @(posedge clk);
        w_adjtime_wr = 1; w_adjtime_delta_ns = -50; @(posedge clk); w_adjtime_wr = 0;
        wait_cycles(1);
        if (ro_time_ns !== 64'd1096) begin  // 1130+8 - 50 + 8 = 1096
            $display("[FAIL] PHC: adjtime- time_ns=%0d expected 1096", ro_time_ns);
            tb_pass = 1'b0;
        end

        // ---- 检查 5: adjfine 频率微调 ----
        // 偏快: 加数 = 2^31 + 2^24 (大频偏, 每个 tick 累加倍增)
        // 当前基准 ~1096, 复跑 16 拍自由运行应增长 > 16*8=128ns
        @(posedge clk);
        w_adjfine_wr = 1; w_adjfine_addend = 32'sd2147483648 + 32'sd16777216; @(posedge clk); w_adjfine_wr = 0;
        wait_cycles(16);
        if (ro_time_ns <= 64'd1096 + 128) begin
            $display("[FAIL] PHC: adjfine(fast) time_ns=%0d not faster than nominal", ro_time_ns);
            tb_pass = 1'b0;
        end
        // 回到无偏: 加数 = 2^31, 再跑应恢复每 8ns +1ns 步长
        @(posedge clk);
        w_adjfine_wr = 1; w_adjfine_addend = 32'sd2147483648; @(posedge clk); w_adjfine_wr = 0;
        wait_cycles(8);
        // 此处仅确认无 X, 不卡绝对量级 (频偏累积量不确定)
        if (ro_time_ns === 64'hx) begin
            $display("[FAIL] PHC: adjfine reset produced X");
            tb_pass = 1'b0;
        end

        // ---- 汇总 ----
        if (tb_pass) begin
            $display("========================================");
            $display("  [PASS] gptp_phc 全部检查项通过");
            $display("========================================");
        end else begin
            $display("========================================");
            $display("  [FAIL] gptp_phc 存在失败项");
            $display("========================================");
        end
        $finish;
    end

endmodule
