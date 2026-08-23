/////////////////////////////////////////////////////////////////
// Testbench: tb_gptp_bmca
// 验证 802.1AS BMCA 角色选举:
//   1) 无 announce 时默认 Master(GM)
//   2) 收到更优对端 -> Slave
//   3) 收到更差对端 -> 保持 Master
//   4) 对端更优 但 rem_steps>>本地 -> Passive (后续建议①)
// 用法: iverilog -g2012 -Isrc/um -o sim/tb_gptp_bmca.vvp \
//        src/um/gptp_defines.v src/um/gptp_bmca.v tb/tb_gptp_bmca.v
//       vvp sim/tb_gptp_bmca.vvp
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "gptp_defines.v"

module tb_gptp_bmca;

    reg                     clk;
    reg                     i_rst;

    // 本地端口优先级向量
    reg [7:0]               i_local_priority1;
    reg [63:0]              i_local_clock_id;
    reg [7:0]               i_local_priority2;
    reg [15:0]              i_local_steps_removed;
    // 对端 announce
    reg                     i_announce_rx;
    reg [7:0]               i_rem_priority1;
    reg [63:0]              i_rem_clock_id;
    reg [7:0]               i_rem_priority2;
    reg [15:0]              i_rem_steps_removed;
    reg [63:0]              i_rem_port_id;

    wire [1:0]              ro_port_role;
    wire                    ro_role_vld;
    wire                    ro_is_gm;

    always #4 clk = ~clk;

    gptp_bmca #(.PORT_ID(4'd0), .PRIORITY1(8'd128), .PRIORITY2(8'd128),
                .CLOCK_IDENTITY(64'hA1B2C3D4E5F60000)) u_dut (
        .i_clk              (clk),
        .i_rst              (i_rst),
        .i_local_priority1  (i_local_priority1),
        .i_local_clock_id   (i_local_clock_id),
        .i_local_priority2  (i_local_priority2),
        .i_local_steps_removed(i_local_steps_removed),
        .i_announce_rx      (i_announce_rx),
        .i_rem_priority1    (i_rem_priority1),
        .i_rem_clock_id     (i_rem_clock_id),
        .i_rem_priority2    (i_rem_priority2),
        .i_rem_steps_removed(i_rem_steps_removed),
        .i_rem_port_id      (i_rem_port_id),
        .o_port_role        (ro_port_role),
        .o_role_vld         (ro_role_vld),
        .o_is_gm            (ro_is_gm)
    );

    // 角色编码
    localparam ROLE_MASTER  = 2'd0;
    localparam ROLE_SLAVE   = 2'd1;
    localparam ROLE_PASSIVE = 2'd2;

    reg tb_pass;
    integer i;

    task send_announce;
        input [7:0]  p1;
        input [63:0] cid;
        input [7:0]  p2;
        input [15:0] sr;
        input [15:0] ls;   // 本地 stepsRemoved
        begin
            // 在 posedge 之前 setup, 确保 FSM 采样到 announce 上升沿
            i_local_steps_removed = ls;
            i_rem_priority1    = p1;
            i_rem_clock_id     = cid;
            i_rem_priority2    = p2;
            i_rem_steps_removed= sr;
            i_announce_rx      = 1'b1;
            @(posedge clk);
            @(posedge clk);
            i_announce_rx      = 1'b0;
            repeat (3) @(posedge clk);  // 等 FSM 走到 DONE
        end
    endtask

    initial begin
        $dumpfile("sim/tb_gptp_bmca.vcd");
        $dumpvars(0, tb_gptp_bmca);
        clk = 0; i_rst = 1;
        i_local_priority1 = 8'd128;
        i_local_clock_id  = 64'hA1B2C3D4E5F60000;
        i_local_priority2 = 8'd128;
        i_announce_rx = 0;
        i_rem_priority1 = 0; i_rem_clock_id = 0; i_rem_priority2 = 0;
        i_rem_steps_removed = 0; i_rem_port_id = 0;

        #20 i_rst = 0;
        repeat (3) @(posedge clk);

        tb_pass = 1'b1;

        // ---- 检查 1: 复位默认 Master(GM) ----
        if (ro_port_role !== ROLE_MASTER) begin
            $display("[FAIL] BMCA: reset default role=%0d expected MASTER", ro_port_role);
            tb_pass = 1'b0;
        end
        if (ro_is_gm !== 1'b1) begin
            $display("[FAIL] BMCA: reset default is_gm=%b expected 1", ro_is_gm);
            tb_pass = 1'b0;
        end

        // ---- 检查 2: 对端更优 (priority1 更小) 且本地 steps 较小 -> Slave ----
        // local_steps=5, rem_steps=1: 1 >= 5+1 为假 -> Slave
        send_announce(8'd64, 64'h1111111111111111, 8'd128, 16'd1, 16'd5);
        if (ro_port_role !== ROLE_SLAVE) begin
            $display("[FAIL] BMCA: rem better (p1=64,ls=5,sr=1) role=%0d expected SLAVE", ro_port_role);
            tb_pass = 1'b0;
        end
        if (ro_is_gm !== 1'b0) begin
            $display("[FAIL] BMCA: rem better is_gm=%b expected 0", ro_is_gm);
            tb_pass = 1'b0;
        end

        // ---- 检查 3: 对端更差 (priority1 更大) -> 保持 Master ----
        send_announce(8'd200, 64'h9999999999999999, 8'd128, 16'd2, 16'd0);
        if (ro_port_role !== ROLE_MASTER) begin
            $display("[FAIL] BMCA: rem worse (p1=200) role=%0d expected MASTER", ro_port_role);
            tb_pass = 1'b0;
        end

        // ---- 检查 4: 对端相等 (相同 p1/cid/p2) -> tie-break Master ----
        send_announce(8'd128, 64'hA1B2C3D4E5F60000, 8'd128, 16'd0, 16'd0);
        if (ro_port_role !== ROLE_MASTER) begin
            $display("[FAIL] BMCA: tie-break role=%0d expected MASTER", ro_port_role);
            tb_pass = 1'b0;
        end

        // ---- 检查 5: 对端更优 但 rem_steps 远大于本地 -> Passive (后续建议①) ----
        // local_steps=0, rem_steps=10: 10 >= 0+1 为真 -> PASSIVE
        send_announce(8'd64, 64'h1111111111111111, 8'd128, 16'd10, 16'd0);
        if (ro_port_role !== ROLE_PASSIVE) begin
            $display("[FAIL] BMCA: rem better but sr>>ls (ls=0,sr=10) role=%0d expected PASSIVE", ro_port_role);
            tb_pass = 1'b0;
        end
        if (ro_is_gm !== 1'b0) begin
            $display("[FAIL] BMCA: passive is_gm=%b expected 0", ro_is_gm);
            tb_pass = 1'b0;
        end

        #50;
        if (tb_pass) begin
            $display("========================================");
            $display("  [PASS] gptp_bmca 全部检查项通过");
            $display("========================================");
        end else begin
            $display("========================================");
            $display("  [FAIL] gptp_bmca 存在失败项");
            $display("========================================");
        end
        $finish;
    end

endmodule
