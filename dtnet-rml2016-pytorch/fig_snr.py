# -*- coding: utf-8 -*-
"""fig_snr.py — 绘制 PyTorch 复现 per-SNR 识别准确率（中文标注）。

数据来源：
  - per_snr_test_pytorch.npz : eval.py 真实评估导出
本图仅做可视化，非手绘。
"""
import os
import numpy as np
import matplotlib
matplotlib.use('Agg')
matplotlib.rcParams['font.sans-serif'] = ['Microsoft YaHei', 'SimHei', 'Arial Unicode MS']
matplotlib.rcParams['axes.unicode_minus'] = False
import matplotlib.pyplot as plt

BASE = os.path.dirname(os.path.abspath(__file__))
PYTORCH_NPZ = os.path.join(BASE, 'per_snr_test_pytorch.npz')
OUT = os.path.join(BASE, 'fig_snr.png')

p = np.load(PYTORCH_NPZ)
snrs = p['snrs'].astype(float)
acc = p['perSnr'].astype(float)
overall = float(p['overall'])
macro = float(p['macro'])
best = float(p['bestAcc'])
best_snr = int(p['bestSnr'])

# ---- 画图 ----
fig, ax = plt.subplots(figsize=(9, 5.2), dpi=150)
ax.plot(snrs, acc * 100, '-o', color='#0072BD', lw=1.8, ms=4, label='PyTorch 复现 (20 轮)')
ax.set_xlabel('信噪比 SNR (dB)')
ax.set_ylabel('各信噪比下识别准确率 (%)')
ax.set_title('不同信噪比下识别准确率')
ax.grid(alpha=0.3)
ax.legend(fontsize=9)

txt = (f"整体 {overall*100:.2f}% | 宏平均 {macro*100:.2f}% | "
       f"最优 {best*100:.2f}% @ {best_snr:+d}dB")
ax.text(0.5, -0.16, txt, transform=ax.transAxes, ha='center', fontsize=10,
        bbox=dict(boxstyle='round', facecolor='#f0f3f8', edgecolor='#cccccc'))

fig.tight_layout()
fig.savefig(OUT, dpi=150, bbox_inches='tight')
plt.close(fig)
print('fig_snr.png 已保存 ->', OUT)
print(txt)
