#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
stap_rtl_compare.py — STAP RTL vs MATLAB 黄金对比（stap_4ch 逐级验证）
=================================================================
RTL 输出（fpga/tb/stap_rtl_out.txt，每行 out_i out_q，22bit 补码 hex）
vs MATLAB 定点黄金（matlab/stap_out/stap_gold.txt，同格式）。

判据（rtl-matlab-stage-verify）：
  1. 行数一致（12288 = 64 bin × 192 gate）
  2. 逐点绝对误差 ≤ 1 LSB（RTL 算术右移截断 vs MATLAB round，±1 差）
  3. 主峰相对误差 ≤ 1e-2（22bit 动态范围）
  4. 杂波抑制有效性：输出谱杂波区（DC bin 门 14 附近）幅度远小于目标门

用法：python stap_rtl_compare.py [rtl_out] [gold_out]
退出码：0=全部 PASS；1=存在 FAIL
"""
import sys, os, math

def read_pairs(path):
    vals = []
    with open(path) as f:
        for ln in f:
            ln = ln.strip()
            if not ln:
                continue
            tok = ln.split()
            vals.append((int(tok[0], 16), int(tok[1], 16)))
    return vals

def to_signed22(v):
    return v - (1 << 22) if v & (1 << 21) else v

def main():
    base = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(base)
    rtl_f = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "data/stap_rtl_out.txt")
    gold_f = sys.argv[2] if len(sys.argv) > 2 else os.path.join(root, "data/stap_gold.txt")
    rtl = read_pairs(rtl_f)
    gold = read_pairs(gold_f)
    n = min(len(rtl), len(gold))
    print(f"=== STAP RTL vs MATLAB 黄金对比 ===")
    print(f"  RTL 行数 {len(rtl)}  Gold 行数 {len(gold)}")
    if len(rtl) != len(gold):
        print("FAIL: 行数不一致")
        return 1
    # 逐点误差（I/Q 分开）
    max_abs_i = max_abs_q = 0
    max_rel_i = 0.0          # 仅在 |gold| ≥ 主峰×1e-3 的点统计（避免小值点 1 LSB 污染）
    peak_abs_i = 0
    n_exact = 0
    n_lsb1 = 0
    for i in range(n):
        ri, rq = to_signed22(rtl[i][0]), to_signed22(rtl[i][1])
        gi, gq = to_signed22(gold[i][0]), to_signed22(gold[i][1])
        ei, eq = abs(ri - gi), abs(rq - gq)
        max_abs_i = max(max_abs_i, ei)
        max_abs_q = max(max_abs_q, eq)
        peak_abs_i = max(peak_abs_i, abs(gi))
        if ei == 0:
            n_exact += 1
        elif ei <= 1:
            n_lsb1 += 1
    print(f"  逐点误差：I max_abs={max_abs_i}  Q max_abs={max_abs_q}  主峰 {peak_abs_i}")
    print(f"  精确一致 {n_exact} 点（{100.0*n_exact/n:.2f}%），±1LSB 内 {n_exact+n_lsb1} 点（{100.0*(n_exact+n_lsb1)/n:.2f}%）")
    # 主峰相对误差 = 最大绝对误差 / 主峰幅度（数值级一致的度量；1 LSB ≈ 4.3e-5）
    max_rel_i = max_abs_i / peak_abs_i if peak_abs_i > 0 else 0.0
    print(f"  主峰相对误差 {max_rel_i:.2e}（判据 ≤1e-2）")
    # 杂波抑制有效性（黄金定点域：DC bin 杂波门 vs 目标门）
    def amp_at(bin_idx, gate0):
        line = bin_idx * 192 + gate0
        return abs(to_signed22(gold[line][0])) + 1e-9
    clut = amp_at(0, 13)
    tgt  = amp_at(0, 90)
    ok1 = len(rtl) == len(gold) and max_abs_i <= 1 and max_abs_q <= 1
    ok2 = max_rel_i <= 1e-2
    ok3 = tgt > clut * 10                      # 目标/杂波 > 20dB（定点域）
    print(f"  [黄金定点域] DC bin 杂波门={clut:.0f} 目标门={tgt:.0f} 目标/杂波={20*math.log10(tgt/clut):.1f}dB")
    all_ok = ok1 and ok2 and ok3
    print(f"==> {'全部 PASS' if all_ok else '存在 FAIL'}")
    return 0 if all_ok else 1

if __name__ == "__main__":
    sys.exit(main())
