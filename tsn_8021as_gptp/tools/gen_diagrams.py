#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 gPTP 可视化报告所需的示意 SVG (架构/状态机/同步对比/因果链), 纯 Python."""
import os
OUT = "doc/img"
os.makedirs(OUT, exist_ok=True)
C = {"phc":"#0072BD","tc":"#D95319","htsu":"#2ca02c","pdelay":"#9467bd",
     "bmca":"#e377c2","servo":"#ff7f0e","glue":"#17becf","phc2":"#0072BD"}

def box(svg, x, y, w, h, title, sub="", fill="#eef3fb", stroke="#0072BD", tcol="#1f2d3d"):
    svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="{fill}" stroke="{stroke}" stroke-width="2"/>')
    svg.append(f'<text x="{x+w/2}" y="{y+h/2-4}" text-anchor="middle" font-size="13" font-weight="bold" fill="{tcol}">{title}</text>')
    if sub:
        svg.append(f'<text x="{x+w/2}" y="{y+h/2+13}" text-anchor="middle" font-size="10" fill="#566">{sub}</text>')

def arrow(svg, x1,y1,x2,y2,color="#9aa7b8",label=""):
    svg.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="1.6" marker-end="url(#ah)"/>')
    if label:
        mx,my=(x1+x2)/2,(y1+y2)/2
        svg.append(f'<text x="{mx}" y="{my-4}" text-anchor="middle" font-size="9" fill="#788">{label}</text>')

def header(svg, w, title):
    svg.append(f'<text x="20" y="26" font-size="16" font-weight="bold" fill="#1f2d3d">{title}</text>')

def save(name, w, h, body):
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" font-family="Consolas,Menlo,monospace">']
    svg.append('<defs><marker id="ah" markerWidth="9" markerHeight="9" refX="7" refY="3" orient="auto"><path d="M0,0 L7,3 L0,6 Z" fill="#9aa7b8"/></marker></defs>')
    svg += body
    svg.append('</svg>')
    p = os.path.join(OUT, name)
    with open(p, "w", encoding="utf-8") as f:
        f.write("\n".join(svg))
    print("wrote", p)

# ---------- 1) 单端口架构数据流 ----------
def arch_single_real():
    w,h=940,560; s=[]
    s.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" font-family="Consolas,Menlo,monospace">')
    s.append('<defs><marker id="ah" markerWidth="9" markerHeight="9" refX="7" refY="3" orient="auto"><path d="M0,0 L7,3 L0,6 Z" fill="#9aa7b8"/></marker></defs>')
    s.append(f'<text x="20" y="26" font-size="16" font-weight="bold" fill="#1f2d3d">单端口架构数据流 (gptp_top: MAC 进 → 时间同步 → MAC 出)</text>')
    # MAC RX
    box(s, 30, 250, 110, 60, "MAC RX", "i_rx_* 字节流", "#eaf1fb", "#0072BD")
    # glue
    box(s, 180, 250, 120, 60, "mac_glue", "0x88F7解析/SOF", "#e6f7fa", "#17becf")
    arrow(s, 140, 280, 180, 280, "#17becf")
    # HTSU
    box(s, 350, 60, 130, 56, "htsu", "t2/t3打标", "#e9f7ec", "#2ca02c")
    # TC
    box(s, 350, 160, 130, 56, "tc", "CF改写", "#fdeee2", "#D95319")
    # Pdelay
    box(s, 350, 360, 130, 56, "pdelay", "P2P延迟", "#f3eafb", "#9467bd")
    # PHC
    box(s, 560, 220, 130, 70, "PHC", "共享时间基准", "#eaf1fb", "#0072BD")
    # BMCA
    box(s, 560, 360, 130, 56, "bmca", "角色选举", "#fbe9f4", "#e377c2")
    # Servo
    box(s, 740, 220, 120, 70, "servo", "PI闭环", "#fff0e0", "#ff7f0e")
    # MAC TX
    box(s, 740, 360, 120, 60, "MAC TX", "o_tx_* 出帧", "#eaf1fb", "#0072BD")
    # arrows glue->htsu/tc/pdelay
    arrow(s, 300, 275, 360, 95, "#2ca02c", "SOF")
    arrow(s, 300, 280, 360, 188, "#D95319")
    arrow(s, 300, 295, 360, 388, "#9467bd", "Pdelay")
    # htsu/tc -> PHC/TC
    arrow(s, 480, 88, 560, 235, "#2ca02c", "ts")
    arrow(s, 480, 188, 560, 250, "#D95319", "res")
    arrow(s, 480, 388, 560, 285, "#9467bd", "peerDelay")
    # bmca->servo(role)
    arrow(s, 560, 388, 740, 255, "#e377c2", "role")
    # servo -> PHC (adjust)
    arrow(s, 740, 255, 690, 255, "#ff7f0e", "adjtime/adjfine")
    # PHC -> TC (time) and TC->TX
    arrow(s, 620, 250, 690, 320, "#0072BD")
    arrow(s, 690, 360, 740, 380, "#D95319", "CF")
    arrow(s, 800, 290, 800, 360, "#0072BD", "sync")
    # Announce / Sync in
    s.append(f'<text x="560" y="345" font-size="10" fill="#788">↑ Announce(i_announce_rx)</text>')
    s.append(f'<text x="740" y="205" font-size="10" fill="#788">↑ Sync(i_sync_rx)</text>')
    s.append('</svg>')
    save("arch_single.svg", w, h, s[2:-1])  # 保留标题文本, 去掉函数内冗余 svg/defs/闭合

