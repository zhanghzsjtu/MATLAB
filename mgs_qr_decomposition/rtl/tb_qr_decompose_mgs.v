//==========================================================================
// tb_qr_decompose_mgs.v
// 验证 qr_decompose_mgs 与 MATLAB 定点参考(mgs_qr_fixed)结果逐位一致
// 激励: rtl_vec/a_mem.hex ; 期望: rtl_vec/q_golden.hex, r_golden.hex
// 运行: iverilog -g2012 -o qr_sim.vvp qr_decompose_mgs.v tb_qr_decompose_mgs.v
//        vvp qr_sim.vvp
//==========================================================================

`timescale 1ns/1ps

module tb_qr_decompose_mgs;

parameter W = 16;
parameter M = 8;
parameter K = 4;
localparam AW = $clog2(M*K);
localparam RW = $clog2(K*(K+1)/2);

reg                  i_clk = 1'b0;
reg                  i_rst = 1'b1;
reg                  i_start = 1'b0;
reg                  i_a_wr_en = 1'b0;
reg [AW-1:0]         i_a_wr_addr = 'd0;
reg [W-1:0]          i_a_wr_data = 'd0;
reg [AW-1:0]         i_q_rd_addr = 'd0;
reg [RW-1:0]         i_r_rd_idx = 'd0;
wire                 o_busy;
wire                 o_done;
wire [W-1:0]         o_q_rd_data;
wire [W-1:0]         o_r_rd_data;

reg [W-1:0] a_mem [0:M*K-1];
reg [W-1:0] q_gold [0:M*K-1];
reg [W-1:0] r_gold [0:K*(K+1)/2-1];

integer addr;
integer err_cnt;
reg done_q;

qr_decompose_mgs #(
    .W (W),
    .M (M),
    .K (K)
) dut (
    .i_clk      (i_clk),
    .i_rst      (i_rst),
    .i_start    (i_start),
    .i_a_wr_en  (i_a_wr_en),
    .i_a_wr_addr(i_a_wr_addr),
    .i_a_wr_data(i_a_wr_data),
    .o_busy     (o_busy),
    .o_done     (o_done),
    .i_q_rd_addr(i_q_rd_addr),
    .o_q_rd_data(o_q_rd_data),
    .i_r_rd_idx (i_r_rd_idx),
    .o_r_rd_data(o_r_rd_data)
);

always #5 i_clk = ~i_clk;

initial begin
    $readmemh("rtl_vec/a_mem.hex", a_mem);
    $readmemh("rtl_vec/q_golden.hex", q_gold);
    $readmemh("rtl_vec/r_golden.hex", r_gold);

    // 复位
    i_rst = 1'b1;
    repeat (3) @(posedge i_clk);
    i_rst = 1'b0;

    // 写入 A 矩阵
    for (addr = 0; addr < M*K; addr = addr + 1) begin
        @(posedge i_clk);
        i_a_wr_en  = 1'b1;
        i_a_wr_addr = addr;
        i_a_wr_data = a_mem[addr];
    end
    @(posedge i_clk);
    i_a_wr_en = 1'b0;

    // 启动分解
    @(posedge i_clk);
    i_start = 1'b1;
    @(posedge i_clk);
    i_start = 1'b0;

    // 等待完成(o_done 打拍后下降沿判据: 打拍检测)
    done_q = 1'b0;
    while (!done_q) begin
        @(posedge i_clk);
        done_q = o_done;
    end

    // 比较 Q
    err_cnt = 0;
    $display("\n=== Q Matrix (M=%0d, K=%0d) ===", M, K);
    for (addr = 0; addr < M*K; addr = addr + 1) begin
        i_q_rd_addr = addr;
        #1;
        $display("Q[%0d] = %04X    (golden %04X)", addr, o_q_rd_data, q_gold[addr]);
        if (o_q_rd_data !== q_gold[addr]) begin
            err_cnt = err_cnt + 1;
            $display("Q MISMATCH at addr=%0d", addr);
        end
    end

    // 比较 R
    $display("\n=== R Matrix (upper triangular, linear index) ===");
    for (addr = 0; addr < K*(K+1)/2; addr = addr + 1) begin
        i_r_rd_idx = addr;
        #1;
        $display("R[%0d] = %04X    (golden %04X)", addr, o_r_rd_data, r_gold[addr]);
        if (o_r_rd_data !== r_gold[addr]) begin
            err_cnt = err_cnt + 1;
            $display("R MISMATCH at idx=%0d", addr);
        end
    end

    if (err_cnt == 0)
        $display("ALL MATCH: Q(%0d entries) R(%0d entries) PASS", M*K, K*(K+1)/2);
    else
        $display("FAIL: %0d mismatches", err_cnt);
    $finish;
end

// 超时保护
initial begin
    #100000;
    $display("TIMEOUT");
    $finish;
end

endmodule
