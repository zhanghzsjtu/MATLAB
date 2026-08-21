# -*- coding: utf-8 -*-
"""
eval.py — per-SNR evaluation of the trained PyTorch model on a given split.

Metric convention (matches the MATLAB evalPerSnr.m reference):
  overall micro accuracy, per-SNR macro average, best single-SNR accuracy.

Usage:
  python eval.py [data.h5] [split]

Default data path and checkpoint are resolved relative to this script.
Results are saved to per_snr_<split>_pytorch.npz next to this script.
"""
import sys
import os
import numpy as np
import h5py
import torch

_HERE = os.path.dirname(os.path.abspath(__file__))
DATA_FILE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(_HERE, "dataset2016b.h5")
SPLIT = sys.argv[2] if len(sys.argv) > 2 else "test"
CKPT = os.path.join(_HERE, "dtnet_best_pytorch.pt")
CHUNK = 8192

sys.path.insert(0, _HERE)
from train import HSE, load_h5  # noqa: E402

device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
net = HSE(num_classes=10).to(device)
net.load_state_dict(torch.load(CKPT, weights_only=True, map_location=device))
net.eval()

X, Y = load_h5(DATA_FILE, SPLIT)
with h5py.File(DATA_FILE, 'r') as f:
    Z = f[f'Z_{SPLIT}'][:].ravel()
Yl = Y.argmax(1)

preds = []
with torch.no_grad(), torch.amp.autocast('cuda', enabled=torch.cuda.is_available()):
    for i in range(0, len(X), CHUNK):
        xb = torch.as_tensor(X[i:i + CHUNK], device=device)
        preds.append(net(xb).argmax(1).cpu().numpy())
preds = np.concatenate(preds)

overall = float((preds == Yl).mean())
print(f'=== {SPLIT.upper()} set ===')
print(f'Overall accuracy (micro): {overall:.4f}')

snrs = np.sort(np.unique(Z))
per_snr = []
for s in snrs:
    m = Z == s
    acc = float((preds[m] == Yl[m]).mean())
    per_snr.append(acc)
    print(f'SNR {s:+3d} dB | acc {acc:.4f} | n={m.sum()}')
per_snr = np.array(per_snr)
macro = per_snr.mean()
bi = int(per_snr.argmax())
print(f'Per-SNR macro average : {macro:.4f}')
print(f'Best single-SNR acc   : {per_snr[bi]:.4f} @ {snrs[bi]:+d} dB')

out = os.path.join(_HERE, f'per_snr_{SPLIT}_pytorch.npz')
np.savez(out, split=SPLIT, overall=overall, macro=macro,
         bestAcc=float(per_snr[bi]), bestSnr=int(snrs[bi]),
         snrs=snrs.astype('int16'), perSnr=per_snr)
print(f'saved {out}')