# ---------- 2) 多端口交换机架构 ----------
def arch_switch_real():
    w,h=940,500; s=[]
    s.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" font-family="Consolas,Menlo,monospace">')
    s.append('<defs><marker id="ah" markerWidth="9" markerHeight="9" refX="7" refY="3" orient="auto"><path d="M0,0 L7,3 L0,6 Z" fill="#9aa7b8"/></marker></defs>')
    s.append(f'<text x="20" y="26" font-size="16" font-weight="bold" fill="#1f2d3d">多端口交换机架构 (N 端口共享一个 PHC, generate 例化)</text>')
    # shared PHC center
    box(s, 400, 200, 140, 80, "共享 PHC", "全网统一时间面", "#eaf1fb", "#0072BD")
    # 3 ports
    ports=[("端口0 (GM)", 40, 80), ("端口1", 40, 210), ("端口2", 40, 340)]
    for name,px,py in ports:
        box(s, px, py, 130, 90, name, "top+bmca+servo", "#f3f6fb", "#0072BD")
        # rx arrow into port
        s.append(f'<text x="{px-2}" y="{py+45}" font-size="9" fill="#788" text-anchor="end">RX</text>')
        # port -> PHC
        arrow(s, px+130, py+45, 400, 240, "#2ca02c", "")
        # PHC -> port (time read / servo write)
        arrow(s, 400, 240, px+130, py+30, "#ff7f0e", "")
    # GM time out
    box(s, 580, 200, 150, 60, "GM 时间输出", "→ 802.1Qbv TAS", "#eaf1fb", "#0072BD")
    arrow(s, 540, 240, 580, 230, "#0072BD", "ro_gm_time")
    # per-port TX (forwarding)
    for (px,py) in [p[1:] for p in ports]:
        s.append(f'<text x="{px+125}" y="{py+82}" font-size="9" fill="#D95319">TX转发(o_tx_*)</text>')
    s.append('</svg>')
    save("arch_switch.svg", w, h, s[2:-1])

