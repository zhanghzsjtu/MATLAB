# -*- coding: utf-8 -*-
"""七步精讲 9 张概念示意图 (v2: 修标题重叠 + ⊗/dagger 方框)
学术蓝 #0072BD / 橙 #D95319，禁用红色。
规则: box() 只放纯中文; 公式一律独立 mtext(); 标题 y=h-0.10。
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Rectangle, FancyArrowPatch
import matplotlib.font_manager as fm
import os

FONT = fm.FontProperties(fname=r"C:/Windows/Fonts/simhei.ttf")
plt.rcParams["font.family"] = "sans-serif"
plt.rcParams["axes.unicode_minus"] = False

BLUE   = "#0072BD"
ORANGE = "#D95319"
GRAY   = "#9AA0A6"
LBLUE  = "#EAF2FB"
LORANGE= "#FBEDE3"
DARK   = "#333333"
GREEN  = "#2E7D32"
LGREEN = "#EAF7EA"
OUT = os.path.join(os.path.dirname(__file__), "..", "images")
os.makedirs(OUT, exist_ok=True)

def newfig(w=6.8, h=3.6, title=None):
    fig, ax = plt.subplots(figsize=(w, h), dpi=150)
    ax.set_xlim(0, w); ax.set_ylim(0, h)
    ax.axis("off")
    if title:
        ax.text(w/2, h-0.10, title, ha="center", va="top",
                fontproperties=FONT, fontsize=12.5, color=DARK, weight="bold")
    return fig, ax

def box(ax, x, y, w, h, text, fc=LBLUE, ec=BLUE, tc=DARK, fs=11, weight="normal"):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.04,rounding_size=0.06",
                                fc=fc, ec=ec, lw=1.4))
    ax.text(x+w/2, y+h/2, text, ha="center", va="center",
            fontproperties=FONT, fontsize=fs, color=tc, weight=weight)

def arr(ax, x1, y1, x2, y2, ec=BLUE, w=1.6):
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2), arrowstyle="-|>",
                 mutation_scale=12, lw=w, color=ec))

def m(ax, x, y, s, fs=12, color=DARK, ha="center", va="center"):
    ax.text(x, y, s, ha=ha, va=va, fontsize=fs, color=color)

def c(ax, x, y, s, fs=9, color=DARK, ha="center", va="center"):
    ax.text(x, y, s, ha=ha, va=va, fontproperties=FONT, fontsize=fs, color=color)

# ---------- 图1 ----------
def fig1():
    fig, ax = newfig(6.8, 4.0, "图1  Kronecker 积块结构示意")
    box(ax, 0.4, 2.5, 0.9, 1.0, "a\n[1\n2]", fc=LORANGE, ec=ORANGE, fs=10)
    c(ax, 0.85, 3.65, "空间 a (2阵元)", color=ORANGE)
    box(ax, 0.4, 0.8, 0.9, 1.0, "s\n[3\n4]", fc=LBLUE, ec=BLUE, fs=10)
    c(ax, 0.85, 1.95, "时间 s (2脉冲)", color=BLUE)
    m(ax, 1.7, 2.0, r"$\otimes$", fs=18)
    # v box: 纯内容, 不放公式
    box(ax, 2.5, 0.55, 1.6, 2.7, "v\n\n[3, 6,\n 4, 8]", fc="#F4F6F8", ec=GRAY, fs=10)
    # 公式放在 box 上方
    m(ax, 3.3, 3.35, r"$v = s \otimes a$", fs=12)
    # 块标注
    ax.add_patch(Rectangle((2.5, 1.95), 1.6, 0.95, fc=LORANGE, ec="none", alpha=0.5))
    ax.add_patch(Rectangle((2.5, 0.95), 1.6, 0.95, fc=LBLUE, ec="none", alpha=0.5))
    c(ax, 4.45, 2.42, "块1: 3·a  ($s_1$=3)", ha="left", color=ORANGE, fs=8.5)
    c(ax, 4.45, 1.42, "块2: 4·a  ($s_2$=4)", ha="left", color=BLUE, fs=8.5)
    arr(ax, 4.15, 2.42, 4.13, 2.42, ec=ORANGE, w=1.2)
    arr(ax, 4.15, 1.42, 4.13, 1.42, ec=BLUE, w=1.2)
    c(ax, 0.4, 0.18, "规律: 每个 s 元素各乘整列 a，再首尾相接", ha="left", color=GRAY, fs=8.5)
    fig.savefig(os.path.join(OUT, "fig01_concept_kronecker.png"), bbox_inches="tight")
    plt.close(fig)

# ---------- 图2 ----------
def fig2():
    fig, ax = newfig(6.8, 4.0, "图2  能量泄漏示意图 (矩形脉冲)")
    gates = [1.2, 2.1, 3.0, 3.9, 4.8]
    for i, gx in enumerate(gates):
        col = LBLUE if i in (2,3) else "#F0F0F0"
        ax.add_patch(Rectangle((gx-0.35, 0.8), 0.7, 2.0, fc=col, ec=GRAY, lw=1.0))
        c(ax, gx, 0.62, "门%d"%(i+1), color=DARK)
    c(ax, 3.45, 0.38, "延迟轴 (距离门)", color=GRAY, fs=9)
    x = [1.2, 2.55, 3.9, 4.8]; y = [0.8, 2.8, 2.8, 0.8]
    ax.plot(x, y, color=ORANGE, lw=2.2)
    ax.fill_between(x, 0.8, y, color=LORANGE, alpha=0.6)
    c(ax, 3.45, 2.98, "模糊函数 χ(τ) 三角峰落在两门之间", color=ORANGE, fs=8.5)
    ax.add_patch(Rectangle((3.0, 0.8), 0.45, 2.0, fc="none", ec=BLUE, lw=1.6, ls="--"))
    ax.annotate(r"$\epsilon$ 残差", xy=(3.225, 1.5), xytext=(5.3, 1.7),
                fontproperties=FONT, fontsize=9, color=BLUE,
                arrowprops=dict(arrowstyle="->", color=BLUE))
    # 分摊比例放在门顶部之上 (标题 ~3.9, 内容上限 3.5)
    m(ax, 2.55, 3.45, r"$1-\epsilon/T_p$", color=BLUE, fs=10)
    m(ax, 3.9, 3.45, r"$\epsilon/T_p$", color=BLUE, fs=10)
    c(ax, 3.45, 0.10, "能量按残差 ε 在两相邻门间分摊 (和=1)", color=GRAY, fs=8.5)
    fig.savefig(os.path.join(OUT, "fig02_concept_leakage.png"), bbox_inches="tight")
    plt.close(fig)

# ---------- 图3 ----------
def fig3():
    fig, ax = newfig(6.8, 3.6, "图3  假设检验数据窗口")
    labels = ["l-1", "l", "l+1"]
    for i, gx in enumerate([2.6, 3.5, 4.4]):
        col = ORANGE if i == 1 else LBLUE
        ax.add_patch(Rectangle((gx-0.35, 1.4), 0.7, 1.0, fc=col, ec=BLUE, lw=1.3))
        c(ax, gx, 1.25, "门%s"%labels[i], color=DARK)
    ax.add_patch(Rectangle((2.25, 1.25), 3.0, 1.3, fc="none", ec=ORANGE, lw=1.6, ls="--"))
    c(ax, 3.75, 2.75, "主数据窗口 [z_{l-1}, z_l, z_{l+1}]  (CUT = l)", color=ORANGE, fs=9)
    for i, gx in enumerate([0.5, 1.1, 1.7, 5.3, 5.9, 6.5]):
        ax.add_patch(Rectangle((gx-0.25, 1.4), 0.5, 1.0, fc="#F0F0F0", ec=GRAY, lw=1.0))
    c(ax, 1.1, 1.25, "辅助 r1", color=GRAY, fs=7.5)
    c(ax, 6.5, 1.25, "rK", color=GRAY, fs=7.5)
    c(ax, 3.75, 0.55, "辅助数据 K 门: 仅噪声 → 估计协方差 R", color=GRAY, fs=9)
    box(ax, 0.4, 0.05, 2.7, 0.40, "H0: 三门均噪声 (均值=0)", fc=LBLUE, ec=BLUE, fs=8.5)
    box(ax, 3.7, 0.05, 2.9, 0.40, "H1: 两相邻门含信号 (漏左/漏右)", fc=LORANGE, ec=ORANGE, fs=8.5)
    fig.savefig(os.path.join(OUT, "fig03_concept_hypothesis.png"), bbox_inches="tight")
    plt.close(fig)

# ---------- 图4 ----------
def fig4():
    fig, ax = newfig(6.8, 3.8, "图4  同构 GLRT (Modified Kelly) 推导路线")
    box(ax, 0.3, 2.5, 1.5, 0.7, "主数据 z\n+ 辅助 r", fc=LBLUE, ec=BLUE, fs=9)
    box(ax, 2.2, 2.5, 1.7, 0.7, "对 R 最大化\nR_hat=Σ残/(K+3)", fc="#F4F6F8", ec=GRAY, fs=8.5)
    box(ax, 4.3, 2.5, 1.8, 0.7, "行列式之比\n|S_total|/|S_res|", fc=LORANGE, ec=ORANGE, fs=9)
    box(ax, 0.3, 1.3, 1.5, 0.7, "Lemma 1\nα_hat 闭式", fc=LBLUE, ec=BLUE, fs=9)
    box(ax, 4.3, 1.3, 1.8, 0.7, "K_{-1}, K_1", fc=LORANGE, ec=ORANGE, fs=9)
    box(ax, 2.2, 0.3, 2.0, 0.7, "max_ε max(K_{-1},K_1)\n> η → 有目标", fc=LGREEN, ec=GREEN, fs=8)
    arr(ax, 1.8, 2.85, 2.2, 2.85)
    arr(ax, 3.9, 2.85, 4.3, 2.85)
    arr(ax, 5.2, 2.5, 5.2, 2.0)
    arr(ax, 4.3, 1.65, 3.5, 1.65, ec=GRAY)
    arr(ax, 1.8, 1.65, 2.5, 0.65, ec=GRAY)
    arr(ax, 4.3, 1.65, 3.6, 0.65, ec=GRAY)
    c(ax, 6.5, 2.0, "ε=0 退化为\n经典 Kelly", color=GRAY, fs=8)
    fig.savefig(os.path.join(OUT, "fig04_concept_glrt.png"), bbox_inches="tight")
    plt.close(fig)

# ---------- 图4b ----------
def fig4b():
    fig, ax = newfig(6.8, 3.4, "图4b  矩阵行列式引理")
    m(ax, 0.4, 2.8, r"$|A+u v^\dagger| = |A|\,(1+v^\dagger A^{-1}u)$", fs=12, ha="left")
    c(ax, 0.4, 2.3, "右侧括号内为一个标量增益", ha="left", color=GRAY, fs=9)
    box(ax, 0.4, 0.6, 1.6, 1.1, "A\n(不含目标\n散布矩阵)", fc=LBLUE, ec=BLUE, fs=8.5)
    box(ax, 2.4, 0.6, 1.6, 1.1, "秩1更新\n含 α 项", fc=LORANGE, ec=ORANGE, fs=8.5)
    box(ax, 4.4, 0.6, 2.0, 1.1, "|A| 约掉\n只剩标量增益\n之比", fc="#F4F6F8", ec=GRAY, fs=8.5)
    # 公式 mtext 独立放在第二个 box 上方
    m(ax, 3.2, 1.9, r"$+u v^\dagger$", fs=12)
    arr(ax, 2.0, 1.15, 2.4, 1.15)
    arr(ax, 4.0, 1.15, 4.4, 1.15)
    fig.savefig(os.path.join(OUT, "fig04b_concept_det_lemma.png"), bbox_inches="tight")
    plt.close(fig)

# ---------- 图4c ----------
def fig4c():
    fig, ax = newfig(6.8, 3.6, "图4c  Lemma 1 闭式: 泄漏加权最小二乘")
    box(ax, 0.4, 1.9, 1.5, 0.9, "门 l\n$z_l - \\alpha c_l v$", fc=LBLUE, ec=BLUE, fs=8.5)
    box(ax, 0.4, 0.7, 1.5, 0.9, "门 l+1\n$z_{l+1} - \\alpha c_{l+1} v$", fc=LORANGE, ec=ORANGE, fs=8.5)
    c(ax, 2.3, 2.35, "权重", color=GRAY, fs=8.5)
    m(ax, 2.3, 1.9, r"$c_l$", color=BLUE, fs=12)
    m(ax, 2.3, 1.15, r"$c_{l+1}$", color=ORANGE, fs=12)
    arr(ax, 1.9, 2.35, 2.1, 2.35, ec=BLUE)
    arr(ax, 1.9, 1.15, 2.1, 1.15, ec=ORANGE)
    m(ax, 4.6, 1.95, r"$\hat\alpha = \dfrac{c_l(v^\dagger S^{-1}z_l)+c_{l+1}(v^\dagger S^{-1}z_{l+1})}{(c_l^2+c_{l+1}^2)(v^\dagger S^{-1}v)}$",
      fs=9.5, ha="center")
    arr(ax, 2.6, 1.9, 3.3, 2.05, ec=GRAY)
    arr(ax, 2.6, 1.15, 3.3, 1.75, ec=GRAY)
    c(ax, 5.9, 0.9, "ε=0 时 c_l=1, c_{l+1}=0\n→ 经典 AMF 的 α_hat", color=DARK, fs=8.5)
    fig.savefig(os.path.join(OUT, "fig04c_concept_lemma1.png"), bbox_inches="tight")
    plt.close(fig)

# ---------- 图5 ----------
def fig5():
    fig, ax = newfig(6.8, 3.4, "图5  Modified AMF 推导路线 (Ad Hoc)")
    box(ax, 0.3, 2.0, 1.6, 0.8, "R 已知\n对 α 求极大", fc=LBLUE, ec=BLUE, fs=9)
    box(ax, 2.3, 2.0, 1.9, 0.8, "$MF=|B|^2/A$\n(含跨门耦合项)", fc=LORANGE, ec=ORANGE, fs=9)
    box(ax, 4.6, 2.0, 1.9, 0.8, "R → R_hat\n(样本协方差)", fc="#F4F6F8", ec=GRAY, fs=9)
    box(ax, 2.3, 0.5, 2.4, 0.8, "Modified AMF\n(无行列式/无Wishart)", fc=LGREEN, ec=GREEN, fs=8.5)
    arr(ax, 1.9, 2.4, 2.3, 2.4)
    arr(ax, 4.2, 2.4, 4.6, 2.4)
    arr(ax, 3.7, 2.0, 3.5, 1.3, ec=GRAY)
    c(ax, 6.6, 1.4, "便宜、工程常用\n仍 CFAR", color=GRAY, fs=8)
    fig.savefig(os.path.join(OUT, "fig05_concept_amf.png"), bbox_inches="tight")
    plt.close(fig)

# ---------- 图6 ----------
def fig6():
    fig, ax = newfig(6.8, 3.8, "图6  Modified ACE 路线 (部分同构)")
    box(ax, 0.3, 2.6, 1.7, 0.8, "MF(ε)\n+ 未知尺度 γ", fc=LBLUE, ec=BLUE, fs=9)
    box(ax, 2.4, 2.6, 2.0, 0.8, "÷ E_总\n(主数据总能量)", fc=LORANGE, ec=ORANGE, fs=9)
    box(ax, 4.7, 2.6, 1.8, 0.8, "NMF(ε)\nγ 被约掉", fc="#F4F6F8", ec=GRAY, fs=9)
    box(ax, 4.7, 1.2, 1.9, 0.8, "R → R_hat\n→ Modified ACE", fc=LGREEN, ec=GREEN, fs=8.5)
    box(ax, 0.3, 1.2, 1.9, 0.8, "γ≠1 时仍 CFAR\n(归一化消尺度)", fc=LBLUE, ec=BLUE, fs=8.5)
    arr(ax, 2.0, 3.0, 2.4, 3.0)
    arr(ax, 4.4, 3.0, 4.7, 3.0)
    arr(ax, 5.6, 2.6, 5.6, 2.0, ec=GRAY)
    arr(ax, 4.7, 1.2, 3.1, 1.2, ec=GRAY)
    fig.savefig(os.path.join(OUT, "fig06_concept_ace.png"), bbox_inches="tight")
    plt.close(fig)

# ---------- 图7 ----------
def fig7():
    fig, ax = newfig(6.8, 3.6, "图7  CFAR 白化变换示意")
    box(ax, 0.3, 1.8, 1.5, 0.9, "z ~ CN(0,R)", fc=LBLUE, ec=BLUE, fs=9)
    box(ax, 2.3, 1.8, 1.8, 0.9, "× R^{-1/2}\nz_w ~ CN(0,I)", fc="#F4F6F8", ec=GRAY, fs=9)
    box(ax, 4.5, 1.8, 1.7, 0.9, "酉旋 U\nz_tilde ~ CN(0,I)", fc=LORANGE, ec=ORANGE, fs=9)
    box(ax, 2.3, 0.5, 2.6, 0.7, "统计量只含 z_tilde → 与 R (及 γ) 无关 → CFAR", fc=LGREEN, ec=GREEN, fs=8)
    arr(ax, 1.8, 2.25, 2.3, 2.25)
    arr(ax, 4.1, 2.25, 4.5, 2.25)
    arr(ax, 5.3, 1.8, 5.3, 1.2, ec=GRAY)
    arr(ax, 4.5, 1.2, 3.6, 1.0, ec=GREEN)
    c(ax, 6.7, 2.25, "把 R 拧成\n单位阵", color=GRAY, fs=8)
    fig.savefig(os.path.join(OUT, "fig07_concept_cfar.png"), bbox_inches="tight")
    plt.close(fig)

for f in (fig1, fig2, fig3, fig4, fig4b, fig4c, fig5, fig6, fig7):
    f()
    print("ok", f.__name__)
print("ALL DONE ->", os.path.abspath(OUT))