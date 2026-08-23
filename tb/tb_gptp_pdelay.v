/////////////////////////////////////////////////////////////////
// Testbench: tb_gptp_pdelay
// 分层验证 (由底向上逐级验证): gptp_pdelay P2P 链路延迟测量状态机
//   检查项:
//   1) i_pdreq_send 触发 SEND: 锁 t1, o_pdreq_vld 脉冲
//   2) 收 Pdelay_Resp 取 t2 (对端收 Req 时刻)
//   3) 收 Pdelay_Resp_FU 取 t3(对端发Resp)/t4(本地收RespFU)
//   4) CALC: peerDelay = ((t4-t1)-(t3-t2))>>>1
//      例: t1=1000 t2=1005 t3=1010 t4=1018 -> ((18)-(5))/2 = 6
//   5) peer_delay_vld 脉冲 & 对称链路特例 = 0
//   6) 无 X 状态
//   注: 三段式 FSM 在仿真中时序输出块对 r_fsm_cs 的读取延迟一拍,
//       故 send/resp/resfu 脉冲保持 2 拍以稳定覆盖目标状态, 检查前留拍。
// 用法:
//   iverilog -g2012 -Isrc/um -o sim/tb_gptp_pdelay.vvp \
//       src/um/gptp_defines.v src/um/gptp_pdelay.v tb/tb_gptp_pdelay.v
//   vvp sim/tb_gptp_pdelay.vvp
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "gptp_defines.v"