# ---------- 3) 状态机总览 ----------
def fsm_overview():
    w,h=1000,620; s=[]
    s.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" font-family="Consolas,Menlo,monospace">')
    s.append('<defs><marker id="ah" markerWidth="9" markerHeight="9" refX="7" refY="3" orient="auto"><path d="M0,0 L7,3 L0,6 Z" fill="#9aa7b8"/></marker></defs>')
    s.append(f'<text x="20" y="26" font-size="16" font-weight="bold" fill="#1f2d3d">各模块三段式 FSM 状态机 (独热编码 P_ST_, 跳转条件独立 wire)</text>')
    def fsm(cx, cy, title, states, trans):
        s.append(f'<text x="{cx}" y="{cy-70}" text-anchor="middle" font-size="13" font-weight="bold" fill="#0072BD">{title}</text>')
        n=len(states); R=26
        import math
        pos=[]
        for i,st in enumerate(states):
            ang = -math.pi/2 + i*2*math.pi/n
            x=cx+R*1.6*math.cos(ang); y=cy+R*1.4*math.sin(ang)
            pos.append((x,y))
        for (x,y),(nm,col) in zip(pos,states):
            s.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{R}" fill="{col}" opacity="0.18" stroke="{col}" stroke-width="2"/>')
            s.append(f'<text x="{x:.0f}" y="{y+4:.0f}" text-anchor="middle" font-size="9" fill="#334">{nm}</text>')
        for (a,b,lb) in trans:
            x1,y1=pos[a]; x2,y2=pos[b]
            s.append(f'<line x1="{x1:.0f}" y1="{y1:.0f}" x2="{x2:.0f}" y2="{y2:.0f}" stroke="#9aa7b8" stroke-width="1.3" marker-end="url(#ah)"/>')
    # HTSU
    fsm(170,120,"HTSU (时间戳)",[("IDLE","#2ca02c"),("RX","#2ca02c"),("WAIT","#2ca02c"),("TX","#2ca02c")],
        [(0,1,"rx_sof"),(1,2,"eof"),(2,3,"tx_sof"),(3,0,"eof")])
    # Pdelay
    fsm(500,120,"Pdelay (P2P)",[("IDLE","#9467bd"),("REQ","#9467bd"),("WAIT","#9467bd"),("RESP","#9467bd"),("CALC","#9467bd")],
        [(0,1,"period"),(1,2,""),(2,3,"resp"),(3,4,"resfu"),(4,0,"")])
    # BMCA
    fsm(830,120,"BMCA (选举)",[("IDLE","#e377c2"),("CMP","#e377c2"),("DONE","#e377c2")],
        [(0,1,"announce"),(1,2,"cmp_ok"),(2,0,"")])
    # Servo
    fsm(170,360,"Servo (PI)",[("IDLE","#ff7f0e"),("CALC","#ff7f0e"),("OUT","#ff7f0e")],
        [(0,1,"sync"),(1,2,""),(2,0,"")])
    # MAC glue (linear)
    s.append(f'<text x="500" y="300" text-anchor="middle" font-size="13" font-weight="bold" fill="#17becf">MAC glue (RX 流)</text>')
    for i,(nm) in enumerate(["RX_IDLE","RX_HDR","RX_BODY"]):
        x=420+i*90
        s.append(f'<rect x="{x}" y="320" width="80" height="40" rx="6" fill="#17becf" opacity="0.18" stroke="#17becf" stroke-width="2"/>')
        s.append(f'<text x="{x+40}" y="344" text-anchor="middle" font-size="9" fill="#334">{nm}</text>')
        if i<2: s.append(f'<line x1="{x+80}" y1="340" x2="{x+90}" y2="340" stroke="#9aa7b8" stroke-width="1.3" marker-end="url(#ah)"/>')
    s.append(f'<text x="500" y="385" text-anchor="middle" font-size="9" fill="#788">SOF→HDR(取msgType/ET)→BODY(CF字节22~29改写)</text>')
    # note
    s.append(f'<text x="20" y="{h-14}" font-size="11" fill="#566">注: 全部状态机采用三段式 — 状态寄存器块仅更新 state_c; 组合块用 case 计算 state_n (default=P_ST_IDLE); 输出块单信号 if-else。跳转条件独立 p_st_*2p_st_*_start wire。</text>')
    save("fsm_overview.svg", w, h, s[2:-1])

# ---------- 4) 同步前后对比 ----------
def sync_compare():
    w,h=940,420; s=[]
    s.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" font-family="Consolas,Menlo,monospace">')
    s.append('<defs><marker id="ah" markerWidth="9" markerHeight="9" refX="7" refY="3" orient="auto"><path d="M0,0 L7,3 L0,6 Z" fill="#9aa7b8"/></marker></defs>')
    s.append(f'<text x="20" y="26" font-size="16" font-weight="bold" fill="#1f2d3d">同步前(时钟发散) vs 同步后(收敛到 GM)</text>')
    # 左: 发散
    s.append(f'<text x="230" y="60" text-anchor="middle" font-size="13" fill="#D95319">同步前: 各端口独立晶振 → 频率/相位发散</text>')
    import math
    for k,(col,lab) in enumerate([("#0072BD","端口A"),("#2ca02c","端口B"),("#9467bd","端口C")]):
        y0=90+k*40
        pts=[]
        for x in range(0,360,10):
            yy=y0 - (x/360)* (k+1)*70*math.sin(x/40.0) - (x/360)*k*30
            pts.append(f'{x+30:.0f},{yy:.0f}')
        s.append(f'<polyline points="{" ".join(pts)}" fill="none" stroke="{col}" stroke-width="1.8"/>')
        s.append(f'<text x="30" y="{y0+4}" font-size="10" fill="{col}">{lab}</text>')
    s.append(f'<text x="230" y="250" text-anchor="middle" font-size="10" fill="#788">offset 持续累积, 跨跳抖动叠加</text>')
    # 右: 收敛
    s.append(f'<text x="710" y="60" text-anchor="middle" font-size="13" fill="#2ca02c">同步后: servo 闭环, 全部对齐 GM 时间面</text>')
    for k,(col,lab) in enumerate([("#0072BD","GM"),("#2ca02c","端口B"),("#9467bd","端口C")]):
        y0=90+k*40
        pts=[]
        for x in range(0,360,10):
            yy=y0 - (x/360)* 8*math.sin(x/120.0)   # 微小残余
            pts.append(f'{x+520:.0f},{yy:.0f}')
        s.append(f'<polyline points="{" ".join(pts)}" fill="none" stroke="{col}" stroke-width="1.8"/>')
        s.append(f'<text x="520" y="{y0+4}" font-size="10" fill="{col}">{lab}</text>')
    s.append(f'<text x="710" y="250" text-anchor="middle" font-size="10" fill="#788">offset≈0, 残余=链路不对称(Pdelay测得)≈数十ns</text>')
    # arrow between
    s.append(f'<line x1="400" y1="150" x2="510" y2="150" stroke="#0072BD" stroke-width="2" marker-end="url(#ah)"/>')
    s.append(f'<text x="455" y="140" text-anchor="middle" font-size="10" fill="#0072BD">servo</text>')
    s.append('</svg>')
    save("sync_compare.svg", w, h, s[2:-1])

