// ============================================================================
// tb_stap_4ch.v — STAP 空时滤波模块验证（先 tb 后 RTL，2026-08-13）
// 场景：MATLAB stap_ref.m 黄金（1 慢速目标 + 强旁瓣杂波）4 通道多普勒谱 22bit 定点
// 流程：复位 → 权值 RAM 由 .mem 初始化（stap_w_q15.mem）→ 逐拍输入 12288 行谱
//       （bin-major：64 bin × 192 gate，每行 4 通道 I/Q）→ 收集 o_out_valid 输出
// 输出：stap_rtl_out.txt（每行 out_i out_q，22bit 补码 hex，顺序同激励）
// 对比：python tools/stap_rtl_compare.py stap_rtl_out.txt vs matlab/stap_out/stap_gold.txt
// 判据：逐点绝对误差 ≤1 LSB（round vs 截断差异）→ 主峰相对误差 ≤1e-2
// ============================================================================
`timescale 1ns / 1ps
module tb_stap_4ch;

// ===== param =====
parameter P_N       = 64;
parameter P_NLINES  = 12288;           // 64 bin × 192 gate
parameter P_CLK     = 10;

// ===== reg =====
reg              r_clk       ;
reg              r_rst       ;
reg              r_valid     ;
reg  [5:0]       r_bin       ;
reg  [87:0]      r_data_i    ;         // 4×22
reg  [87:0]      r_data_q    ;
reg  [31:0]      r_cnt       ;
reg  [31:0]      r_out_cnt   ;
reg  [21:0]      r_stim [0:P_NLINES*8-1];  // 激励：每行 8 字段（ch0_i ch0_q .. ch3_i ch3_q）
integer          fd_out      ;

// ===== wire =====
wire             w_out_valid ;
wire [21:0]      w_out_i     ;
wire [21:0]      w_out_q     ;
wire [5:0]       w_out_bin   ;

// ===== inst =====
stap_4ch #(
    .P_DATA_W  ( 22      ),
    .P_W_W     ( 16      ),
    .P_CH      ( 4       ),
    .P_N       ( P_N     ),
    .P_BIN_W   ( 6       )
) u_stap (
    .i_clk        ( r_clk        ),
    .i_rst        ( r_rst        ),
    .i_data_valid ( r_valid      ),
    .i_bin        ( r_bin        ),
    .i_data_i     ( r_data_i     ),
    .i_data_q     ( r_data_q     ),
    .o_out_valid  ( w_out_valid  ),
    .o_out_i      ( w_out_i      ),
    .o_out_q      ( w_out_q      ),
    .o_out_bin    ( w_out_bin    ),
    .i_w_wr       ( 1'b0         ),
    .i_w_addr     ( 6'd0         ),
    .i_w_data     ( 128'd0       )
);

// ===== combine_Logic =====

// ===== always =====
always #(P_CLK/2) r_clk = ~r_clk;

initial begin
    $readmemh("../data/stap_in.txt", r_stim);
    r_clk   = 1'b0;
    r_rst   = 1'b1;
    r_valid = 1'b0;
    r_bin   = 6'd0;
    r_data_i= 88'd0;
    r_data_q= 88'd0;
    r_cnt   = 32'd0;
    r_out_cnt = 32'd0;
    fd_out  = $fopen("../data/stap_rtl_out.txt", "w");
    #(P_CLK*5);
    r_rst = 1'b0;
    // 等待权值加载稳定（initial readmemh 已同步完成）
    #(P_CLK*5);
    // 逐行驱动：每行一拍（bin-major）
    for (r_cnt = 0; r_cnt < P_NLINES; r_cnt = r_cnt + 1) begin
        @(posedge r_clk);
        r_valid = 1'b1;
        r_bin   = r_cnt / 192;                       // bin 0..63
        // 打包：ch0=字段0(I)/字段1(Q) ... ch3=字段6(I)/字段7(Q)
        // i_data_i = {ch3_i, ch2_i, ch1_i, ch0_i}（ch0 最低位）
        r_data_i = {r_stim[r_cnt*8+6], r_stim[r_cnt*8+4], r_stim[r_cnt*8+2], r_stim[r_cnt*8+0]};
        r_data_q = {r_stim[r_cnt*8+7], r_stim[r_cnt*8+5], r_stim[r_cnt*8+3], r_stim[r_cnt*8+1]};
    end
    // 循环退出后 r_valid 仍为 1（最后一次迭代设置）；下一沿模块采样最后一行
    @(posedge r_clk);
    r_valid = 1'b0;
    // 流水排空（3 级流水 + 余量）
    repeat(8) @(posedge r_clk);
    $fclose(fd_out);
    $display("[tb] STAP 输入 %0d 行，输出 %0d 行 → fpga/tb/stap_rtl_out.txt", P_NLINES, r_out_cnt);
    $finish;
end

// 输出收集：valid 当拍采样（posedge 触发时 NBA 未更新，w_out_valid/w_out_i 均为
// valid 拉高那拍的值——同沿同拍正确采样；XPM 化后流水 +1 级，
// 原 r_vd1 延迟采样错位 1 行，2026-08-14 改为当拍采样，对任意流水深度鲁棒）
always @(posedge r_clk or posedge r_rst) begin
    if (r_rst) begin
        r_out_cnt <= 32'd0;
    end
    else if (w_out_valid) begin
        $fwrite(fd_out, "%06X %06X\n", w_out_i, w_out_q);
        r_out_cnt <= r_out_cnt + 1'b1;
    end
    else r_out_cnt <= r_out_cnt;
end

endmodule
