/////////////////////////////////////////////////////////////////
// Testbench: tb_gptp_servo
// 验证 802.1AS PI 伺服环闭环时间同步:
//   1) 收到 Sync 后计算 offset = (t1 + cf) - t2
//   2) 输出 adjtime (相位跳变) 与 adjfine (频率微调)
//   3) offset 收敛到 < 50ns 时 locked 拉高
// 用法: iverilog -g2012 -Isrc/um -o sim/tb_gptp_servo.vvp \
//        src/um/gptp_defines.v src/um/gptp_servo.v tb/tb_gptp_servo.v
//       vvp sim/tb_gptp_servo.vvp
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "gptp_defines.v"

module tb_gptp_servo;

    reg                       clk;
    reg                     i_rst;

    reg                       i_sync_rx;
    reg [`GPTT_TIME_W-1:0]    i_t1_gm_ns;
    reg [`GPTT_TIME_W-1:0]    i_t2_local_ns;
    reg [63:0]                i_cf_ns;

    reg signed [31:0]         i_kp;
    reg signed [31:0]         i_ki;

    wire                      o_adjtime_wr;
    wire signed [`GPTT_TIME_W-1:0] o_adjtime_delta_ns;
    wire                      o_adjfine_wr;
    wire signed [31:0]        o_adjfine_addend;
    wire                      o_servo_locked;

    always #4 clk = ~clk;

    gptp_servo #(.Kp_Q(16), .Ki_Q(16)) u_dut (
        .i_clk (clk),
        
        .i_rst              (i_rst),
        .i_sync_rx          (i_sync_rx),
        .i_t1_gm_ns         (i_t1_gm_ns),
        .i_t2_local_ns      (i_t2_local_ns),
        .i_cf_ns            (i_cf_ns),
        .i_kp               (i_kp),
        .i_ki               (i_ki),
        .o_adjtime_wr       (o_adjtime_wr),
        .o_adjtime_delta_ns (o_adjtime_delta_ns),
        .o_adjfine_wr       (o_adjfine_wr),
        .o_adjfine_addend   (o_adjfine_addend),
        .o_servo_locked     (o_servo_locked)
    );

    reg tb_pass;
    integer i;

    // 边沿捕获: 监测 servo 输出脉冲是否发生过
    reg adjtime_wr_seen;
    reg adjfine_wr_seen;
    always @(posedge clk or posedge i_rst) begin
        if (i_rst) begin
            adjtime_wr_seen <= 1'b0;
            adjfine_wr_seen <= 1'b0;
        end else begin
            if (o_adjtime_wr) adjtime_wr_seen <= 1'b1;
            if (o_adjfine_wr) adjfine_wr_seen <= 1'b1;
        end
    end

    task send_sync;
        input [`GPTT_TIME_W-1:0] t1;
        input [`GPTT_TIME_W-1:0] t2;
        input [63:0]             cf;
        begin
            // 在 posedge 之前 setup, 确保 FSM 采样到 sync 上升沿
            i_t1_gm_ns   = t1;
            i_t2_local_ns= t2;
            i_cf_ns      = cf;
            i_sync_rx    = 1'b1;
            @(posedge clk);
            @(posedge clk);
            i_sync_rx    = 1'b0;
            repeat (3) @(posedge clk);  // 等 FSM 走到 OUT
        end
    endtask

    initial begin
        $dumpfile("sim/tb_gptp_servo.vcd");
        $dumpvars(0, tb_gptp_servo);
        clk = 0; i_rst = 1;
        i_sync_rx = 0;
        i_t1_gm_ns = 0; i_t2_local_ns = 0; i_cf_ns = 0;
        i_kp = 32'sd65536;   // Kp = 1.0 (Q16)
        i_ki = 32'sd1024;    // Ki 小一点, 防 windup

        #20 i_rst = 0;
        repeat (3) @(posedge clk);

        tb_pass = 1'b1;
        adjtime_wr_seen = 1'b0;
        adjfine_wr_seen = 1'b0;

        // ---- 检查 1: 首次 Sync, offset = (1000 + 0) - 1120 = -120ns ----
        // GM 在 t1=1000 发, 本地在 t2=1120 收 (本地慢 120ns, 需往前调)
        send_sync(64'd1000, 64'd1120, 64'd0);
        if (adjtime_wr_seen !== 1'b1) begin
            $display("[FAIL] SERVO: adjtime_wr not asserted"); tb_pass = 1'b0;
        end
        if (o_adjtime_delta_ns !== -120) begin
            $display("[FAIL] SERVO: adjtime_delta=%0d expected -120", o_adjtime_delta_ns);
            tb_pass = 1'b0;
        end
        if (adjfine_wr_seen !== 1'b1) begin
            $display("[FAIL] SERVO: adjfine_wr not asserted"); tb_pass = 1'b0;
        end
        if (o_servo_locked !== 1'b0) begin
            $display("[FAIL] SERVO: locked should be 0 (|offset|=120>50)"); tb_pass = 1'b0;
        end

        // ---- 检查 2: 第二次 Sync, 假设上次 adjtime 已生效, t1=2000 t2=2010 ----
        // offset = (2000 + 0) - 2010 = -10ns -> 收敛
        send_sync(64'd2000, 64'd2010, 64'd0);
        if (o_servo_locked !== 1'b1) begin
            $display("[FAIL] SERVO: locked should be 1 (|offset|=10<50)"); tb_pass = 1'b0;
        end
        if (o_adjtime_delta_ns !== -10) begin
            $display("[FAIL] SERVO: adjtime_delta=%0d expected -10", o_adjtime_delta_ns);
            tb_pass = 1'b0;
        end

        // ---- 检查 3: 带 correctionField, cf=5ns*2^16 ----
        // offset = (3000 + 5) - 3010 = -5ns
        send_sync(64'd3000, 64'd3010, 64'd327680);
        if (o_adjtime_delta_ns !== -5) begin
            $display("[FAIL] SERVO: adjtime_delta(cf)=%0d expected -5", o_adjtime_delta_ns);
            tb_pass = 1'b0;
        end
        if (o_servo_locked !== 1'b1) begin
            $display("[FAIL] SERVO: locked should stay 1"); tb_pass = 1'b0;
        end

        #50;
        if (tb_pass) begin
            $display("========================================");
            $display("  [PASS] gptp_servo 全部检查项通过");
            $display("========================================");
        end else begin
            $display("========================================");
            $display("  [FAIL] gptp_servo 存在失败项");
            $display("========================================");
        end
        $finish;
    end

endmodule
