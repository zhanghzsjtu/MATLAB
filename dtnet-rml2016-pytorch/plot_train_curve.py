"""绘制 DTNet 训练过程曲线（中文标注，数据来自训练日志 train_pytorch_log.txt）。

该图完全由本脚本基于真实训练日志产生，非手绘。
"""
import re
import os
import numpy as np
import matplotlib
matplotlib.rcParams['font.sans-serif'] = ['Microsoft YaHei', 'SimHei', 'DejaVu Sans']
matplotlib.rcParams['axes.unicode_minus'] = False
import matplotlib.pyplot as plt

BASE = os.path.dirname(os.path.abspath(__file__))
LOG = os.path.join(BASE, 'train_pytorch_log.txt')
OUT = os.path.join(BASE, 'fig_train_curve.png')

epochs, losses, accs = [], [], []
with open(LOG, 'r', encoding='utf-8') as f:
    for line in f:
        m = re.search(r'Epoch\s+(\d+)\s*\|\s*train loss\s+([\d.]+)\s*\|\s*val acc\s+([\d.]+)', line)
        if m:
            epochs.append(int(m.group(1)))
            losses.append(float(m.group(2)))
            accs.append(float(m.group(3)))

epochs = np.array(epochs)
losses = np.array(losses)
accs = np.array(accs)

fig, ax1 = plt.subplots(figsize=(7.2, 4.2), dpi=130)
color_l = '#0072BD'
ax1.plot(epochs, losses, '-o', color=color_l, markersize=4, linewidth=1.8, label='训练损失')
ax1.set_xlabel('训练轮次 Epoch')
ax1.set_ylabel('训练损失', color=color_l)
ax1.tick_params(axis='y', labelcolor=color_l)
ax1.set_xticks(epochs)

ax2 = ax1.twinx()
color_a = '#D95319'
ax2.plot(epochs, accs * 100, '-s', color=color_a, markersize=4, linewidth=1.8, label='验证准确率')
ax2.set_ylabel('验证准确率 (%)', color=color_a)
ax2.tick_params(axis='y', labelcolor=color_a)
ax2.set_ylim(0, 100)

# 合并图例
lines1, labels1 = ax1.get_legend_handles_labels()
lines2, labels2 = ax2.get_legend_handles_labels()
ax1.legend(lines1 + lines2, labels1 + labels2, loc='center right', fontsize=9, framealpha=0.9)

plt.title('DTNet 训练过程：损失下降与验证准确率上升', fontsize=12)
ax1.grid(True, linestyle='--', alpha=0.4)
fig.tight_layout()
fig.savefig(OUT)
print('saved', OUT, '| epochs', len(epochs), '| best val acc', f'{accs.max()*100:.2f}%')
