/////////////////////////////////////////////////////////////////
// Testbench: tb_gptp_tc
// 分层验证 (由底向上逐级验证): gptp_tc 透明时钟 one-step 修正字段改写
//   检查项:
//   1) residence=0 & peerDelay=0 -> cf_out = cf_in
//   2) residence=136ns -> cf_out = cf_in + 136*65536
//   3) residence=136 & peerDelay=19 -> cf_out = cf_in + 155*65536
//   4) i_pkt_vld 当拍 o_cf_wr 脉冲拉高
//   5) 无 X 状态
//   6) two-step 模式 (TC_MODE=1): i_pkt_vld 当拍 o_cf_rd 拉高 (回读原 CF)
//   7) one-step 模式 (TC_MODE=0): o_cf_rd 恒 0
// 用法:
//   iverilog -g2012 -Isrc/um -o sim/tb_gptp_tc.vvp \
//       src/um/gptp_defines.v src/um/gptp_tc.v tb/tb_gptp_tc.v
//   vvp sim/tb_gptp_tc.vvp
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "gptp_defines.v"

module tb_gptp_tc;

    reg                     clk;
    reg                     i_rst;

    reg [`GPTT_TIME_W-1:0]  i_residence_ns;
    reg                     i_residence_vld;
    reg [`GPTT_TIME_W-1:0]  i_peer_delay_ns;
    reg                     i_peer_delay_vld;

    reg                     i_pkt_vld;
    reg [63:0]              i_cf_in;
    wire [63:0]             o_cf_out;
    wire                    o_cf_wr;
    wire                    o_cf_rd;

    // two-step 模式 DUT (TC_MODE=1): 验证 o_cf_rd 回读脉冲
    wire [63:0]             o_cf_rd_out;
    wire                    o_cf_rd_wr;
    wire                    o_cf_rd_rd;

    always #4 clk = ~clk;

    gptp_tc #(.PORT_ID(4'd0), .TC_MODE(1'd0)) u_dut (
        .i_clk (clk),

        .i_rst              (i_rst),
        .i_residence_ns   (i_residence_ns),
        .i_residence_vld  (i_residence_vld),
        .i_peer_delay_ns  (i_peer_delay_ns),
        .i_peer_delay_vld (i_peer_delay_vld),
        .i_pkt_vld        (i_pkt_vld),
        .i_cf_in          (i_cf_in),
        .o_cf_out         (o_cf_out),
        .o_cf_wr          (o_cf_wr),
        .o_cf_rd          (o_cf_rd)
    );

    gptp_tc #(.PORT_ID(4'd1), .TC_MODE(1'd1)) u_twostep (
        .i_clk (clk),

        .i_rst              (i_rst),
        .i_residence_ns   (i_residence_ns),
        .i_residence_vld  (i_residence_vld),
        .i_peer_delay_ns  (i_peer_delay_ns),
        .i_peer_delay_vld (i_peer_delay_vld),
        .i_pkt_vld        (i_pkt_vld),
        .i_cf_in          (i_cf_in),
        .o_cf_out         (o_cf_rd_out),
        .o_cf_wr          (o_cf_rd_wr),
        .o_cf_rd          (o_cf_rd_rd)
    );

    reg     tb_pass;

    task tick; begin @(posedge clk); end endtask

    initial begin
        $dumpfile("sim/tb_gptp_tc.vcd");
        $dumpvars(0, tb_gptp_tc);

        clk = 0; i_rst = 1;
        i_residence_ns = 0; i_residence_vld = 0;
        i_peer_delay_ns = 0; i_peer_delay_vld = 0;
        i_pkt_vld = 0; i_cf_in = 0;

        #20 i_rst = 0;
        tb_pass = 1'b1;

        // ---- 检查 1: 全 0 -> cf_out = cf_in ----
        i_cf_in = 64'd12345;
        @(posedge clk); i_pkt_vld = 1; @(posedge clk); i_pkt_vld = 0;
        @(posedge clk);
        if (o_cf_out !== 64'd12345) begin
            $display("[FAIL] TC: zero total cf_out=%0d expected 12345", o_cf_out);
            tb_pass = 1'b0;
        end

        // ---- 检查 2: residence=136 -> cf_in + 136*65536 ----
        @(posedge clk);
        i_residence_ns = 136; i_residence_vld = 1; @(posedge clk); i_residence_vld = 0;
        repeat (2) @(posedge clk);
        i_cf_in = 64'd0;
        @(posedge clk); i_pkt_vld = 1; @(posedge clk); i_pkt_vld = 0;
        @(posedge clk);
        if (o_cf_out !== 64'd8912896) begin  // 136*65536 = 8912896
            $display("[FAIL] TC: residence-only cf_out=%0d expected 8912896", o_cf_out);
            tb_pass = 1'b0;
        end

        // ---- 检查 3: residence=136 + peerDelay=19 -> cf_in + 155*65536 ----
        @(posedge clk);
        i_peer_delay_ns = 19; i_peer_delay_vld = 1; @(posedge clk); i_peer_delay_vld = 0;
        repeat (2) @(posedge clk);
        i_cf_in = 64'd1000;
        @(posedge clk); i_pkt_vld = 1; @(posedge clk); i_pkt_vld = 0;
        @(posedge clk);
        if (o_cf_out !== 64'd10159080) begin  // 1000 + 155*65536 = 1000 + 10158080 = 10159080
            $display("[FAIL] TC: residence+peerDelay cf_out=%0d expected 10159080", o_cf_out);
            tb_pass = 1'b0;
        end

        // ---- 检查 4: i_pkt_vld 采样后 o_cf_wr 应脉冲拉高 ----
        // 注: o_cf_wr 为打拍输出; 在 i_pkt_vld 采样沿的下降沿检查 (NBA 已提交)
        @(posedge clk);
        i_cf_in = 64'd0;
        i_pkt_vld = 1;
        @(posedge clk);          // 采样 i_pkt_vld, ro_cf_wr<=1 调度
        @(negedge clk);          // NBA 已提交, 此时 o_cf_wr=1
        if (o_cf_wr !== 1'b1) begin
            $display("[FAIL] TC: o_cf_wr not asserted after pkt_vld sampled");
            tb_pass = 1'b0;
        end
        i_pkt_vld = 0;

        // ---- 检查 5: 无 X ----
        @(posedge clk);
        if (o_cf_out === 64'hx) begin
            $display("[FAIL] TC: cf_out is X");
            tb_pass = 1'b0;
        end

        // ---- 检查 6: two-step 模式 (u_twostep) i_pkt_vld 采样后 o_cf_rd 拉高 ----
        @(posedge clk);
        i_cf_in = 64'd0;
        i_pkt_vld = 1;
        @(posedge clk);          // 采样 i_pkt_vld, ro_cf_rd<=1 调度
        @(negedge clk);          // NBA 提交, o_cf_rd_rd=1
        if (o_cf_rd_rd !== 1'b1) begin
            $display("[FAIL] TC: two-step o_cf_rd not asserted after pkt_vld sampled");
            tb_pass = 1'b0;
        end
        i_pkt_vld = 0;

        // ---- 检查 7: one-step 模式 o_cf_rd 恒为 0 ----
        @(posedge clk);
        i_cf_in = 64'd0;
        i_pkt_vld = 1;
        @(posedge clk);
        @(negedge clk);
        if (o_cf_rd !== 1'b0) begin
            $display("[FAIL] TC: one-step o_cf_rd should stay 0, got %b", o_cf_rd);
            tb_pass = 1'b0;
        end
        i_pkt_vld = 0;

        if (tb_pass) begin
            $display("========================================");
            $display("  [PASS] gptp_tc ALL CHECKS PASSED");
            $display("========================================");
        end else begin
            $display("========================================");
            $display("  [FAIL] gptp_tc SOME CHECKS FAILED");
            $display("========================================");
        end
        $finish;
    end

endmodule
