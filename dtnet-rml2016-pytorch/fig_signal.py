# -*- coding: utf-8 -*-
"""fig_signal.py — 生成两类科普图（中文标注，由真实数据产生）：

  1) fig_constellation.png : 10 类调制各自在高 SNR 下的 I/Q 星座图（每类一个样本）
  2) fig_confusion.png     : test 集整体混淆矩阵（10x10）

数据来源：
  - dataset2016b.h5          : RML2016.10b 原始 I/Q 样本（X_*/Y_*/Z_*）
  - dtnet_best_pytorch.pt   : 训练得到的最佳权重
两图均由本脚本基于真实数据/真实预测生成，非手绘。
"""
import os
import sys
import numpy as np
import h5py
import torch
import matplotlib
matplotlib.use('Agg')
matplotlib.rcParams['font.sans-serif'] = ['Microsoft YaHei', 'SimHei', 'Arial Unicode MS']
matplotlib.rcParams['axes.unicode_minus'] = False
import matplotlib.pyplot as plt

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
from train import HSE, load_h5  # noqa: E402

DATA_FILE = os.path.join(_HERE, 'dataset2016b.h5')
CKPT = os.path.join(_HERE, 'dtnet_best_pytorch.pt')
SPLIT = 'test'

CLASSES = ['BPSK', 'QPSK', '8PSK', 'QAM16', 'QAM64',
           'PAM4', 'WBFM', 'CPFSK', 'GFSK', 'AM-DSB']
NC = len(CLASSES)

device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
net = HSE(num_classes=NC).to(device)
net.load_state_dict(torch.load(CKPT, weights_only=True, map_location=device))
net.eval()

# ---- 读数据 ----
X, Y = load_h5(DATA_FILE, SPLIT)          # X:[N,1,128,2]  Y:[N,10]
with h5py.File(DATA_FILE, 'r') as f:
    Z = f[f'Z_{SPLIT}'][:].ravel()        # SNR 标签
Yl = Y.argmax(1)

# ---- 预测（test 集）----
preds = []
with torch.no_grad(), torch.amp.autocast('cuda', enabled=torch.cuda.is_available()):
    for i in range(0, len(X), 8192):
        xb = torch.as_tensor(X[i:i + 8192], device=device)
        preds.append(net(xb).argmax(1).cpu().numpy())
preds = np.concatenate(preds)

# ============================ 图1：时域 I/Q 波形 ============================
# 每类挑一个高 SNR 样本（取该类信噪比最高的样本）
fig1, axes = plt.subplots(2, 5, figsize=(15, 5.8), dpi=150)
for c in range(NC):
    ax = axes[c // 5, c % 5]
    idx_c = np.where(Yl == c)[0]
    zc = Z[idx_c]
    pick = idx_c[int(np.argmax(zc))]
    I = X[pick, 0, :, 0]
    Q = X[pick, 0, :, 1]
    t = np.arange(128)
    ax.plot(t, I, color='#0072BD', lw=1.0, label='I 路')
    ax.plot(t, Q, color='#D95319', lw=1.0, alpha=0.75, label='Q 路')
    ax.set_title(f'{CLASSES[c]}  (SNR {Z[pick]:+d} dB)', fontsize=10)
    ax.set_xlabel('采样点', fontsize=8)
    ax.set_ylabel('幅度', fontsize=8)
    ax.tick_params(labelsize=7)
    ax.grid(alpha=0.25)
    if c == 0:
        ax.legend(fontsize=7, loc='upper right')
fig1.suptitle('各类调制的时域 I/Q 波形（每类一个高 SNR 样本）', fontsize=12)
fig1.tight_layout(rect=[0, 0, 1, 0.95])
p1 = os.path.join(_HERE, 'fig_waveform.png')
fig1.savefig(p1, dpi=150)
plt.close(fig1)
print('fig_waveform.png 已保存 ->', p1)

# ============================ 图2：混淆矩阵 ============================
cm = np.zeros((NC, NC), dtype=int)
for t, p in zip(Yl, preds):
    cm[t, p] += 1
cm_norm = cm / cm.sum(1, keepdims=True) * 100  # 每行归一化为百分比

fig2, ax = plt.subplots(figsize=(8.2, 7), dpi=150)
im = ax.imshow(cm_norm, cmap='Blues', vmin=0, vmax=100)
ax.set_xticks(range(NC)); ax.set_yticks(range(NC))
ax.set_xticklabels(CLASSES, rotation=45, ha='right', fontsize=8)
ax.set_yticklabels(CLASSES, fontsize=8)
ax.set_xlabel('预测类别', fontsize=10)
ax.set_ylabel('真实类别', fontsize=10)
ax.set_title('test 集混淆矩阵（行归一化，单位 %）', fontsize=11)
# 标注数值（只标较高的，避免拥挤）
for i in range(NC):
    for j in range(NC):
        v = cm_norm[i, j]
        if v >= 10:
            ax.text(j, i, f'{v:.0f}', ha='center', va='center',
                    color='white' if v > 55 else 'black', fontsize=7.5)
fig2.colorbar(im, ax=ax, fraction=0.046, pad=0.04, label='百分比 %')
fig2.tight_layout()
p2 = os.path.join(_HERE, 'fig_confusion.png')
fig2.savefig(p2, dpi=150)
plt.close(fig2)
print('fig_confusion.png 已保存 ->', p2)

# 保存混淆矩阵数值（供博客引用）
np.savez(os.path.join(_HERE, 'confusion_test_pytorch.npz'),
         classes=CLASSES, cm=cm, cm_norm=cm_norm)
print('saved confusion_test_pytorch.npz')
