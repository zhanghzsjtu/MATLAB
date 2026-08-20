#!/bin/bash
# ============================================================================
# STAP RTL 仿真脚本（Vivado xsim）
# ----------------------------------------------------------------------------
# 功能：编译并运行 stap_4ch 的 testbench（tb_stap_4ch），生成 data/stap_rtl_out.txt，
#       再用 tools/stap_rtl_compare.py 与 MATLAB 黄金（data/stap_gold.txt）逐级对比。
#
# 前置条件：
#   1. Vivado 已安装（2022.1 或兼容版本）。脚本通过环境变量 VIVADO 定位，
#      不设则用默认 /d/Xilinx/Vivado/2022.1。
#   2. glbl.v：Xilinx 仿真全局原语，从 Vivado 安装目录取：
#      ${VIVADO}/data/verilog/src/glbl.v
#      放到本目录（rtl/glbl.v）即可，或改下方 GLBL 变量。
#   3. xpm_memory：Xilinx 参数化存储原语，从 Vivado 安装目录取：
#      ${VIVADO}/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv
#
# 用法：bash run_sim.sh
# 产物：data/stap_rtl_out.txt → 自动调用 python 对比
# ============================================================================
set -e

# ---- 路径配置（按需修改，勿硬编码他人机器路径）----
VIVADO="${VIVADO:-/d/Xilinx/Vivado/2022.1}"
XVLOG="$VIVADO/bin/xvlog.bat"
XELAB="$VIVADO/bin/xelab.bat"
XSIM="$VIVADO/bin/xsim.bat"
XPM_MEM="$VIVADO/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv"
GLBL="${GLBL:-$(cd "$(dirname "$0")" && pwd)/glbl.v}"

RTL_DIR="$(cd "$(dirname "$0")" && pwd)"
SIM_WORK="$RTL_DIR/sim_work"
TB_TOP="tb_stap_4ch"

mkdir -p "$SIM_WORK"
cd "$SIM_WORK"

# ---- 编译 xpm_memory（权值 SDPRAM 依赖）----
echo "=== [1/3] xvlog 编译 ==="
"$XVLOG" --work work -sv "$XPM_MEM"
"$XVLOG" --work work "$RTL_DIR/stap_4ch.v"
"$XVLOG" --work work "$RTL_DIR/tb_stap_4ch.v"
"$XVLOG" --work work "$GLBL"

# ---- 链接 ----
echo "=== [2/3] xelab 链接 ==="
"$XELAB" "work.$TB_TOP" work.glbl -s "${TB_TOP}_sim" -debug typical -L work -L unisims_ver -L secureip

# ---- 运行（仿真工作目录 = sim_work，相对路径 ../data/ 指向仓库 data/）----
echo "=== [3/3] xsim 运行 ==="
"$XSIM" "${TB_TOP}_sim" -runall 2>&1 | grep -E "PASS|FAIL|OK|ERROR|tb" || true

# ---- 逐级对比 ----
echo "=== [4/4] RTL vs 黄金对比 ==="
python "$RTL_DIR/../tools/stap_rtl_compare.py"

echo "=== 完成: $TB_TOP ==="
