#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
VCD -> 波形 SVG 渲染器 (gPTP 可视化报告配套, 纯 Python 无第三方依赖)
解析 iverilog 生成的 .vcd, 抽取关键信号, 渲染为时间-值波形 SVG.
输出目录: doc/img/
"""
import os, re

VCD_DIR = "sim"
OUT_DIR = "doc/img"
os.makedirs(OUT_DIR, exist_ok=True)

def parse_vcd(path):
    """返回 (times, sig): times=排序时间列表; sig={信号名:[(t,值串)]}
    支持多字符 VCD identifier code; 数组信号仅保留首个声明(端口0)."""
    with open(path, encoding="utf-8", errors="replace") as f:
        txt = f.read()
    decl, _, body = txt.partition("$enddefinitions")
    code_map = {}        # code -> 信号名 (数组信号仅保留首个声明=端口0)
    name_seen = set()
    # 支持带 [hi:lo] 位宽后缀的声明
    for m in re.finditer(r"\$var\s+\w+\s+\d+\s+(\S+)\s+([\w.\[\]]+)(?:\s+\[\d+:\d+\])?\s*\$end", decl):
        code, name = m.group(1), m.group(2)
        if name not in name_seen:
            code_map[code] = name
            name_seen.add(name)
    times = []
    sig = {}
    cur_t = 0
    i, n = 0, len(body)
    while i < n:
        c = body[i]
        if c == '#':
            j = i + 1
            while j < n and body[j] != '\n':
                j += 1
            try:
                cur_t = int(body[i+1:j])
                times.append(cur_t)
            except ValueError:
                pass
            i = j + 1
        elif c in 'bB':        # 多比特二进制 b<bits> <code>
            j = i + 1
            while j < n and body[j] != ' ':
                j += 1
            val = body[i+1:j]
            k = j + 1
            while k < n and body[k] != '\n':
                k += 1
            code = body[j+1:k].strip()
            if code in code_map:
                sig.setdefault(code_map[code], []).append((cur_t, val))
            i = k + 1
        elif c in '01xzXZ':    # 单比特 <bit><code...> (code 可为多字符)
            j = i + 1
            while j < n and body[j] != '\n':
                j += 1
            code = body[i+1:j].strip()
            if code in code_map:
                sig.setdefault(code_map[code], []).append((cur_t, c))
            i = j + 1
        else:
            i += 1
    # sig 已经按信号名(而非 code)建键, 直接返回即可
    return sorted(set(times)), sig

def to_int(val):
    if val in ('x', 'X', 'z', 'Z'):
        return None
    try:
        return int(val, 2) if len(val) > 1 else int(val)
    except Exception:
        return None

def render_svg(vcd_file, title, picks, fname, width=1100):
    """picks: list of (substr, label, color, kind)  kind: 'bool'|'num'"""
    times, sig = parse_vcd(vcd_file)
    tmax = max(times) if times else 1
    lanes = len(picks)
    margin_l, margin_r, margin_t, lane_h, gap = 150, 30, 46, 70, 16
    height = margin_t + lanes * (lane_h + gap) + 30
    plot_w = width - margin_l - margin_r
    x0 = margin_l
    def X(t):
        return x0 + (t / tmax) * plot_w

    svg = []
    svg.append(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}" font-family="Consolas,Menlo,monospace" font-size="13">')
    svg.append(f'<rect width="{width}" height="{height}" fill="#fbfcfe"/>')
    svg.append(f'<text x="{margin_l}" y="26" font-size="16" font-weight="bold" fill="#1f2d3d">{title}</text>')
    svg.append(f'<text x="{width-margin_r}" y="26" text-anchor="end" font-size="11" fill="#8a94a6">仿真时间 0..{tmax} tick</text>')
    # 时间网格
    for g in range(0, 11):
        gx = x0 + g/10*plot_w
        svg.append(f'<line x1="{gx:.1f}" y1="{margin_t-6}" x2="{gx:.1f}" y2="{height-20}" stroke="#e6eaf0" stroke-width="1"/>')
        svg.append(f'<text x="{gx:.1f}" y="{height-6}" font-size="9" fill="#aab2c0" text-anchor="middle">{int(g/10*tmax)}</text>')
    # 各 lane
    y = margin_t
    for (sub, label, color, kind) in picks:
        cand = [k for k in sig if sub in k]
        ly = y + lane_h/2
        svg.append(f'<line x1="{x0}" y1="{ly}" x2="{x0+plot_w}" y2="{ly}" stroke="#eef1f5" stroke-width="1"/>')
        svg.append(f'<text x="10" y="{ly+4}" font-size="12" fill="#33414f" font-weight="bold">{label}</text>')
        # 颜色标签
        svg.append(f'<rect x="10" y="{y+4}" width="6" height="14" fill="{color}"/>')
        if not cand:
            svg.append(f'<text x="{x0+10}" y="{ly+4}" font-size="11" fill="#d95319">信号未找到: {sub}</text>')
            y += lane_h + gap
            continue
        name = sorted(cand)[0]
        series = sig[name]
        pts = [(t, to_int(v)) for (t, v) in series if to_int(v) is not None]
        if kind == 'bool':
            # 数字波形: 阶梯 0/1
            path = []
            last = None
            for (t, v) in pts:
                yy = ly - (22 if v else 0)  # 数字量: 非零->上移
                if last is None:
                    path.append(f'M{X(t):.1f} {ly}')
                    path.append(f'L{X(t):.1f} {yy:.1f}')
                else:
                    path.append(f'L{X(t):.1f} {last:.1f}')
                    path.append(f'L{X(t):.1f} {yy:.1f}')
                last = yy
            if last is not None:
                path.append(f'L{X(tmax):.1f} {last:.1f}')
            svg.append(f'<path d="{" ".join(path)}" fill="none" stroke="{color}" stroke-width="1.6"/>')
        else:  # num -> 阶梯折线
            if pts:
                vmin = min(v for _, v in pts); vmax = max(v for _, v in pts)
                span = (vmax - vmin) or 1
                def Y(v):
                    r = (v - vmin) / span
                    if r < 0:
                        r = 0.0
                    elif r > 1:
                        r = 1.0
                    return y + lane_h - 8 - r*(lane_h-16)
                path = []
                for idx, (t, v) in enumerate(pts):
                    xx, yy = X(t), Y(v)
                    if idx == 0:
                        path.append(f'M{xx:.1f} {yy:.1f}')
                    else:
                        path.append(f'L{xx:.1f} {Y(pts[idx-1][1]):.1f}')
                        path.append(f'L{xx:.1f} {yy:.1f}')
                path.append(f'L{X(tmax):.1f} {Y(pts[-1][1]):.1f}')
                svg.append(f'<path d="{" ".join(path)}" fill="none" stroke="{color}" stroke-width="1.6"/>')
                svg.append(f'<text x="{x0+plot_w}" y="{y+12}" text-anchor="end" font-size="9" fill="#aab2c0">[{vmin}..{vmax}]</text>')
        y += lane_h + gap
    svg.append('</svg>')
    out = os.path.join(OUT_DIR, fname)
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(svg))
    print("wrote", out)

if __name__ == "__main__":
    base = "E:/03-tsn/tsn_8021as/tsn_8021as"
    os.chdir(base)
    # 1) PHC
    render_svg("sim/tb_gptp_phc.vcd",
               "PHC 高精度本地时钟: 自由运行计数 + 调相(adjtime)/调频(adjfine)",
               [("ro_time_ns", "time_ns", "#0072BD", "num"),
                ("w_adjtime_wr", "adjtime_wr", "#D95319", "bool"),
                ("w_adjfine_wr", "adjfine_wr", "#2ca02c", "bool")],
               "wave_phc.svg")
    # 2) HTSU
    render_svg("sim/tb_gptp_htsu.vcd",
               "HTSU 硬件时间戳: SOF 锁存 t2/t3, EOF 算 residence",
                [("i_rx_sof", "rx_sof", "#0072BD", "bool"),
                ("i_tx_sof", "tx_sof", "#2ca02c", "bool"),
                ("ro_residence_ns", "residence_ns", "#D95319", "num"),
                ("o_residence_vld", "residence_vld", "#9467bd", "bool")],
               "wave_htsu.svg")
    # 3) TC
    render_svg("sim/tb_gptp_tc.vcd",
               "透明时钟 TC: pkt_vld -> cf_wr/cf_rd 脉冲, cf_out 改写",
                [("i_pkt_vld", "pkt_vld", "#0072BD", "bool"),
                ("ro_cf_wr", "cf_wr(one-step)", "#D95319", "bool"),
                ("o_cf_rd", "cf_rd(two-step)", "#2ca02c", "bool"),
                ("o_cf_out", "cf_out", "#9467bd", "num")],
               "wave_tc.svg")
    # 4) Pdelay
    render_svg("sim/tb_gptp_pdelay.vcd",
               "Pdelay P2P 对等延迟: Req/Resp 交换 -> peer_delay",
               [("i_pdreq_send", "pdreq_send", "#0072BD", "bool"),
                ("o_pdreq_vld", "pdreq_vld", "#D95319", "bool"),
                ("i_pdresp_rx", "pdresp_rx", "#2ca02c", "bool"),
                ("i_pdresfu_rx", "pdresfu_rx", "#9467bd", "bool"),
                ("ro_peer_delay_ns", "peer_delay_ns", "#e377c2", "num")],
               "wave_pdelay.svg")
    # 5) BMCA
    render_svg("sim/tb_gptp_bmca.vcd",
               "BMCA 最佳主时钟选举: Announce -> 角色(2:Passive/1:Slave/0:Master)",
               [("i_announce_rx", "announce_rx", "#0072BD", "bool"),
                ("o_port_role", "port_role", "#D95319", "num"),
                ("o_is_gm", "is_gm", "#2ca02c", "bool")],
               "wave_bmca.svg")
    # 6) Servo
    render_svg("sim/tb_gptp_servo.vcd",
               "PI 伺服环: Sync -> adjtime/adjfine 闭环, locked 置位",
               [("i_sync_rx", "sync_rx", "#0072BD", "bool"),
                ("o_adjtime_wr", "adjtime_wr", "#D95319", "bool"),
                ("o_adjfine_wr", "adjfine_wr", "#2ca02c", "bool"),
                ("o_servo_locked", "servo_locked", "#9467bd", "bool")],
               "wave_servo.svg")
    # 7) MAC glue
    render_svg("sim/tb_gptp_mac_glue.vcd",
               "MAC 胶合: 帧流识别 -> CF 字节级改写 (帧偏移22~29)",
               [("i_rx_sop", "rx_sop", "#0072BD", "bool"),
                ("i_rx_eop", "rx_eop", "#D95319", "bool"),
                ("i_rx_vld", "rx_vld", "#2ca02c", "bool"),
                ("o_cf_wr", "cf_wr", "#9467bd", "bool")],
               "wave_mac_glue.svg")
    # 8) Switch
    render_svg("sim/tb_gptp_switch.vcd",
               "Switch 三端口: 共享 GM 时间基准 + 真实 TX 转发 + servo 仲裁",
                [("ro_gm_time_ns", "gm_time_ns", "#0072BD", "num"),
                ("o_tx_vld", "tx_vld(转发流)", "#D95319", "bool"),
                ("o_phc_adjtime_wr", "phc_adjtime_wr(仲裁)", "#2ca02c", "bool"),
                ("o_is_gm", "is_gm", "#9467bd", "bool")],
               "wave_switch.svg")
    print("ALL SVG WAVEFORMS DONE")