module tb_gptp_pdelay;

    reg                     clk;
    reg                     i_rst;

    reg [`GPTT_TIME_W-1:0]  i_phc_time_ns;

    reg                     i_pdreq_send;
    reg                     i_pdresp_rx;
    reg [63:0]              i_t2_resp;
    reg                     i_pdresfu_rx;
    reg [63:0]              i_t3_respfu;

    wire                    o_pdreq_vld;
    wire [`GPTT_TIME_W-1:0] ro_peer_delay_ns;
    wire                    ro_peer_delay_vld;
    wire [`GPTT_TIME_W-1:0] ro_t1_ns;
    wire [`GPTT_TIME_W-1:0] ro_t4_ns;

    always #4 clk = ~clk;

    gptp_pdelay #(.PORT_ID(4'd0), .PDREQ_PERIOD(32'd100000000)) u_dut (
        .i_clk (clk),
        
        .i_rst              (i_rst),
        .i_phc_time_ns    (i_phc_time_ns),
        .i_pdreq_send     (i_pdreq_send),
        .i_pdresp_rx      (i_pdresp_rx),
        .i_t2_resp        (i_t2_resp),
        .i_pdresfu_rx     (i_pdresfu_rx),
        .i_t3_respfu      (i_t3_respfu),
        .o_pdreq_vld      (o_pdreq_vld),
        .o_peer_delay_ns (ro_peer_delay_ns),
        .o_peer_delay_vld (ro_peer_delay_vld),
        .o_t1_ns (ro_t1_ns),
        .o_t4_ns (ro_t4_ns)
    );

    reg     tb_pass;
    reg     cap_pdreq_vld, cap_pd_vld;

    // 全程监控单拍脉冲 (Pdelay FSM 状态推进有跨块延迟, 脉冲易错过)
    always @(posedge clk or posedge i_rst) begin
        if (i_rst) begin
            cap_pdreq_vld <= 1'b0;
            cap_pd_vld     <= 1'b0;
        end else begin
            if (o_pdreq_vld)      cap_pdreq_vld <= 1'b1;
            if (ro_peer_delay_vld) cap_pd_vld     <= 1'b1;
        end
    end

    // 单拍脉冲保持 n 拍的辅助: 置高并持续 hold 拍
    task pulse;
        input reg sig;
        input integer hold;
        integer j;
    begin
        sig = 1'b1;
        for (j = 0; j < hold; j = j + 1) @(posedge clk);
        sig = 1'b0;
    end
    endtask

    initial begin
        $dumpfile("sim/tb_gptp_pdelay.vcd");
        $dumpvars(0, tb_gptp_pdelay);

        clk = 0; i_rst = 1;
        i_phc_time_ns = 0;
        i_pdreq_send = 0; i_pdresp_rx = 0; i_t2_resp = 0;
        i_pdresfu_rx = 0; i_t3_respfu = 0;

        #20 i_rst = 0;
        tb_pass = 1'b1;
        cap_pdreq_vld = 1'b0; cap_pd_vld = 1'b0;

        // ---- 检查 1: 触发发 Req, 锁 t1=1000 ----
        i_phc_time_ns = 1000;
        @(posedge clk);
        i_pdreq_send = 1;
        repeat (3) @(posedge clk) begin  // 保持 3 拍覆盖 SEND 态, 锁存单拍脉冲
            if (o_pdreq_vld) cap_pdreq_vld = 1'b1;
        end
        i_pdreq_send = 0;
        repeat (2) @(posedge clk);   // 等 SEND 时序输出锁 t1
        if (ro_t1_ns !== 64'd1000) begin
            $display("[FAIL] Pdelay: t1=%0d expected 1000", ro_t1_ns);
            tb_pass = 1'b0;
        end
        if (cap_pdreq_vld !== 1'b1) begin
            $display("[FAIL] Pdelay: o_pdreq_vld not asserted at SEND");
            tb_pass = 1'b0;
        end

        // ---- 检查 2: 收 Resp, 带 t2=1005 ----
        @(posedge clk);
        i_phc_time_ns = 1006;
        i_pdresp_rx = 1; i_t2_resp = 1005;
        repeat (3) @(posedge clk);   // 覆盖 WAIT_R 态
        i_pdresp_rx = 0;

        // ---- 检查 3: 收 RespFU, 带 t3=1010, t4=1018 ----
        @(posedge clk);
        i_phc_time_ns = 1018;
        i_pdresfu_rx = 1; i_t3_respfu = 1010;
        repeat (3) @(posedge clk);   // 覆盖 WAIT_F 态
        i_pdresfu_rx = 0;

        // ---- 检查 4: CALC 出 peerDelay ----
        repeat (2) @(posedge clk) begin  // 等 CALC 态输出, 锁存单拍脉冲
            if (ro_peer_delay_vld) cap_pd_vld = 1'b1;
        end
        if (ro_peer_delay_ns !== 64'd6) begin
            // ((1018-1000)-(1010-1005))/2 = (18-5)/2 = 6.5 -> 算术右移 -> 6
            $display("[FAIL] Pdelay: peer_delay=%0d expected 6", ro_peer_delay_ns);
            tb_pass = 1'b0;
        end
        if (cap_pd_vld !== 1'b1) begin
            $display("[FAIL] Pdelay: peer_delay_vld not asserted at CALC");
            tb_pass = 1'b0;
        end
        if (ro_t4_ns !== 64'd1018) begin
            $display("[FAIL] Pdelay: t4=%0d expected 1018", ro_t4_ns);
            tb_pass = 1'b0;
        end

        // ---- 检查 5: 对称链路特例, 再来一轮 peerDelay=0 ----
        @(posedge clk);
        i_phc_time_ns = 2000;
        @(posedge clk);
        i_pdreq_send = 1; repeat(3) @(posedge clk); i_pdreq_send = 0;
        repeat (2) @(posedge clk);
        i_phc_time_ns = 2000;  // 对端与本地同时刻: t2=t1, t4=t3
        i_pdresp_rx = 1; i_t2_resp = 2000; repeat(3) @(posedge clk); i_pdresp_rx = 0;
        repeat (2) @(posedge clk);
        i_phc_time_ns = 2010;
        i_pdresfu_rx = 1; i_t3_respfu = 2010; repeat(3) @(posedge clk); i_pdresfu_rx = 0;
        repeat (2) @(posedge clk);
        if (ro_peer_delay_ns !== 64'd0) begin
            $display("[FAIL] Pdelay: symmetric peer_delay=%0d expected 0", ro_peer_delay_ns);
            tb_pass = 1'b0;
        end

        // ---- 检查 6: 无 X ----
        @(posedge clk);
        if (ro_peer_delay_ns === 64'hx) begin
            $display("[FAIL] Pdelay: peer_delay is X");
            tb_pass = 1'b0;
        end

        if (tb_pass) begin
            $display("========================================");
            $display("  [PASS] gptp_pdelay 全部检查项通过");
            $display("========================================");
        end else begin
            $display("========================================");
            $display("  [FAIL] gptp_pdelay 存在失败项");
            $display("========================================");
        end
        $finish;
    end

endmodule
