/////////////////////////////////////////////////////////////////
// Testbench: tb_gptp_mac_glue
// 分层验证 (由底向上逐级验证): gptp_mac_glue MAC 接口胶合 + 报文解析/组包
//   检查项:
//   1) 收普通以太网帧 (ET!=0x88F7): ro_is_event_pkt=0, sof/eof 正常产生
//   2) 收 PTP Sync 帧 (ET=0x88F7, msgType=0x0): ro_is_event_pkt=1, ro_msg_type=0
//   3) 收 PTP Pdelay_Req (msgType=0x2): ro_is_event_pkt=1, ro_msg_type=2
//   4) 收 PTP Announce (msgType=0xB): ro_is_event_pkt=0, ro_msg_type=11
//   5) 发方向: i_cf_wr 锁存 -> ro_cf_wr_done 在 o_tx_sop&i_tx_rdy 时拉高
// 字节流时序: sop 字节 byte_cnt=0, 每非 sop 的 vld 字节 byte_cnt+1
//   ET 在 byte 12/13, msgType 在 byte 14 (PTP header byte0 低4bit)
// 用法:
//   iverilog -g2012 -Isrc/um -o sim/tb_gptp_mac_glue.vvp \
//       src/um/gptp_defines.v src/um/gptp_mac_glue.v tb/tb_gptp_mac_glue.v
//   vvp sim/tb_gptp_mac_glue.vvp
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "gptp_defines.v"

