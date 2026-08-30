// ============================================================================
// 模块名：stap_4ch
// 功能：STAP 空时滤波——4 子阵通道多普勒谱 × 每 bin 复数权（Q15）→ 复加权求和
//       输出杂波抑制后的单通道谱（后多普勒 STAP，权值离线 SMI 计算由寄存器下发）
// 算法：y(d,r) = Σ_m w_m(d)·X_m(d,r)，w 随多普勒 bin 变化（杂波空间谱抑制）
// 定点：输入谱 22bit 定点（对齐 doppler_fft 输出）× 权值 16bit Q15（32768=1.0）
//       乘积 38bit → 4 项累加 40bit → 算术右移 15 → 饱和 22bit 输出
// 流水：3 级（乘 → 累加 → 截位饱和），无状态机，吞吐 = 输入速率
// 权值：matlab/stap_w_q15.mem（$readmemh 绝对路径；每行 8 字段：
//       ch0_i ch0_q ch1_i ch1_q ch2_i ch2_q ch3_i ch3_q，16bit 补码 hex）
// 参数：P_DATA_W=22 P_W_W=16 P_CH=4 P_N=64 P_BIN_W=6
// 时钟：i_clk；复位：i_rst 高有效异步复位
// 规范：端口对齐 + 分组注释 + r_/w_/ro_ 前缀 + 保持型 else + 32'dN
// 黄金：matlab/stap_ref.m（SMI 权 + 定点模拟）；tb：fpga/tb/tb_stap_4ch.v
// ============================================================================
`timescale 1ns / 1ps
module stap_4ch #(
    parameter P_DATA_W  = 22   , // 谱数据位宽（对齐 doppler_fft 输出）
    parameter P_W_W     = 16   , // 权值位宽（Q15）
    parameter P_CH      = 4    , // 子阵通道数
    parameter P_N       = 64   , // 多普勒 bin 数
    parameter P_BIN_W   = 6      // log2(P_N)
)(
    input  wire                         i_clk          ,
    input  wire                         i_rst          ,
    // ===== 输入：4 通道同 bin 谱（ch0 在最低位）=====
    input  wire                         i_data_valid   ,
    input  wire [P_BIN_W-1:0]           i_bin          ,
    input  wire [P_CH*P_DATA_W-1:0]     i_data_i       ,
    input  wire [P_CH*P_DATA_W-1:0]     i_data_q       ,
    // ===== 输出：STAP 谱（流水 3 拍后，同拍序）=====
    output wire                         o_out_valid    ,
    output wire [P_DATA_W-1:0]          o_out_i        ,
    output wire [P_DATA_W-1:0]          o_out_q        ,
    output wire [P_BIN_W-1:0]           o_out_bin      ,
    // ===== 权值在线刷新（预留；默认由 .mem 初始化，不使用）=====
    input  wire                         i_w_wr         ,
    input  wire [P_BIN_W-1:0]           i_w_addr       ,
    input  wire [2*P_CH*P_W_W-1:0]      i_w_data
);

// ===== param =====
localparam P_PROD_W = P_DATA_W + P_W_W;        // 38：22×16 乘积
localparam P_ACC_W  = P_PROD_W + 2;            // 40：4 项累加
localparam P_WIN_SHIFT = 15;                   // Q15 归一化右移
// 饱和常量：与 w_sh_i 同宽有符号（避免 signed/unsigned 混比较误判）
localparam signed [P_ACC_W-1:0] P_SAT_POS = {{(P_ACC_W-22){1'b0}}, 22'h1FFFFF}; // +2097151
localparam signed [P_ACC_W-1:0] P_SAT_NEG = {{(P_ACC_W-22){1'b1}}, 22'h200000}; // -2097152

// ===== reg =====
reg [P_PROD_W-1:0]  r_prod_i [0:P_CH-1];        // 级1：乘积 I（每通道）
reg [P_PROD_W-1:0]  r_prod_q [0:P_CH-1];        // 级1：乘积 Q
reg [P_ACC_W-1:0]   r_acc_i        ;            // 级2：累加和 I
reg [P_ACC_W-1:0]   r_acc_q        ;            // 级2：累加和 Q
reg                 r_valid_0      ;            // 级0 有效（XPM 同步读对齐，i_data_valid 打拍）
reg                 r_valid_1      ;            // 级1 有效
reg                 r_valid_2      ;            // 级2 有效
reg [P_BIN_W-1:0]   r_bin_0        ;            // 级0 bin 打拍
reg [P_BIN_W-1:0]   r_bin_1        ;            // 级1 bin 打拍
reg [P_BIN_W-1:0]   r_bin_2        ;            // 级2 bin 打拍
reg [P_CH*P_DATA_W-1:0] r_data_i_0 ;            // 级0 输入 I 打拍（与 XPM 权值输出对齐）
reg [P_CH*P_DATA_W-1:0] r_data_q_0 ;            // 级0 输入 Q 打拍
reg [P_DATA_W-1:0]  ro_out_i       ;            // 输出 I 打拍
reg [P_DATA_W-1:0]  ro_out_q       ;            // 输出 Q 打拍
reg                 ro_out_valid   ;            // 输出有效打拍
reg [P_BIN_W-1:0]   ro_out_bin     ;            // 输出 bin 打拍
integer             i              ;            // 复位循环索引

// ===== wire =====
wire signed [P_PROD_W-1:0] w_prod_i [0:P_CH-1]; // 乘法器输出 I（组合）
wire signed [P_PROD_W-1:0] w_prod_q [0:P_CH-1]; // 乘法器输出 Q
wire signed [P_ACC_W-1:0]  w_acc_i   ;          // 累加和 I（组合，树形）
wire signed [P_ACC_W-1:0]  w_acc_q   ;          // 累加和 Q
wire signed [P_ACC_W-1:0]  w_sh_i    ;          // 右移 15 中间（25bit 有效）
wire signed [P_ACC_W-1:0]  w_sh_q    ;
wire                        w_ovr_i   ;          // I 饱和标志
wire                        w_ovr_q   ;          // Q 饱和标志
wire [2*P_CH*P_W_W-1:0]    w_w_pack  ;          // 权值 SDPRAM 读口输出（128bit，1 拍延迟）

// ===== assign =====
assign o_out_valid = ro_out_valid;
assign o_out_i     = ro_out_i;
assign o_out_q     = ro_out_q;
assign o_out_bin   = ro_out_bin;

// 复乘：y = w^H·x = Σ conj(w_m)·x_m（共轭转置；与 MATLAB Y_float/Yq 同口径）
// conj(w)·x = (wi - j·wq)(xi + j·xq) → i: wi·xi + wq·xq，q: wi·xq - wq·xi
// XPM 化 2026-08-14：权值 SDPRAM 同步读 1 拍 → 输入数据打拍 1 拍（r_data_i_0）对齐
genvar gm;
generate
    for (gm = 0; gm < P_CH; gm = gm + 1) begin : g_mul
        wire signed [P_DATA_W-1:0] w_xi = $signed(r_data_i_0[gm*P_DATA_W +: P_DATA_W]);
        wire signed [P_DATA_W-1:0] w_xq = $signed(r_data_q_0[gm*P_DATA_W +: P_DATA_W]);
        wire signed [P_W_W-1:0]    w_wi = $signed(w_w_pack[gm*2*P_W_W +: P_W_W]);
        wire signed [P_W_W-1:0]    w_wq = $signed(w_w_pack[gm*2*P_W_W + P_W_W +: P_W_W]);
        assign w_prod_i[gm] = w_xi * w_wi + w_xq * w_wq;   // conj(w)·x 实部 = wi·xi + wq·xq
        assign w_prod_q[gm] = w_wi * w_xq - w_wq * w_xi;   // conj(w)·x 虚部 = wi·xq − wq·xi
    end
endgenerate

// 累加：Σ 4 通道（组合树，级 2 寄存）
assign w_acc_i = $signed(r_prod_i[0]) + $signed(r_prod_i[1]) +
                 $signed(r_prod_i[2]) + $signed(r_prod_i[3]);
assign w_acc_q = $signed(r_prod_q[0]) + $signed(r_prod_q[1]) +
                 $signed(r_prod_q[2]) + $signed(r_prod_q[3]);

// 截位饱和（级 3 组合 → ro_ 打拍）：acc >> 15（算术）→ 25bit 有效 → 饱和 22bit
assign w_sh_i = $signed(r_acc_i) >>> P_WIN_SHIFT;
assign w_sh_q = $signed(r_acc_q) >>> P_WIN_SHIFT;
assign w_ovr_i = ($signed(w_sh_i) > P_SAT_POS) || ($signed(w_sh_i) < P_SAT_NEG);
assign w_ovr_q = ($signed(w_sh_q) > P_SAT_POS) || ($signed(w_sh_q) < P_SAT_NEG);

// ===== FSM =====
// 无状态机：纯数据流流水（3 级）

// ===== inst =====
// 权值 SDPRAM：xpm_memory_sdpram（P0 规范改造 2026-08-14，替代 $readmemh + reg 数组；
//       128bit 宽 × P_N 深（每 bin 一行 8 字段），SMI 离线权初始化，
//       写口接在线刷新（i_w_wr/i_w_addr/i_w_data），读口同步 1 拍延迟）
xpm_memory_sdpram #(
    .MEMORY_SIZE        ( P_N * 2*P_CH*P_W_W ),
    .WRITE_DATA_WIDTH_A ( 2*P_CH*P_W_W       ),
    .READ_DATA_WIDTH_B  ( 2*P_CH*P_W_W       ),
    .ADDR_WIDTH_A       ( P_BIN_W            ),
    .ADDR_WIDTH_B       ( P_BIN_W            ),
    .READ_LATENCY_B     ( 1                  ),
    .WRITE_MODE_B       ( "no_change"        ),
    .MEMORY_PRIMITIVE   ( "auto"             ),
    .USE_MEM_INIT       ( 1                  ),
    .MEMORY_INIT_FILE   ( "../data/stap_w_rom.mem" ),
    .MEMORY_INIT_PARAM  ( "0"                )
) u_w (
    .sleep          ( 1'b0   ),
    .clka           ( i_clk  ),
    .ena            ( 1'b1   ),
    .wea            ( i_w_wr ),
    .addra          ( i_w_addr ),
    .dina           ( i_w_data ),
    .injectsbiterra ( 1'b0   ),
    .injectdbiterra ( 1'b0   ),
    .clkb           ( i_clk  ),
    .rstb           ( 1'b0   ),
    .enb            ( 1'b1   ),
    .regceb         ( 1'b1   ),
    .addrb          ( i_bin  ),
    .doutb          ( w_w_pack ),
    .sbiterrb       (        ),
    .dbiterrb       (        )
);

// ===== combine_Logic =====
// 无（组合逻辑已由 assign 覆盖）

// ===== always =====
// 权值由 SDPRAM MEMORY_INIT_FILE 初始化（XPM 化 2026-08-14，
// 替代 initial $readmemh + reg 数组组合读；SMI 离线权见 u_w 例化）
// 权值在线刷新（预留接口：i_w_wr 置位时写入 SDPRAM 写口，见 u_w 例化）

// 级 0：输入打拍（与 XPM 权值同步读 1 拍延迟对齐——乘法取 r_data_0 × w_w_pack）
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst) begin
        r_valid_0   <= 'd0;
        r_bin_0     <= 'd0;
        r_data_i_0  <= 'd0;
        r_data_q_0  <= 'd0;
    end
    else begin
        r_valid_0   <= i_data_valid;
        r_bin_0     <= i_bin;
        r_data_i_0  <= i_data_i;
        r_data_q_0  <= i_data_q;
    end
end

// 级 1：乘积寄存（每通道独立 always，保持型 else）
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst) begin
        for (i = 0; i < P_CH; i = i + 1) begin
            r_prod_i[i] <= 'd0;
            r_prod_q[i] <= 'd0;
        end
    end
    else if (r_valid_0) begin
        for (i = 0; i < P_CH; i = i + 1) begin
            r_prod_i[i] <= w_prod_i[i];
            r_prod_q[i] <= w_prod_q[i];
        end
    end
    else begin
        for (i = 0; i < P_CH; i = i + 1) begin
            r_prod_i[i] <= r_prod_i[i];
            r_prod_q[i] <= r_prod_q[i];
        end
    end
end

// 级 1 有效打拍
always @(posedge i_clk or posedge i_rst)
    if (i_rst)      r_valid_1 <= 'd0;
    else            r_valid_1 <= r_valid_0;

// 级 1 bin 打拍
always @(posedge i_clk or posedge i_rst)
    if (i_rst)      r_bin_1 <= 'd0;
    else            r_bin_1 <= r_bin_0;

// 级 2：累加寄存
always @(posedge i_clk or posedge i_rst)
    if (i_rst)      r_acc_i <= 'd0;
    else if (r_valid_1) r_acc_i <= w_acc_i;
    else            r_acc_i <= r_acc_i;

always @(posedge i_clk or posedge i_rst)
    if (i_rst)      r_acc_q <= 'd0;
    else if (r_valid_1) r_acc_q <= w_acc_q;
    else            r_acc_q <= r_acc_q;

// 级 2 有效打拍
always @(posedge i_clk or posedge i_rst)
    if (i_rst)      r_valid_2 <= 'd0;
    else            r_valid_2 <= r_valid_1;

// 级 2 bin 打拍
always @(posedge i_clk or posedge i_rst)
    if (i_rst)      r_bin_2 <= 'd0;
    else            r_bin_2 <= r_bin_1;

// 级 3：输出 I（饱和 + 打拍）
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst) begin
        ro_out_i <= 'd0;
    end
    else if (r_valid_2) begin
        if (w_ovr_i) begin
            ro_out_i <= (w_sh_i[P_ACC_W-1]) ? P_SAT_NEG : P_SAT_POS;
        end
        else begin
            ro_out_i <= w_sh_i[P_DATA_W-1:0];
        end
    end
    else ro_out_i <= ro_out_i;
end

// 级 3：输出 Q（饱和 + 打拍）
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst) begin
        ro_out_q <= 'd0;
    end
    else if (r_valid_2) begin
        if (w_ovr_q) begin
            ro_out_q <= (w_sh_q[P_ACC_W-1]) ? P_SAT_NEG : P_SAT_POS;
        end
        else begin
            ro_out_q <= w_sh_q[P_DATA_W-1:0];
        end
    end
    else ro_out_q <= ro_out_q;
end

// 级 3：输出有效打拍
always @(posedge i_clk or posedge i_rst)
    if (i_rst)      ro_out_valid <= 'd0;
    else            ro_out_valid <= r_valid_2;

// 级 3：输出 bin 打拍
always @(posedge i_clk or posedge i_rst)
    if (i_rst)      ro_out_bin <= 'd0;
    else            ro_out_bin <= r_bin_2;

endmodule
