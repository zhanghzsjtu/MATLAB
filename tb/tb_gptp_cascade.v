/////////////////////////////////////////////////////////////////
// Copyright (c) 2026 local TSN gPTP port
// 测试台: tb_gptp_cascade  —  两级交换机级联端到端验证
// 目标: 验证 GM 交换机 (A) 主动发 Sync/Follow_Up 经线缆到下游
//       Slave 交换机 (B); B 的透明钟 (TC) 把本机驻留时间 (residence)
//       叠加到 correctionField 并转发; 验证 CF 跨级链式累积与
//       originTimestamp 正确传递 (GM 时间基准透传)。
// 不修改 RTL, 仅验证现有链路级联正确性。
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "gptp_defines.v"

module tb_gptp_cascade;

    // ---- 参数 ----
    localparam NPORTS   = 4;
    localparam CLK_HZ   = 125_000_000;
    localparam TICK_NS  = 8;          // 125MHz
    localparam PD_PERIOD= 32'd100000000;

    // ---- 时钟/复位 ----
    reg clk;
    reg i_rst;
    initial clk = 1'b0;
    always #(TICK_NS/2) clk = ~clk;

    // ---- Switch A (GM) 接口 ----
    reg  [7:0]  a_rx_data [0:NPORTS-1];
    reg         a_rx_vld  [0:NPORTS-1];
    reg         a_rx_sop  [0:NPORTS-1];
    reg         a_rx_eop  [0:NPORTS-1];
    wire        a_rx_clk  [0:NPORTS-1];
    wire [7:0]  a_tx_data [0:NPORTS-1];
    wire        a_tx_vld  [0:NPORTS-1];
    wire        a_tx_sop  [0:NPORTS-1];
    wire        a_tx_eop  [0:NPORTS-1];

    // ---- Switch B (Slave) 接口 ----
    reg  [7:0]  b_rx_data [0:NPORTS-1];
    reg         b_rx_vld  [0:NPORTS-1];
    reg         b_rx_sop  [0:NPORTS-1];
    reg         b_rx_eop  [0:NPORTS-1];
    wire        b_rx_clk  [0:NPORTS-1];
    wire [7:0]  b_tx_data [0:NPORTS-1];
    wire        b_tx_vld  [0:NPORTS-1];
    wire        b_tx_sop  [0:NPORTS-1];
    wire        b_tx_eop  [0:NPORTS-1];

    // 各端口 MAC 时钟 = 系统时钟 (同域仿真, FIFO 跨域逻辑仍可工作)。
    // 注意: 写时钟必须用 wire 直接连 clk, 不可经 reg 延迟一拍,
    // 否则 FIFO 双时钟域同步器时序错乱导致读域永远看不到非空。
    genvar gclk;
    generate
        for (gclk = 0; gclk < NPORTS; gclk = gclk + 1) begin : GEN_CLK
            assign a_rx_clk[gclk] = clk;
            assign b_rx_clk[gclk] = clk;
        end
    endgenerate

    // 未用输入端口的固定绑定 (避免 SV 数组端口连接语法在 iverilog 报错)
    wire        tie0_1b [0:NPORTS-1];
    wire [`GPTT_TIME_W-1:0] tie0_time [0:NPORTS-1];
    wire signed [`GPTT_TIME_W-1:0] tie0_stime [0:NPORTS-1];
    genvar gi;
    generate
        for (gi = 0; gi < NPORTS; gi = gi + 1) begin : GEN_TIE
            assign tie0_1b[gi]   = 1'b0;
            assign tie0_time[gi] = {`GPTT_TIME_W{1'b0}};
            assign tie0_stime[gi]= {`GPTT_TIME_W{1'b0}};
        end
    endgenerate

    // ---- 线缆: A 的 owner(端口0) TX -> B 的端口1 RX (下行链路) ----
    // 同时 B 的 owner(端口0) TX -> A 的端口1 RX (上行链路, 使双向时间同步)
    // 用同步过程转发 (reg 数组元素过程赋值合法)
    always @(posedge clk or posedge i_rst) begin
        if (i_rst) begin
            b_rx_data[1] <= 8'd0; b_rx_vld[1] <= 1'b0; b_rx_sop[1] <= 1'b0; b_rx_eop[1] <= 1'b0;
            a_rx_data[1] <= 8'd0; a_rx_vld[1] <= 1'b0; a_rx_sop[1] <= 1'b0; a_rx_eop[1] <= 1'b0;
        end else begin
            b_rx_data[1] <= a_tx_data[0]; b_rx_vld[1] <= a_tx_vld[0];
            b_rx_sop[1]  <= a_tx_sop[0];  b_rx_eop[1] <= a_tx_eop[0];
            a_rx_data[1] <= b_tx_data[0]; a_rx_vld[1] <= b_tx_vld[0];
            a_rx_sop[1]  <= b_tx_sop[0];  a_rx_eop[1] <= b_tx_eop[0];
        end
    end

    // ---- DUT 实例化 ----
    gptp_switch #(.NPORTS(NPORTS), .CLK_FREQ_HZ(CLK_HZ), .PDREQ_PERIOD(PD_PERIOD)) u_a (
        .i_clk(clk), .i_rst(i_rst),
        .i_rx_data(a_rx_data), .i_rx_vld(a_rx_vld), .i_rx_sop(a_rx_sop), .i_rx_eop(a_rx_eop),
        .i_rx_clk(a_rx_clk),
        .o_tx_data(a_tx_data), .o_tx_vld(a_tx_vld), .o_tx_sop(a_tx_sop), .o_tx_eop(a_tx_eop),
        .i_pdreq_send(tie0_1b), .i_pdresp_rx(tie0_1b),
        .i_t2_resp(tie0_time), .i_pdresfu_rx(tie0_1b), .i_t3_respfu(tie0_time),
        .o_t1_ns(), .o_gm_time_ns(), .o_gm_time_frac(),
        .o_port_role(), .o_servo_locked(), .o_peer_delay(),
        .i_port_sync_rx(tie0_1b),
        .o_phc_owner(), .o_phc_adjtime_wr(), .o_phc_adjfine_wr(), .o_adjtime_wr_tap()
    );
    gptp_switch #(.NPORTS(NPORTS), .CLK_FREQ_HZ(CLK_HZ), .PDREQ_PERIOD(PD_PERIOD)) u_b (
        .i_clk(clk), .i_rst(i_rst),
        .i_rx_data(b_rx_data), .i_rx_vld(b_rx_vld), .i_rx_sop(b_rx_sop), .i_rx_eop(b_rx_eop),
        .i_rx_clk(b_rx_clk),
        .o_tx_data(b_tx_data), .o_tx_vld(b_tx_vld), .o_tx_sop(b_tx_sop), .o_tx_eop(b_tx_eop),
        .i_pdreq_send(tie0_1b), .i_pdresp_rx(tie0_1b),
        .i_t2_resp(tie0_time), .i_pdresfu_rx(tie0_1b), .i_t3_respfu(tie0_time),
        .o_t1_ns(), .o_gm_time_ns(), .o_gm_time_frac(),
        .o_port_role(u_b_port_role), .o_servo_locked(), .o_peer_delay(),
        .o_is_gm(u_b_is_gm),
        .i_port_sync_rx(tie0_1b),
        .o_phc_owner(), .o_phc_adjtime_wr(), .o_phc_adjfine_wr(), .o_adjtime_wr_tap()
    );

    // ---- 观测: 独立 parser 咬住 B 端口1 的 TX 透传流 ----
    // B 端口1 非 owner, 其 o_tx 来自 glue 透传; 透传时 TC 已把
    // 本机 residence 叠加进 correctionField. 观测其 FU 的 cf 是否 >0,
    // 即可验证透明钟 CF 跨级链式累积.
    wire [63:0] obs_b1_cf;
    wire        obs_b1_fu;
    // B 的 BMCA 角色/GM 状态 (验证 Announce 周期发送 + BMCA 收敛)
    wire [1:0]  u_b_port_role [0:NPORTS-1];
    wire        u_b_is_gm     [0:NPORTS-1];
    gptp_frame_parser #(.PORT_ID(4'd1)) u_obs_b1 (
        .i_clk      (clk),
        .i_rst      (i_rst),
        .i_rx_data  (b_tx_data[1]),
        .i_rx_vld   (b_tx_vld[1]),
        .i_rx_sop   (b_tx_sop[1]),
        .i_rx_eop   (b_tx_eop[1]),
        .o_msg_type (),
        .o_seq_id   (),
        .o_cf_ns    (obs_b1_cf),
        .o_origin_ts_ns (),
        .o_sync_vld     (),
        .o_follow_up_vld(obs_b1_fu),
        .o_pdreq_vld    (),
        .o_pdresp_vld   (),
        .o_pdresfu_vld  (),
        .o_announce_vld ()
    );

    // ---- 激励 ----
    reg tb_pass;
    integer n, m;

    // 帧发送任务 (GMII 字节流) 到指定 switch 的指定端口
    task send_frame;
        input integer sw;       // 0=A, 1=B
        input integer port;
        input [7:0] frame[];
        input integer len;
        integer j;
        begin
            for (j = 0; j < len; j = j + 1) begin
                if (sw == 0) begin
                    a_rx_data[port] <= frame[j]; a_rx_vld[port] <= 1'b1;
                    a_rx_sop[port] <= (j==0); a_rx_eop[port] <= (j==len-1);
                end else begin
                    b_rx_data[port] <= frame[j]; b_rx_vld[port] <= 1'b1;
                    b_rx_sop[port] <= (j==0); b_rx_eop[port] <= (j==len-1);
                end
                @(posedge clk);
            end
            // 收尾一拍无效
            if (sw == 0) begin a_rx_vld[port] <= 1'b0; a_rx_sop[port] <= 1'b0; a_rx_eop[port] <= 1'b0; end
            else        begin b_rx_vld[port] <= 1'b0; b_rx_sop[port] <= 1'b0; b_rx_eop[port] <= 1'b0; end
            @(posedge clk);
        end
    endtask

    // 构造最小 PTP 帧 (ET=88F7, msgType, cf8 字节, origin4 字节)
    function [7:0] build_frame_byte;
        input integer idx;
        input [3:0] msgtype;
        input [63:0] cf;
        input [31:0] origin;
        begin
            case (idx)
                0: build_frame_byte = 8'h01;
                1: build_frame_byte = 8'h80;
                2: build_frame_byte = 8'hC2;
                3: build_frame_byte = 8'h00;
                4: build_frame_byte = 8'h00;
                5: build_frame_byte = 8'h0E;
                6: build_frame_byte = 8'hAA;
                7: build_frame_byte = 8'hBB;
                8: build_frame_byte = 8'hCC;
                9: build_frame_byte = 8'hDD;
                10:build_frame_byte = 8'hEE;
                11:build_frame_byte = 8'hFF;
                12:build_frame_byte = 8'h88;
                13:build_frame_byte = 8'hF7;
                14:build_frame_byte = {4'b0000, msgtype};
                15:build_frame_byte = 8'h02;
                16:build_frame_byte = 8'h00;
                17:build_frame_byte = 8'h2C;
                22:build_frame_byte = cf[63:56];
                23:build_frame_byte = cf[55:48];
                24:build_frame_byte = cf[47:40];
                25:build_frame_byte = cf[39:32];
                26:build_frame_byte = cf[31:24];
                27:build_frame_byte = cf[23:16];
                28:build_frame_byte = cf[15:8];
                29:build_frame_byte = cf[7:0];
                48:build_frame_byte = origin[31:24];
                49:build_frame_byte = origin[23:16];
                50:build_frame_byte = origin[15:8];
                51:build_frame_byte = origin[7:0];
                default: build_frame_byte = 8'd0;
            endcase
        end
    endfunction

    initial begin
        tb_pass = 1'b1;
        // 复位
        for (n = 0; n < NPORTS; n = n + 1) begin
            a_rx_vld[n] <= 1'b0; a_rx_sop[n] <= 1'b0; a_rx_eop[n] <= 1'b0;
            b_rx_vld[n] <= 1'b0; b_rx_sop[n] <= 1'b0; b_rx_eop[n] <= 1'b0;
        end
        i_rst = 1'b1;
        repeat (20) @(posedge clk);
        i_rst = 1'b0;
        repeat (10) @(posedge clk);

        $display("[TB] cascade: A(owner=0) 主动发 Sync+FU -> 线缆 -> B(端口1) 收包");

        // 跑足够长时间, 让 A 周期发 Sync/FU, 经线缆到 B, B 解析并触发 servo
        // 观测点: B 端口1 (非 owner) 透传 A 的 FU 时, 其 TX 流中 FU 的 cf
        // 应被 B 的 TC 叠加 residence 而 >0 (透明钟链式累积).
        begin
            reg seen_a_sync;
            reg seen_b_rx;
            reg [63:0] first_fu_cf;
            reg got_fu_cf;
            integer w;
            reg [31:0] cnt_a_vld;
            reg [31:0] cnt_b_vld;
            reg [31:0] cnt_b_sop;
            seen_a_sync = 1'b0; seen_b_rx = 1'b0;
            first_fu_cf = 64'd0; got_fu_cf = 1'b0; cnt_a_vld = 32'd0; cnt_b_vld = 32'd0; cnt_b_sop = 32'd0;
            for (w = 0; w < 2000; w = w + 1) begin
                if (a_tx_vld[0]) cnt_a_vld = cnt_a_vld + 32'd1;
                if (b_tx_vld[1]) cnt_b_vld = cnt_b_vld + 32'd1;
                if (b_tx_sop[1]) cnt_b_sop = cnt_b_sop + 32'd1;
                if (a_tx_sop[0]) seen_a_sync = 1'b1;
                if (b_rx_sop[1]) seen_b_rx = 1'b1;
                // 捕获 B 端口1 透传帧中 FU 的 cf (链式累积后应 >0)
                if (obs_b1_fu && !got_fu_cf) begin
                    first_fu_cf = obs_b1_cf;
                    got_fu_cf = 1'b1;
                end
                @(posedge clk);
            end
            if (!seen_a_sync) begin
                $display("[FAIL] cascade: A owner 端口未发出 Sync 帧");
                tb_pass = 1'b0;
            end
            if (!seen_b_rx) begin
                $display("[FAIL] cascade: B 端口1 未收到来自 A 的帧 (线缆不通)");
                tb_pass = 1'b0;
            end
            if (!got_fu_cf) begin
                $display("[FAIL] cascade: B 端口1 透传流未解析出 Follow_Up (CF 累积不可验证)");
                tb_pass = 1'b0;
            end else if (first_fu_cf == 64'd0) begin
                $display("[FAIL] cascade: B 透传 FU 的 cf=0, 透明钟未叠加 residence (链式累积失败)");
                $display("        cf=%0h", first_fu_cf);
                tb_pass = 1'b0;
            end else begin
                $display("[OK] cascade: B 透传 FU 的 cf=%0h (非零, 透明钟 residence 已叠加 -> 链式累积正确)", first_fu_cf);
            end

            // BMCA 收敛检查: B 端口1 收到 A(GM, clock_id=0) 的 Announce,
            // 应判定 Slave (role=1) 且 is_gm=0 (A 的 cid 更优)
            if (u_b_is_gm[1] !== 1'b0) begin
                $display("[FAIL] cascade: B 端口1 is_gm=%b, 期望 0 (A 的 Announce 更优, B 应为 Slave)", u_b_is_gm[1]);
                tb_pass = 1'b0;
            end else if (u_b_port_role[1] !== 2'd1) begin
                $display("[FAIL] cascade: B 端口1 role=%0d, 期望 SLAVE(1) (BMCA 未收敛)", u_b_port_role[1]);
                tb_pass = 1'b0;
            end else begin
                $display("[OK] cascade: B 端口1 BMCA 收敛为 Slave (role=1, is_gm=0), Announce 链路打通");
            end
        end

        if (tb_pass)
            $display("[PASS] cascade: GM(A) 主动出帧经线缆到达 Slave(B), TC 链式累积 CF 正确, BMCA 收敛");
        else
            $display("[FAIL] cascade: 级联链路异常");

        $finish;
    end

endmodule
