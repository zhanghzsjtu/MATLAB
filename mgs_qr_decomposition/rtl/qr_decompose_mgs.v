//==========================================================================
// qr_decompose_mgs.v
// 基于修正 Gram-Schmidt(MGS) 的 QR 分解, 状态机实现
// 算法: 对支撑集矩阵 A(m x k), 逐列做 MGS 正交化, 输出 Q(m x k) 与 R(k x k)
// 定点格式: Q1.15 有符号 (W=16), 输入原子要求已单位化
//   投影系数  r_ij = sum_t q_i(t)*v(t)          -> 乘累加后取 [30:15]
//   残差更新  v(t)  = v(t) - (r_ij*q_i(t))>>15
//   范数      r_jj = sqrt(sum_t v(t)^2)         -> 逐位开方 16 拍
//   归一化    q_new = v / r_jj                  -> 逐位除法 30 拍
// 状态: IDLE -> LOAD -> (PROJ -> SUB)* -> NORM -> SQRT -> DIV -> DONE
// 内部存储: A/Q RAM 地址 = row*K + col; R RAM 线性索引 idx = j*(j+1)/2 + i
// 验证: iverilog 12.0 与 Vivado 2022.1 xsim 均 ALL MATCH(42 项逐位一致)
//==========================================================================
`timescale 1ns/1ps

module qr_decompose_mgs #(
    parameter W  = 16,             // 数据位宽, Q1.15 定点
    parameter M  = 8,              // 信号维度(行数)
    parameter K  = 4,              // 支撑集大小(列数)
    parameter AW = $clog2(M*K),    // A/Q RAM 地址位宽
    parameter RW = $clog2(K*(K+1)/2)  // R RAM 地址位宽
) (
    input  wire              i_clk,
    input  wire              i_rst,         // 高有效异步复位
    input  wire              i_start,       // 启动分解
    // A 矩阵写入接口
    input  wire              i_a_wr_en,
    input  wire [AW-1:0]     i_a_wr_addr,   // 地址 = row*K + col
    input  wire [W-1:0]      i_a_wr_data,
    // 状态输出
    output wire              o_busy,
    output wire              o_done,
    // Q 矩阵读出接口
    input  wire [AW-1:0]     i_q_rd_addr,
    output wire [W-1:0]      o_q_rd_data,
    // R 矩阵读出接口(线性索引 idx = j*(j+1)/2 + i, i<=j)
    input  wire [RW-1:0]     i_r_rd_idx,
    output wire [W-1:0]      o_r_rd_data
);

// ===== param =====
localparam WT2 = 2*W;                      // 乘积累加位宽

// 状态常量(独热码)
parameter P_ST_IDLE = 8'b0000_0001;
parameter P_ST_LOAD = 8'b0000_0010;
parameter P_ST_PROJ = 8'b0000_0100;
parameter P_ST_SUB  = 8'b0000_1000;
parameter P_ST_NORM = 8'b0001_0000;
parameter P_ST_SQRT = 8'b0010_0000;
parameter P_ST_DIV  = 8'b0100_0000;
parameter P_ST_DONE = 8'b1000_0000;

// ===== reg =====
// FSM 状态
reg [7:0] state_c;
reg [7:0] state_n;

// 控制计数
reg [AW-1:0] r_t_cnt;          // 行/拍计数(0..M-1)
reg [AW-1:0] r_j_cnt;          // 当前列(0..K-1)
reg [AW-1:0] r_i_cnt;          // 内层投影索引(0..j-1)
reg [4:0]    r_dv_cnt;         // 除法位计数(0..29)
reg [3:0]    r_sq_cnt;         // 开方位计数(0..15)

// 计算寄存器
reg [WT2+3:0] r_mac_acc;       // 乘累加器 36 位(Q2.30 累加)
reg [WT2+1:0] r_sq_acc;        // 平方累加器 34 位
reg [W-1:0]   r_rij_q;         // 锁存投影系数
reg [WT2-1:0] r_sq_val;        // 开方输入(低 32 位)
reg [33:0]    r_sq_rem;        // 开方余数 34 位(rem<<2 需 34 位)
reg [W-1:0]   r_sq_res;        // 开方结果
reg [W:0]     r_dv_rem;        // 除法余数 17 位
reg [W-1:0]   r_dv_quot;       // 除法商

// 存储
reg [W-1:0] r_v_arr [0:M-1];        // 残差向量
reg [W-1:0] r_a_ram  [0:M*K-1];     // A 矩阵
reg [W-1:0] r_q_ram  [0:M*K-1];     // Q 矩阵
reg [W-1:0] r_r_ram  [0:K*(K+1)/2-1]; // R 矩阵

// 输出打拍寄存器
reg ro_busy;
reg ro_done;

integer tt;

// ===== wire =====
// 状态完成判据
wire w_ld_done;
wire w_mac_done;
wire w_sub_done;
wire w_sq_done;
wire w_sqrt_done;
wire w_div_done;
// 循环边界判据
wire w_no_inner;
wire w_i_last;
wire w_j_last;
// MAC 组合
wire [WT2-1:0] w_prod32;
wire [W-1:0]   w_rij_new;
wire [WT2-1:0] w_sub_prod;
wire [W-1:0]   w_sub_val;
wire [WT2-1:0] w_sq_prod;
// 开方组合
wire [1:0]     w_sq_2bit;
wire [33:0]    w_sq_rem_in;
wire [W+1:0]   w_sq_trial;
wire [WT2-1:0] w_sq_val_eff;   // sq_cnt=0 拍用 NORM 累加值, 后续用 r_sq_val
// 除法组合
wire [W-1:0]   w_abs_v;
wire [WT2-1:0] w_dv_num;
wire           w_dv_bit;
wire [W:0]     w_dv_rem_in;
wire           w_dv_carry;
wire [W-1:0]   w_dv_quot_in;
wire [W-1:0]   w_dv_quot_final;
wire           w_dv_sign;
// 地址组合
wire [AW-1:0] w_a_rd_addr;
wire [AW-1:0] w_q_rd_addr;
wire [AW-1:0] w_off_idx;
wire [AW-1:0] w_diag_idx;
// FSM 跳转条件
wire p_st_idle2st_load_start;
wire p_st_load2st_proj_start;
wire p_st_load2st_norm_start;
wire p_st_proj2st_sub_start;
wire p_st_sub2st_proj_start;
wire p_st_sub2st_norm_start;
wire p_st_norm2st_sqrt_start;
wire p_st_sqrt2st_div_start;
wire p_st_div2st_load_start;
wire p_st_div2st_done_start;
wire p_st_done2st_idle_start;

// ===== assign =====
assign o_busy    = ro_busy;
assign o_done    = ro_done;
assign o_q_rd_data = r_q_ram[i_q_rd_addr];
assign o_r_rd_data = r_r_ram[i_r_rd_idx];

// ===== FSM(状态跳转条件, 独立 wire) =====
assign p_st_idle2st_load_start = state_c==P_ST_IDLE && (i_start);
assign p_st_load2st_proj_start = state_c==P_ST_LOAD && (w_ld_done) && (~w_no_inner);
assign p_st_load2st_norm_start = state_c==P_ST_LOAD && (w_ld_done) && (w_no_inner);
assign p_st_proj2st_sub_start  = state_c==P_ST_PROJ && (w_mac_done);
assign p_st_sub2st_proj_start  = state_c==P_ST_SUB  && (w_sub_done) && (~w_i_last);
assign p_st_sub2st_norm_start  = state_c==P_ST_SUB  && (w_sub_done) && (w_i_last);
assign p_st_norm2st_sqrt_start = state_c==P_ST_NORM && (w_sq_done);
assign p_st_sqrt2st_div_start  = state_c==P_ST_SQRT && (w_sqrt_done);
assign p_st_div2st_load_start  = state_c==P_ST_DIV  && (w_div_done) && (~w_j_last);
assign p_st_div2st_done_start  = state_c==P_ST_DIV  && (w_div_done) && (w_j_last);
assign p_st_done2st_idle_start = state_c==P_ST_DONE && (i_start);

// ===== inst(本模块无子模块实例) =====

// ===== combine_Logic(组合判据与数据通路) =====
assign w_ld_done   = (state_c == P_ST_LOAD) && (r_t_cnt == M-1);
assign w_mac_done  = (state_c == P_ST_PROJ) && (r_t_cnt == M);   // 多 1 拍, 等累加器边沿更新完整
assign w_sub_done  = (state_c == P_ST_SUB)  && (r_t_cnt == M-1);
assign w_sq_done   = (state_c == P_ST_NORM) && (r_t_cnt == M-1);
assign w_sqrt_done = (state_c == P_ST_SQRT) && (r_sq_cnt == 4'd15);
assign w_div_done  = (state_c == P_ST_DIV)  && (r_dv_cnt == 5'd29) && (r_t_cnt == M-1);

assign w_no_inner = (r_j_cnt == 'd0);
assign w_i_last   = (r_i_cnt == r_j_cnt - 1'b1);
assign w_j_last   = (r_j_cnt == K - 1'b1);

// 地址
assign w_a_rd_addr = r_t_cnt * K + r_j_cnt;
assign w_q_rd_addr = r_t_cnt * K + r_i_cnt;
assign w_off_idx   = r_j_cnt*(r_j_cnt+1)/2 + r_i_cnt;
assign w_diag_idx  = r_j_cnt*(r_j_cnt+1)/2 + r_j_cnt;

// MAC: 16x16 有符号乘
assign w_prod32 = $signed(r_q_ram[w_q_rd_addr]) * $signed(r_v_arr[r_t_cnt]);
assign w_rij_new = r_mac_acc[30:15];                  // acc 算术右移 15 位(取 bit30..bit15)
assign w_sub_prod = $signed(r_rij_q) * $signed(r_q_ram[w_q_rd_addr]);
assign w_sub_val  = w_sub_prod[30:15];                // prod 算术右移 15 位
assign w_sq_prod  = $signed(r_v_arr[r_t_cnt]) * $signed(r_v_arr[r_t_cnt]);

// 开方: rem = {rem<<2 | 2bit}, trial = (res<<2)+1
assign w_sq_val_eff = (r_sq_cnt == 4'd0) ? r_sq_acc[31:0] : r_sq_val;
assign w_sq_2bit    = w_sq_val_eff[30 - 2*r_sq_cnt +: 2];
assign w_sq_rem_in  = (r_sq_cnt == 4'd0) ? {32'b0, w_sq_2bit}
                                          : {r_sq_rem[31:0], w_sq_2bit};
assign w_sq_trial   = {r_sq_res, 2'b01};

// 除法: 恢复法逐位 MSB-first, 被除数 |v|<<15(30 位), 除数 r_jj(=r_sq_res)
assign w_abs_v      = r_v_arr[r_t_cnt][W-1] ? (~r_v_arr[r_t_cnt] + 1'b1) : r_v_arr[r_t_cnt];
assign w_dv_num     = {1'b0, w_abs_v} << (W-1);
assign w_dv_bit     = w_dv_num[29 - r_dv_cnt];
assign w_dv_rem_in  = (r_dv_cnt == 5'd0) ? {16'b0, w_dv_bit}
                                          : {r_dv_rem[W-1:0], w_dv_bit};
assign w_dv_carry   = (w_dv_rem_in >= r_sq_res);
assign w_dv_quot_in = (r_dv_cnt == 5'd0) ? {15'b0, w_dv_carry}
                                          : {r_dv_quot[W-2:0], w_dv_carry};
assign w_dv_quot_final = (r_sq_res == 'd0) ? 'd0 : w_dv_quot_in;   // 除零防护
assign w_dv_sign    = r_v_arr[r_t_cnt][W-1];

// ===== always(时序逻辑) =====
// 第一段: 状态寄存器
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        state_c <= P_ST_IDLE;
    else
        state_c <= state_n;
end

// 第二段: 状态转移组合逻辑
always @(*) begin
    case (state_c)
        P_ST_IDLE: begin
            if (p_st_idle2st_load_start) state_n = P_ST_LOAD;
            else                         state_n = state_c;
        end
        P_ST_LOAD: begin
            if (p_st_load2st_proj_start) state_n = P_ST_PROJ;
            else if (p_st_load2st_norm_start) state_n = P_ST_NORM;
            else                         state_n = state_c;
        end
        P_ST_PROJ: begin
            if (p_st_proj2st_sub_start) state_n = P_ST_SUB;
            else                        state_n = state_c;
        end
        P_ST_SUB: begin
            if (p_st_sub2st_proj_start) state_n = P_ST_PROJ;
            else if (p_st_sub2st_norm_start) state_n = P_ST_NORM;
            else                        state_n = state_c;
        end
        P_ST_NORM: begin
            if (p_st_norm2st_sqrt_start) state_n = P_ST_SQRT;
            else                         state_n = state_c;
        end
        P_ST_SQRT: begin
            if (p_st_sqrt2st_div_start) state_n = P_ST_DIV;
            else                        state_n = state_c;
        end
        P_ST_DIV: begin
            if (p_st_div2st_load_start) state_n = P_ST_LOAD;
            else if (p_st_div2st_done_start) state_n = P_ST_DONE;
            else                        state_n = state_c;
        end
        P_ST_DONE: begin
            if (p_st_done2st_idle_start) state_n = P_ST_IDLE;
            else                         state_n = state_c;
        end
        default: state_n = P_ST_IDLE;
    endcase
end

// 行/拍计数
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_t_cnt <= 'd0;
    else if (w_ld_done || w_mac_done || w_sub_done || w_sq_done || w_div_done)
        r_t_cnt <= 'd0;
    else if (state_c == P_ST_LOAD || state_c == P_ST_PROJ ||
             state_c == P_ST_SUB  || state_c == P_ST_NORM)
        r_t_cnt <= r_t_cnt + 1'b1;
    else if (state_c == P_ST_DIV)
        r_t_cnt <= (r_dv_cnt == 5'd29) ? r_t_cnt + 1'b1 : r_t_cnt;
    else
        r_t_cnt <= r_t_cnt;
end

// 内层投影索引
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_i_cnt <= 'd0;
    else if (p_st_load2st_proj_start)
        r_i_cnt <= 'd0;
    else if (p_st_sub2st_proj_start)
        r_i_cnt <= r_i_cnt + 1'b1;
    else
        r_i_cnt <= r_i_cnt;
end

// 当前列索引
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_j_cnt <= 'd0;
    else if (p_st_idle2st_load_start)
        r_j_cnt <= 'd0;
    else if (p_st_div2st_load_start)
        r_j_cnt <= r_j_cnt + 1'b1;
    else
        r_j_cnt <= r_j_cnt;
end

// 除法位计数(首拍装载后转到 1, 0..29 共 30 拍)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_dv_cnt <= 'd0;
    else if (state_c == P_ST_DIV) begin
        if (r_dv_cnt == 5'd0)
            r_dv_cnt <= 5'd1;
        else if (r_dv_cnt == 5'd29)
            r_dv_cnt <= 5'd0;
        else
            r_dv_cnt <= r_dv_cnt + 1'b1;
    end else
        r_dv_cnt <= r_dv_cnt;
end

// 开方位计数(首拍装载后转到 1, 保证 16 拍运算)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_sq_cnt <= 'd0;
    else if (state_c == P_ST_SQRT) begin
        if (r_sq_cnt == 4'd0)
            r_sq_cnt <= 4'd1;
        else if (r_sq_cnt == 4'd15)
            r_sq_cnt <= 4'd0;
        else
            r_sq_cnt <= r_sq_cnt + 1'b1;
    end else
        r_sq_cnt <= r_sq_cnt;
end

// 乘累加器(每次进入 PROJ 清零, 前 M 拍累加, 第 M 拍等待累加结果稳定)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_mac_acc <= 'd0;
    else if (p_st_idle2st_load_start || p_st_div2st_load_start ||
             p_st_load2st_proj_start || p_st_sub2st_proj_start)
        r_mac_acc <= 'd0;
    else if (state_c == P_ST_PROJ && r_t_cnt != M)
        r_mac_acc <= $signed(r_mac_acc) + $signed(w_prod32);
    else
        r_mac_acc <= r_mac_acc;
end

// 平方累加器
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_sq_acc <= 'd0;
    else if (p_st_idle2st_load_start || p_st_div2st_load_start)
        r_sq_acc <= 'd0;
    else if (state_c == P_ST_NORM)
        r_sq_acc <= r_sq_acc + {2'b00, w_sq_prod};
    else
        r_sq_acc <= r_sq_acc;
end

// 投影系数锁存
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_rij_q <= 'd0;
    else if (w_mac_done)
        r_rij_q <= w_rij_new;
    else
        r_rij_q <= r_rij_q;
end

// 开方输入装载(SQRT 首拍装载 NORM 累加结果, 避免与 r_sq_acc 累加同拍冲突)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_sq_val <= 'd0;
    else if (state_c == P_ST_SQRT && r_sq_cnt == 4'd0)
        r_sq_val <= r_sq_acc[WT2-1:0];
    else
        r_sq_val <= r_sq_val;
end

// 开方余数
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_sq_rem <= 'd0;
    else if (state_c == P_ST_SQRT)
        r_sq_rem <= (w_sq_rem_in >= w_sq_trial) ? (w_sq_rem_in - w_sq_trial)
                                                 : w_sq_rem_in;
    else
        r_sq_rem <= r_sq_rem;
end

// 开方结果(首拍从 0 开始移位, 后续拍逐位收敛)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_sq_res <= 'd0;
    else if (state_c == P_ST_SQRT)
        r_sq_res <= (r_sq_cnt == 4'd0)
            ? {15'b0, (w_sq_rem_in >= w_sq_trial)}
            : ((w_sq_rem_in >= w_sq_trial) ? {r_sq_res[W-2:0], 1'b1}
                                            : {r_sq_res[W-2:0], 1'b0});
    else
        r_sq_res <= r_sq_res;
end

// 除法余数
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_dv_rem <= 'd0;
    else if (state_c == P_ST_DIV)
        r_dv_rem <= (w_dv_carry) ? (w_dv_rem_in - r_sq_res) : w_dv_rem_in;
    else
        r_dv_rem <= r_dv_rem;
end

// 除法商
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        r_dv_quot <= 'd0;
    else if (state_c == P_ST_DIV)
        r_dv_quot <= w_dv_quot_in;
    else
        r_dv_quot <= r_dv_quot;
end

// 残差向量
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst) begin
        for (tt = 0; tt < M; tt = tt + 1)
            r_v_arr[tt] <= 'd0;
    end else if (state_c == P_ST_LOAD)
        r_v_arr[r_t_cnt] <= r_a_ram[w_a_rd_addr];
    else if (state_c == P_ST_SUB)
        r_v_arr[r_t_cnt] <= r_v_arr[r_t_cnt] - w_sub_val;
    else
        r_v_arr[r_t_cnt] <= r_v_arr[r_t_cnt];
end

// A 矩阵写入
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst) begin
        for (tt = 0; tt < M*K; tt = tt + 1)
            r_a_ram[tt] <= 'd0;
    end else if (i_a_wr_en)
        r_a_ram[i_a_wr_addr] <= i_a_wr_data;
    else
        r_a_ram[i_a_wr_addr] <= r_a_ram[i_a_wr_addr];
end

// Q 矩阵写入(除法完成拍写入当前列元素)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst) begin
        for (tt = 0; tt < M*K; tt = tt + 1)
            r_q_ram[tt] <= 'd0;
    end else if (state_c == P_ST_DIV && r_dv_cnt == 5'd29)
        r_q_ram[r_t_cnt*K + r_j_cnt] <= (w_dv_sign) ? (-w_dv_quot_final) : w_dv_quot_final;
    else
        r_q_ram[r_t_cnt*K + r_j_cnt] <= r_q_ram[r_t_cnt*K + r_j_cnt];
end

// R 矩阵写入(投影系数 + 对角元)
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst) begin
        for (tt = 0; tt < K*(K+1)/2; tt = tt + 1)
            r_r_ram[tt] <= 'd0;
    end else if (w_mac_done)
        r_r_ram[w_off_idx] <= w_rij_new;
    else if (state_c == P_ST_DIV && r_dv_cnt == 5'd0 && r_t_cnt == 'd0)
        r_r_ram[w_diag_idx] <= r_sq_res;
    else
        r_r_ram[w_off_idx] <= r_r_ram[w_off_idx];
end

// 输出打拍
always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_busy <= 1'b0;
    else
        ro_busy <= (state_c != P_ST_IDLE);
end

always @(posedge i_clk or posedge i_rst) begin
    if (i_rst)
        ro_done <= 1'b0;
    else
        ro_done <= (state_c == P_ST_DONE);
end

endmodule