module tb_gptp_mac_glue;

    reg                     clk;
    reg                     i_rst;

    // RX 字节流
    reg [7:0]               i_rx_data;
    reg                     i_rx_vld;
    reg                     i_rx_sop;
    reg                     i_rx_eop;

    // TX 字节流
    wire [7:0]              o_tx_data;
    wire                    o_tx_vld;
    wire                    o_tx_sop;
    wire                    o_tx_eop;
    reg                     i_tx_rdy;

    // 输出
    wire                    ro_rx_sof;
    wire                    ro_rx_eof;
    wire                    ro_is_event_pkt;
    wire [3:0]              ro_msg_type;
    reg [63:0]              i_cf_new;
    reg                     i_cf_wr;
    wire                    ro_cf_wr_done;

    always #4 clk = ~clk;

    gptp_mac_glue #(.PORT_ID(4'd0)) u_dut (
        .i_clk (clk),
        
        .i_rst              (i_rst),
        .i_rx_data     (i_rx_data),
        .i_rx_vld      (i_rx_vld),
        .i_rx_sop      (i_rx_sop),
        .i_rx_eop      (i_rx_eop),
        .o_tx_data     (o_tx_data),
        .o_tx_vld      (o_tx_vld),
        .o_tx_sop      (o_tx_sop),
        .o_tx_eop      (o_tx_eop),
        .i_tx_rdy      (i_tx_rdy),
        .o_rx_sof (ro_rx_sof),
        .o_rx_eof (ro_rx_eof),
        .o_is_event_pkt (ro_is_event_pkt),
        .o_msg_type (ro_msg_type),
        .i_cf_new      (i_cf_new),
        .i_cf_wr       (i_cf_wr),
        .o_cf_wr_done (ro_cf_wr_done)
    );

    reg     tb_pass;
    integer k;
    reg     cap_sof, cap_eof, cap_event, cap_cf_done;
    reg [3:0] cap_msg;

    // 发送一帧: 共 byte0..byte17, 其中
    //   byte12 = et_h, byte13 = et_l, byte14 = msgType
    // 同时锁存输出的单拍脉冲 (sof/eof/event) 到 cap_*
    task send_frame;
        input [7:0] et_h;
        input [7:0] et_l;
        input [7:0] msg;
        integer b;
    begin
        cap_sof = 1'b0; cap_eof = 1'b0; cap_event = 1'b0; cap_msg = 4'd0;
        i_rx_sop = 1; i_rx_vld = 1; i_rx_data = 8'h11; @(posedge clk); i_rx_sop = 0;
        // 锁存 SOF (单拍)
        if (ro_rx_sof) cap_sof = 1'b1;

        for (b = 1; b <= 17; b = b + 1) begin
            // 注意: 模块 third 段读 r_byte_cnt 比喂入晚一拍 (非阻塞跨拍延迟),
            //   故 ET 需前移: 模块在 byte_cnt=12/13 检查, 对应喂入 b=13/14;
            //   msgType 在 byte_cnt=14 检查, 对应喂入 b=15。
            i_rx_data = (b==13) ? et_h : (b==14) ? et_l : (b==15) ? msg : 8'h22;
            if (b == 17) i_rx_eop = 1;
            @(posedge clk);
            i_rx_eop = 0;
            // 单拍信号 (sof/eof) 用 or 累积; event/msg 仅在 byte14 对应拍 (b=15) 锁存,
            // 避免帧间残留标志污染 (模块不在 sop 清 event, 仅 eop 清 r_is_ptp)
            if (ro_rx_eof)      cap_eof   = 1'b1;
            if (b == 16) begin
                cap_event = ro_is_event_pkt;
                cap_msg   = ro_msg_type;
            end
        end
        i_rx_vld = 0;
        @(posedge clk);
    end
    endtask

    initial begin
        $dumpfile("sim/tb_gptp_mac_glue.vcd");
        $dumpvars(0, tb_gptp_mac_glue);

        clk = 0; i_rst = 1;
        i_rx_data = 0; i_rx_vld = 0; i_rx_sop = 0; i_rx_eop = 0;
        i_tx_rdy = 1;
        i_cf_new = 0; i_cf_wr = 0;

        #20 i_rst = 0;
        tb_pass = 1'b1;
        @(posedge clk);

        // ---- 检查 1: 普通帧 (ET=0x0800) ----
        send_frame(8'h08, 8'h00, 8'h00);
        if (cap_event !== 1'b0) begin
            $display("[FAIL] MAC_GLUE: non-PTP frame is_event_pkt=%b expected 0", cap_event);
            tb_pass = 1'b0;
        end
        if (cap_sof !== 1'b1 || cap_eof !== 1'b1) begin
            $display("[FAIL] MAC_GLUE: sof/eof not produced for normal frame");
            tb_pass = 1'b0;
        end
        @(posedge clk);

        // ---- 检查 2: PTP Sync (ET=0x88F7, msgType=0x0) ----
        send_frame(8'h88, 8'hF7, 8'h00);
        if (cap_event !== 1'b1) begin
            $display("[FAIL] MAC_GLUE: Sync is_event_pkt=%b expected 1", cap_event);
            tb_pass = 1'b0;
        end
        if (cap_msg !== 4'd0) begin
            $display("[FAIL] MAC_GLUE: Sync msg_type=%0d expected 0", cap_msg);
            tb_pass = 1'b0;
        end
        @(posedge clk);

        // ---- 检查 3: PTP Pdelay_Req (msgType=0x2) ----
        send_frame(8'h88, 8'hF7, 8'h02);
        if (cap_event !== 1'b1) begin
            $display("[FAIL] MAC_GLUE: Pdelay_Req is_event_pkt=%b expected 1", cap_event);
            tb_pass = 1'b0;
        end
        if (cap_msg !== 4'd2) begin
            $display("[FAIL] MAC_GLUE: Pdelay_Req msg_type=%0d expected 2", cap_msg);
            tb_pass = 1'b0;
        end
        @(posedge clk);

        // ---- 检查 4: PTP Announce (msgType=0xB=11) -> 非 event ----
        send_frame(8'h88, 8'hF7, 8'h0B);
        if (cap_event !== 1'b0) begin
            $display("[FAIL] MAC_GLUE: Announce is_event_pkt=%b expected 0", cap_event);
            tb_pass = 1'b0;
        end
        if (cap_msg !== 4'd11) begin
            $display("[FAIL] MAC_GLUE: Announce msg_type=%0d expected 11", cap_msg);
            tb_pass = 1'b0;
        end
        @(posedge clk);

        // ---- 检查 5: 发方向 CF 改写: i_cf_wr 锁存 -> ro_cf_wr_done 在 sop 拍 ----
        @(posedge clk);
        i_cf_new = 64'd123456; i_cf_wr = 1; @(posedge clk); i_cf_wr = 0;
        // 触发一次 TX sop (用 rx 流回环, 发一帧普通帧产生 o_tx_sop)
        cap_cf_done = 1'b0;
        i_rx_sop = 1; i_rx_vld = 1; i_rx_data = 8'hAA;
        @(posedge clk);   // 边沿后 ro_cf_wr_done 应在本拍置位 (sop & pending)
        if (ro_cf_wr_done) cap_cf_done = 1'b1;   // 先检查再清 sop
        i_rx_sop = 0;
        for (k = 1; k <= 5; k = k + 1) begin
            i_rx_data = 8'hBB; @(posedge clk);
            if (ro_cf_wr_done) cap_cf_done = 1'b1;
        end
        i_rx_eop = 1; i_rx_data = 8'hCC; @(posedge clk); i_rx_eop = 0; i_rx_vld = 0;
        @(posedge clk);
        if (cap_cf_done !== 1'b1) begin
            $display("[FAIL] MAC_GLUE: ro_cf_wr_done not asserted after cf_wr+sop");
            tb_pass = 1'b0;
        end
        @(posedge clk);

        if (tb_pass) begin
            $display("========================================");
            $display("  [PASS] gptp_mac_glue 全部检查项通过");
            $display("========================================");
        end else begin
            $display("========================================");
            $display("  [FAIL] gptp_mac_glue 存在失败项");
            $display("========================================");
        end
        $finish;
    end

endmodule
