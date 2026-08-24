/////////////////////////////////////////////////////////////////
// Testbench: tb_gptp_frame_parser
// 验证 gptp_frame_parser 从真实 PTP-over-Ethernet 字节流中提取:
//   - msgType / sequenceId / correctionField / originTimestamp
//   - 各消息类型的 EOF 脉冲
// 帧布局 (DA 起算偏移):
//   0..5   DA
//   6..11  SA
//   12..13 EtherType = 88 F7
//   14     msgType (PTP 头 byte0)
//   22..29 correctionField (8B 大端)
//   40..41 sequenceId (2B 大端)
//   48..51 originTimestamp 纳秒 (Follow_Up 携带)
/////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "gptp_defines.v"

module tb_gptp_frame_parser;

    reg                     clk;
    reg                     i_rst;
    reg [7:0]               i_rx_data;
    reg                     i_rx_vld;
    reg                     i_rx_sop;
    reg                     i_rx_eop;

    wire [3:0]              o_msg_type;
    wire [15:0]             o_seq_id;
    wire [63:0]             o_cf_ns;
    wire [63:0]             o_origin_ts_ns;
    wire                    o_sync_vld, o_follow_up_vld, o_pdreq_vld;
    wire                    o_pdresp_vld, o_pdresfu_vld, o_announce_vld;

    always #4 clk = ~clk;

    gptp_frame_parser #(.PORT_ID(4'd0)) u_dut (
        .i_clk          (clk),
        .i_rst          (i_rst),
        .i_rx_data      (i_rx_data),
        .i_rx_vld       (i_rx_vld),
        .i_rx_sop       (i_rx_sop),
        .i_rx_eop       (i_rx_eop),
        .o_msg_type     (o_msg_type),
        .o_seq_id       (o_seq_id),
        .o_cf_ns        (o_cf_ns),
        .o_origin_ts_ns (o_origin_ts_ns),
        .o_sync_vld     (o_sync_vld),
        .o_follow_up_vld(o_follow_up_vld),
        .o_pdreq_vld    (o_pdreq_vld),
        .o_pdresp_vld   (o_pdresp_vld),
        .o_pdresfu_vld  (o_pdresfu_vld),
        .o_announce_vld (o_announce_vld)
    );

    reg [7:0] frame [0:63];
    integer n, k;

    // 构造一帧: 填 DA/SA/ET, 再按偏移写字段; len 为总字节数
    task build_frame;
        input [7:0] msg_type;
        input [15:0] seq_id;
        input [63:0] cf;
        input [31:0] origin_ns;
        input integer len;
        integer i;
        begin
            for (i = 0; i < len; i = i +    1) frame[i] = 8'h00;
            frame[0]=8'h01; frame[1]=8'h80; frame[2]=8'hC2;
            frame[3]=8'h00; frame[4]=8'h00; frame[5]=8'h0E;
            frame[6]=8'hAA; frame[7]=8'hBB; frame[8]=8'hCC;
            frame[9]=8'hDD; frame[10]=8'hEE; frame[11]=8'hFF;
            frame[12]=8'h88; frame[13]=8'hF7;
            frame[14] = msg_type;
            frame[15] = 8'h02;                 // version
            frame[16] = 8'h00; frame[17]=8'h2C;// messageLength
            frame[18] = 8'h00;                 // domain
            frame[19] = 8'h00;
            frame[20] = 8'h02; frame[21]=8'h00;// flags
            frame[22]=(cf>>56)&8'hFF; frame[23]=(cf>>48)&8'hFF;
            frame[24]=(cf>>40)&8'hFF; frame[25]=(cf>>32)&8'hFF;
            frame[26]=(cf>>24)&8'hFF; frame[27]=(cf>>16)&8'hFF;
            frame[28]=(cf>>8)&8'hFF;  frame[29]=cf&8'hFF;
            frame[40]=(seq_id>>8)&8'hFF; frame[41]=seq_id&8'hFF;
            frame[48]=(origin_ns>>24)&8'hFF; frame[49]=(origin_ns>>16)&8'hFF;
            frame[50]=(origin_ns>>8)&8'hFF;  frame[51]=origin_ns&8'hFF;
        end
    endtask

    // 发送任务: 每个字节在时钟沿之前就绪, 用周期延迟保证严格一拍一字节 (clk period=8ns)
    task send_frame;
        input integer len;
        integer j;
        begin
            for (j = 0; j < len; j = j + 1) begin
                i_rx_data  = frame[j];
                i_rx_vld   = 1'b1;
                i_rx_sop   = (j == 0);
                i_rx_eop   = (j == (len-1));
                #8;                              // 经历一个完整时钟, posedge 采样本字节
            end
            i_rx_vld = 1'b0; i_rx_sop = 1'b0; i_rx_eop = 1'b0;
            #8;
        end
    endtask

    reg [63:0] expected_cf;
    reg [15:0] expected_seq;
    reg [31:0] expected_origin;
    reg [3:0]  expected_msg;
    reg        tb_pass;

    // 捕获 EOF 脉冲 (vld 仅一拍, 需锁存供帧后检查)
    reg cap_sync, cap_fu, cap_pre, cap_ann;
    always @(posedge clk) begin
        cap_sync <= o_sync_vld;
        cap_fu   <= o_follow_up_vld;
        cap_pre  <= o_pdreq_vld;
        cap_ann  <= o_announce_vld;
    end

    initial begin
        $dumpfile("sim/tb_gptp_frame_parser.vcd");
        $dumpvars(0, tb_gptp_frame_parser);
        clk = 0; i_rst = 1;
        i_rx_data = 0; i_rx_vld = 0; i_rx_sop = 0; i_rx_eop = 0;
        tb_pass = 1'b1;
        #20 i_rst = 0;

        // ---- SYNC 帧 (msgType=0), CF=0x0000000000000100, seq=1 ----
        build_frame(8'h00, 16'h0001, 64'h0000000000000100, 32'h00000000, 56);
        expected_cf    = 64'h0000000000000100;
        expected_seq   = 16'h0001;
        expected_msg   = 4'd0;
        expected_origin= 32'h00000000;
        $display("[TB] >> send SYNC  (msgType=0, cf=256, seq=1)");
        send_frame(56);
        @(posedge clk);
        if (cap_sync!==1'b1)          begin $display("[FAIL] SYNC vld"); tb_pass=1'b0; end
        if (o_msg_type!==expected_msg)begin $display("[FAIL] SYNC msg_type=%0d", o_msg_type); tb_pass=1'b0; end
        if (o_seq_id!==expected_seq)  begin $display("[FAIL] SYNC seq=%0h", o_seq_id); tb_pass=1'b0; end
        if (o_cf_ns!==expected_cf)    begin $display("[FAIL] SYNC cf=%0h", o_cf_ns); tb_pass=1'b0; end
        if (o_origin_ts_ns!==64'd0)   begin $display("[FAIL] SYNC origin should be 0 (not FU)"); tb_pass=1'b0; end

        // ---- FOLLOW_UP 帧 (msgType=8), origin=100000 ----
        build_frame(8'h08, 16'h0001, 64'h0000000000000200, 32'h000186A0, 56);
        expected_cf    = 64'h0000000000000200;
        expected_msg   = 4'd8;
        expected_origin= 32'h000186A0; // 100000
        $display("[TB] >> send FOLLOW_UP (msgType=8, origin=100000, seq=1)");
        send_frame( 56);
        @(posedge clk);
        if (cap_fu!==1'b1)            begin $display("[FAIL] FU vld"); tb_pass=1'b0; end
        if (o_msg_type!==expected_msg)begin $display("[FAIL] FU msg_type=%0d", o_msg_type); tb_pass=1'b0; end
        if (o_cf_ns!==expected_cf)    begin $display("[FAIL] FU cf=%0h", o_cf_ns); tb_pass=1'b0; end
        if (o_origin_ts_ns!==64'd100000) begin $display("[FAIL] FU origin=%0d", o_origin_ts_ns); tb_pass=1'b0; end

        // ---- PDELAY_REQ 帧 (msgType=2) ----
        build_frame( 8'h02, 16'h0002, 64'h0, 32'h0, 56);
        $display("[TB] >> send PDELAY_REQ (msgType=2)");
        send_frame(56);
        @(posedge clk);
        if (cap_pre!==1'b1) begin $display("[FAIL] PREQ vld"); tb_pass=1'b0; end

        // ---- ANNOUNCE 帧 (msgType=11) ----
        build_frame(8'h0B, 16'h0003, 64'h0, 32'h0, 56);
        $display("[TB] >> send ANNOUNCE (msgType=11)");
        send_frame(56);
        @(posedge clk);
        if (cap_ann!==1'b1) begin $display("[FAIL] ANNOUNCE vld"); tb_pass=1'b0; end

        // ---- 非 PTP 帧 (ET != 88F7): 不应产生任何有效脉冲 ----
        for (k=0;k<14;k=k+1) frame[k]= (k<6)?8'h01:(k<12)?8'h02:(k==12?8'h08:8'h00); // ET=0800
        frame[14]=8'h00;
        $display("[TB] >> send non-PTP frame (ET=0800)");
        send_frame(20);
        @(posedge clk);
        if (cap_sync||cap_fu||cap_pre||cap_ann) begin
            $display("[FAIL] non-PTP frame produced pulses"); tb_pass=1'b0;
        end

        if (tb_pass) $display("[PASS] gptp_frame_parser field extraction OK");
        else         $display("[FAIL] gptp_frame_parser");
        $finish;
    end
endmodule
