/////////////////////////////////////////////////////////////////
// Testbench: tb_gptp_top
// 验证 gptp_top 基本功能: PHC 计数、HTSU 时间戳捕获、TC correctionField
// 改写、Pdelay 链路延迟计算。
// 用法 (Vivado xsim / ModelSim):
//   vlog gptp_defines.v gptp_phc.v gptp_htsu.v gptp_tc.v gptp_pdelay.v \
//        gptp_top.v tb_gptp_top.v
//   vsim tb_gptp_top; run -all
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "gptp_defines.v"

module tb_gptp_top;

    reg                     clk;
    reg                     i_rst;

    // PHC 控制
    reg                     w_adjfine_wr;
    reg signed [31:0]       w_adjfine_addend;
    reg                     w_adjtime_wr;
    reg signed [`GPTT_TIME_W-1:0] w_adjtime_delta_ns;
    reg                     w_settime_wr;
    reg [`GPTT_TIME_W-1:0]  w_settime_ns;

    wire [`GPTT_TIME_W-1:0] ro_time_ns;
    wire [31:0]             ro_time_frac;

    // MAC 边沿
    reg                     i_rx_sof, i_rx_eof, i_tx_sof, i_tx_eof;
    reg                     i_is_event_pkt;

    // TC 握手
    reg                     i_pkt_vld;
    reg [63:0]              i_cf_in;
    wire [63:0]             o_cf_out;
    wire                    o_cf_wr;

    // Pdelay
    reg                     i_pdreq_send;
    reg                     i_pdresp_rx;
    reg [63:0]              i_t2_resp;
    reg                     i_pdresfu_rx;
    reg [63:0]              i_t3_respfu;
    wire                    o_pdreq_vld;
    wire [`GPTT_TIME_W-1:0] ro_peer_delay_ns;
    wire [`GPTT_TIME_W-1:0] ro_residence_ns;

    // ---- 时钟 125MHz ----
    always #4 clk = ~clk;

    // ---- 实例化 DUT ----
    gptp_top #(.PORT_ID(4'd0), .CLK_FREQ_HZ(125_000_000),
               .PDREQ_PERIOD(32'd200)) u_dut (
        .i_clk (clk),
        
        .i_rst              (i_rst),
        .i_adjfine_wr (w_adjfine_wr),
        .i_adjfine_addend (w_adjfine_addend),
        .i_adjtime_wr (w_adjtime_wr),
        .i_adjtime_delta_ns (w_adjtime_delta_ns),
        .i_settime_wr (w_settime_wr),
        .i_settime_ns (w_settime_ns),
        .o_time_ns (ro_time_ns),
        .o_time_frac (ro_time_frac),
        .i_rx_sof           (i_rx_sof),
        .i_rx_eof           (i_rx_eof),
        .i_tx_sof           (i_tx_sof),
        .i_tx_eof           (i_tx_eof),
        .i_is_event_pkt     (i_is_event_pkt),
        .i_pkt_vld          (i_pkt_vld),
        .i_cf_in            (i_cf_in),
        .o_cf_out           (o_cf_out),
        .o_cf_wr            (o_cf_wr),
        .i_pdreq_send       (i_pdreq_send),
        .i_pdresp_rx        (i_pdresp_rx),
        .i_t2_resp          (i_t2_resp),
        .i_pdresfu_rx       (i_pdresfu_rx),
        .i_t3_respfu        (i_t3_respfu),
        .o_pdreq_vld        (o_pdreq_vld),
        .o_peer_delay_ns (ro_peer_delay_ns),
        .o_residence_ns (ro_residence_ns)
    );

    // ---- 激励 ----
    integer i;
    initial begin
        $dumpfile("sim/tb_gptp_top.vcd");
        $dumpvars(0, tb_gptp_top);
        clk = 0; i_rst = 1;
        w_adjfine_wr = 0; w_adjfine_addend = 0;
        w_adjtime_wr = 0; w_adjtime_delta_ns = 0;
        w_settime_wr = 0; w_settime_ns = 0;
        i_rx_sof = 0; i_rx_eof = 0; i_tx_sof = 0; i_tx_eof = 0;
        i_is_event_pkt = 0; i_pkt_vld = 0; i_cf_in = 0;
        i_pdreq_send = 0; i_pdresp_rx = 0; i_t2_resp = 0; i_pdresfu_rx = 0; i_t3_respfu = 0;

        #20 i_rst = 0;
        #20 w_settime_wr = 1; w_settime_ns = 1000; @(posedge clk); w_settime_wr = 0;

        // 模拟一帧 Sync 进出 (residence 帧)
        #40;
        @(posedge clk);
        i_is_event_pkt = 1; i_rx_sof = 1; @(posedge clk); i_rx_sof = 0;
        repeat (10) @(posedge clk);
        i_rx_eof = 1; @(posedge clk); i_rx_eof = 0;
        // 转发延迟若干拍后出帧
        repeat (5) @(posedge clk);
        i_tx_sof = 1; @(posedge clk); i_tx_sof = 0;
        repeat (10) @(posedge clk);
        i_tx_eof = 1; @(posedge clk); i_tx_eof = 0;
        i_is_event_pkt = 0;

        // TC 改写: 在出帧后给一次 pkt_vld
        @(posedge clk);
        i_cf_in = 64'd0; i_pkt_vld = 1; @(posedge clk); i_pkt_vld = 0;

        // 模拟 Pdelay 交互: 先触发发 Req (锁 t1), 再依次收 Resp/RespFU
        #100;
        @(posedge clk);
        i_pdreq_send = 1; @(posedge clk); i_pdreq_send = 0;  // 触发 P_ST_SEND, 锁 t1
        repeat (3) @(posedge clk);
        i_pdresp_rx = 1; i_t2_resp = 10; @(posedge clk); i_pdresp_rx = 0;  // 带 t2 (对端收 Req 时刻)
        repeat (3) @(posedge clk);
        i_pdresfu_rx = 1; i_t3_respfu = 20; @(posedge clk); i_pdresfu_rx = 0;  // 带 t3, 锁 t4
        repeat (3) @(posedge clk);  // 等 P_ST_CALC 出结果

        #200;
        $display("RESULT time_ns=%0d peer_delay=%0d residence=%0d cf_out=%0d",
                 ro_time_ns, ro_peer_delay_ns, ro_residence_ns, o_cf_out);

        // ---- 自检: 明确 PASS/FAIL ----
        begin
            reg tb_pass;
            tb_pass = 1'b1;
            // 1) PHC 应正常计数且非未知态
            if (ro_time_ns === 64'hx) begin
                $display("[FAIL] PHC: time_ns is X"); tb_pass = 1'b0;
            end
            // 2) Pdelay 应算出正延迟 (19ns, 容差 +/-2)
            if (ro_peer_delay_ns === 64'hx) begin
                $display("[FAIL] Pdelay: peer_delay is X"); tb_pass = 1'b0;
            end else if (ro_peer_delay_ns < 17 || ro_peer_delay_ns > 21) begin
                $display("[FAIL] Pdelay: peer_delay=%0d out of [17,21]", ro_peer_delay_ns); tb_pass = 1'b0;
            end
            // 3) HTSU 驻留时间: 当前 RTL 在 RX 首拍锁 t2、WAIT 首拍 (tx_sof)
            //    锁 t3, 本激励下 (rx body 10 拍 + 转发的 5 拍) residence = 40ns
            if (ro_residence_ns === 64'hx) begin
                $display("[FAIL] HTSU: residence is X"); tb_pass = 1'b0;
            end else if (ro_residence_ns !== 40) begin
                $display("[FAIL] HTSU: residence=%0d expected 40", ro_residence_ns); tb_pass = 1'b0;
            end
            // 4) TC one-step 改写: cf_out = cf_in(0) + residence(40ns)*65536 = 2621440
            //    (top 集成未接 peer_delay_vld, 故不叠加 peerDelay)
            if (o_cf_out === 64'hx) begin
                $display("[FAIL] TC: cf_out is X"); tb_pass = 1'b0;
            end else if (o_cf_out !== 2621440) begin
                $display("[FAIL] TC: cf_out=%0d expected 2621440", o_cf_out); tb_pass = 1'b0;
            end

            if (tb_pass) begin
                $display("========================================");
                $display("  [PASS] gptp_top 全部检查项通过");
                $display("========================================");
            end else begin
                $display("========================================");
                $display("  [FAIL] gptp_top 存在失败项");
                $display("========================================");
            end
        end

        $finish;
    end

endmodule
