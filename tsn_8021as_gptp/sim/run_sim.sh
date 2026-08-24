#!/bin/bash
# ============================================================
# TSN 802.1AS gPTP 仿真脚本 (iverilog + vvp)
# 一次跑齐 9 个分层 testbench, 每个输出独立 [PASS]/[FAIL]
# 分层验证策略 (由底向上逐级验证):
#   基础时钟   -> gptp_phc      (PHC 计数器 / 调频 / 调相 / 初始化)
#   时间戳捕获 -> gptp_htsu     (t2/t3 打标 + 驻留时间)
#   透明钟     -> gptp_tc       (one-step correctionField 改写)
#   链路延迟   -> gptp_pdelay   (P2P 双向延迟测量状态机)
#   接口胶合   -> gptp_mac_glue (PTP 帧识别 / msgType / CF 改写)
#   控制面     -> gptp_bmca     (最佳主时钟选举)
#   执行面     -> gptp_servo    (PI 伺服环)
#   集成层     -> gptp_top      (单端口核心端到端联动)
#   系统层     -> gptp_switch   (多端口 / 共享PHC / 独立Pdelay / BMCA / 同步残差)
# 用法: cd tsn_8021as && bash sim/run_sim.sh
# ============================================================
set -e
cd "$(dirname "$0")/.."

INC="-Isrc/um"
DEF="src/um/gptp_defines.v"

PASS_CNT=0
FAIL_CNT=0

echo "=========================================="
echo " TSN 802.1AS gPTP 分层回归测试"
echo "=========================================="

run_tb () {
    local name=$1; shift
    echo "[run] 编译 $name ..."
    iverilog -g2012 $INC -o sim/$name.vvp $DEF "$@" tb/$name.v
    echo "[run] 运行 $name ..."
    if vvp sim/$name.vvp | tee sim/$name.log | grep -q "\[PASS\]"; then
        PASS_CNT=$((PASS_CNT+1))
    else
        FAIL_CNT=$((FAIL_CNT+1))
        echo "  *** $name 未通过 (见上) ***"
    fi
}

# ---- 基础层 ----
run_tb tb_gptp_phc      src/um/gptp_phc.v
run_tb tb_gptp_htsu     src/um/gptp_htsu.v
run_tb tb_gptp_tc       src/um/gptp_tc.v
run_tb tb_gptp_pdelay   src/um/gptp_pdelay.v
run_tb tb_gptp_mac_glue src/um/gptp_mac_glue.v

# ---- 帧解析 (GMII 字节流 -> PTP 字段提取) ----
run_tb tb_gptp_frame_parser src/um/gptp_frame_parser.v

# ---- 控制面 / 执行面 ----
run_tb tb_gptp_bmca     src/um/gptp_bmca.v
run_tb tb_gptp_servo    src/um/gptp_servo.v

# ---- 集成层 (覆盖全部子模块) ----
run_tb tb_gptp_top      src/um/gptp_phc.v src/um/gptp_htsu.v src/um/gptp_tc.v \
                         src/um/gptp_pdelay.v src/um/gptp_bmca.v src/um/gptp_servo.v \
                         src/um/gptp_mac_glue.v src/um/gptp_frame_parser.v \
                         src/um/gptp_rx_fifo.v src/um/gptp_tx_gen.v \
                         src/um/gptp_top.v src/um/gptp_switch.v

# ---- 系统层 (多端口交换机集成) ----
run_tb tb_gptp_switch   src/um/gptp_phc.v src/um/gptp_htsu.v src/um/gptp_tc.v \
                         src/um/gptp_pdelay.v src/um/gptp_bmca.v src/um/gptp_servo.v \
                         src/um/gptp_mac_glue.v src/um/gptp_frame_parser.v \
                         src/um/gptp_rx_fifo.v src/um/gptp_tx_gen.v \
                         src/um/gptp_top.v src/um/gptp_switch.v

# ---- 级联端到端 (GM->线缆->Slave, TC 链式累积 CF) ----
run_tb tb_gptp_cascade  src/um/gptp_phc.v src/um/gptp_htsu.v src/um/gptp_tc.v \
                         src/um/gptp_pdelay.v src/um/gptp_bmca.v src/um/gptp_servo.v \
                         src/um/gptp_mac_glue.v src/um/gptp_frame_parser.v \
                         src/um/gptp_rx_fifo.v src/um/gptp_tx_gen.v \
                         src/um/gptp_top.v src/um/gptp_switch.v

# ---- MAC 适配层 (GMII 透传 / XGMII / AXI-S 占位) ----
run_tb tb_gptp_mac_adapt src/um/gptp_mac_adapt.v

echo "=========================================="
echo " 结果: PASS=$PASS_CNT  FAIL=$FAIL_CNT"
echo "=========================================="
if [ "$FAIL_CNT" -ne 0 ]; then
    exit 1
fi