# ---------- 5) 子模块不可或缺因果链 ----------
def causal_chain():
    w,h=1000,440; s=[]
    s.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" font-family="Consolas,Menlo,monospace">')
    s.append('<defs><marker id="ah" markerWidth="9" markerHeight="9" refX="7" refY="3" orient="auto"><path d="M0,0 L7,3 L0,6 Z" fill="#9aa7b8"/></marker></defs>')
    s.append(f'<text x="20" y="26" font-size="16" font-weight="bold" fill="#1f2d3d">每个子模块为何不可或缺 (缺一则 50ns 同步失效)</text>')
    items=[("BMCA","选定全网基准 GM\n缺→不知以谁为准", "#e377c2"),
           ("HTSU","线上 SOF 硬打戳\n缺→时间戳由软件引入抖动", "#2ca02c"),
           ("Pdelay","P2P 测链路不对称\n缺→双向延迟无法抵消", "#9467bd"),
           ("TC","累加 residence 到 CF\n缺→跨跳抖动累积", "#D95319"),
           ("Servo","PI 闭环收敛 offset\n缺→频率/相位永不对齐", "#ff7f0e"),
           ("MAC glue","识别 0x88F7/提 msgType\n缺→无法接入真实帧流", "#17becf"),
           ("PHC","自由运行时间基准\n缺→无统一时间面", "#0072BD")]
    x0,y0=30,60; bw,bh=125,80; gap=12
    pos=[]
    for i,(nm,desc,col) in enumerate(items):
        r=i//4; c=i%4
        x=x0+c*(bw+gap); y=y0+r*(bh+gap+30)
        pos.append((x,y))
        s.append(f'<rect x="{x}" y="{y}" width="{bw}" height="{bh}" rx="8" fill="{col}" opacity="0.15" stroke="{col}" stroke-width="2"/>')
        s.append(f'<text x="{x+bw/2}" y="{y+22}" text-anchor="middle" font-size="12" font-weight="bold" fill="{col}">{nm}</text>')
        for j,line in enumerate(desc.split("\n")):
            s.append(f'<text x="{x+bw/2}" y="{y+42+j*15}" text-anchor="middle" font-size="9" fill="#445">{line}</text>')
    # arrows chain
    for i in range(len(items)-1):
        x1,y1=pos[i]; x2,y2=pos[i+1]
        if y1==y2:
            s.append(f'<line x1="{x1+bw}" y1="{y1+bh/2}" x2="{x2}" y2="{y2+bh/2}" stroke="#9aa7b8" stroke-width="1.5" marker-end="url(#ah)"/>')
        else:
            s.append(f'<line x1="{x1+bw/2}" y1="{y1+bh}" x2="{x2+bw/2}" y2="{y2}" stroke="#9aa7b8" stroke-width="1.5" marker-end="url(#ah)"/>')
    # final
    fx=30+4*(bw+gap); fy=y0+2*(bh+gap+30)
    s.append(f'<rect x="{fx}" y="{fy}" width="{bw}" height="50" rx="8" fill="#0072BD" opacity="0.9"/>')
    s.append(f'<text x="{fx+bw/2}" y="{fy+30}" text-anchor="middle" font-size="12" font-weight="bold" fill="#fff">50ns 同步达成</text>')
    s.append(f'<line x1="{pos[-1][0]+bw/2}" y1="{pos[-1][1]+bh}" x2="{fx+bw/2}" y2="{fy}" stroke="#0072BD" stroke-width="1.8" marker-end="url(#ah)"/>')
    s.append('</svg>')
    save("causal_chain.svg", w, h, s[2:-1])

if __name__ == "__main__":
    arch_single_real()
    arch_switch_real()
    fsm_overview()
    sync_compare()
    causal_chain()
    print("ALL DIAGRAMS DONE")
