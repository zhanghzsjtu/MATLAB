# -*- coding: utf-8 -*-
# fix_tb_ascii.py -- replace Chinese $display strings in all tb/*.v with
# ASCII English, so xsim/ModelSim console output has no mojibake on Windows.
import glob, os, io

TB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tb")

# Order matters: longer/more specific phrases first.
MAPPING = [
    ("全部检查项通过", "ALL CHECKS PASSED"),
    ("存在失败项", "SOME CHECKS FAILED"),
    ("提取正确", "field extraction OK"),
    ("A owner 端口未发出 Sync 帧", "A owner did not send Sync"),
    ("B 端口1 未收到来自 A 的帧 (线缆不通)", "B port1 got no frame from A (link down)"),
    ("B 端口1 透传流未解析出 Follow_Up (CF 累积不可验证)", "B port1 passthrough has no Follow_Up (CF n/a)"),
    ("B 透传 FU 的 cf=0, 透明钟未叠加 residence (链式累积失败)", "B FU cf=0, TC did not add residence (chain fail)"),
    ("B 透传 FU 的 cf=%0h (非零, 透明钟 residence 已叠加 -> 链式累积正确)",
     "B FU cf=%0h (non-zero, TC added residence -> chain OK)"),
    ("B 端口1 is_gm=%b, 期望 0 (A 的 Announce 更优, B 应为 Slave)",
     "B port1 is_gm=%b, expected 0 (A better, B=Slave)"),
    ("B 端口1 role=%0d, 期望 SLAVE(1) (BMCA 未收敛)", "B port1 role=%0d, expected SLAVE(1) (BMCA n/a)"),
    ("B 端口1 BMCA 收敛为 Slave (role=1, is_gm=0), Announce 链路打通",
     "B port1 BMCA->Slave (role=1,is_gm=0), announce OK"),
    ("级联链路异常", "cascade chain abnormal"),
    ("A(owner=0) 主动发 Sync+FU -> 线缆 -> B(端口1) 收包",
     "A(owner=0) sends Sync+FU -> cable -> B(port1) rx"),
    ("GM(A) 主动出帧经线缆到达 Slave(B), TC 链式累积 CF 正确, BMCA 收敛",
     "GM(A) frame via cable to Slave(B), TC chain CF OK, BMCA converged"),
    ("XGMII 占位输出非 0 (预期占位, 忽略)", "XGMII placeholder non-zero (expected, ignored)"),
    ("GMII 透传端口连通, XGMII/AXI-S 占位就绪", "GMII passthrough connected, XGMII/AXI-S ready"),
    ("owner 端口未主动产生 o_tx_sop 出帧脉冲", "owner produced no o_tx_sop pulse"),
    ("owner 端口发出的帧未识别为 Sync(msgType=0)", "owner frame not Sync(msgType=0)"),
    ("owner 端口未发出 Follow_Up(msgType=8)", "owner produced no Follow_Up(msgType=8)"),
    ("owner 端口主动生成 Sync+Follow_Up 出帧 (真实 TX 转发闭环)",
     "owner generates Sync+Follow_Up (real TX loop)"),
    ("o_phc_owner=%0d 期望 0(GM)", "o_phc_owner=%0d expected 0(GM)"),
    ("o_phc_owner 未锁定 GM 端口0", "o_phc_owner not locked to GM port0"),
    ("非 owner 端口 servo 写透传到了 PHC (仲裁失效)", "non-owner servo write leaked to PHC (arb fail)"),
    ("owner 端口 servo 写未透传到 PHC", "owner servo write not passed to PHC"),
    ("servo 仲裁正确 (仅 owner 写 PHC, 非 owner 屏蔽)", "servo arbitration OK (owner only writes PHC)"),
    ("多端口 gPTP 集成仿真 — 最终同步效果", "Multi-port gPTP integration sim - final sync result"),
    ("GM 时间基准", "GM time base"),
    ("端口%-1d: role=%0d peer_delay=%0d ns servo_locked=%0b",
     "Port%-1d: role=%0d peer_delay=%0d ns servo_locked=%0b"),
    ("同步残差 (各端口相对 GM 的链路不对称, gPTP 测得值):",
     "Sync residual (per-port asymmetry vs GM, measured):"),
    ("端口0: 实测 %0d ns  (注入链路 ~10ns)", "Port0: measured %0d ns (injected ~10ns)"),
    ("端口1: 实测 %0d ns  (注入链路 ~25ns)", "Port1: measured %0d ns (injected ~25ns)"),
    ("端口2: 实测 %0d ns  (注入链路 ~40ns)", "Port2: measured %0d ns (injected ~40ns)"),
    ("各端口独立测得不同链路延迟, servo 将据此把本地时钟",
     "each port measures its own link delay; servo will align local clock"),
    ("对齐到 GM, 最终同步精度 ~ 残差 + 时钟漂移 (本模型未计漂移)",
     "to GM; final sync accuracy ~ residual + drift (drift not modeled)"),
    ("peer_delay 未体现链路差异 (monotonic)", "peer_delay not monotonic per port"),
    ("集成验证通过 (3端口/共享PHC/独立Pdelay)", "integration PASS (3 ports/shared PHC/indep Pdelay)"),
]

def has_cjk(s):
    return any('\u4e00' <= ch <= '\u9fff' for ch in s)

def main():
    changed = 0
    remaining = []
    for path in sorted(glob.glob(os.path.join(TB, "*.v"))):
        with io.open(path, "r", encoding="utf-8") as f:
            lines = f.readlines()
        out = []
        for line in lines:
            for cn, en in MAPPING:
                if cn in line:
                    line = line.replace(cn, en)
                    changed += 1
            out.append(line)
        with io.open(path, "w", encoding="utf-8", newline="") as f:
            f.writelines(out)
        # report leftover Chinese inside $display only
        for ln in out:
            if "$display" in ln and has_cjk(ln):
                remaining.append((os.path.basename(path), ln.strip()))
    print("replaced: %d occurrences" % changed)
    if remaining:
        print("still Chinese inside $display:")
        for f, l in remaining:
            print("  %s: %s" % (f, l))
    else:
        print("no Chinese left inside any $display")

if __name__ == "__main__":
    main()
