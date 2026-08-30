# DTNet (HSE) — RML2016.10b PyTorch 复现

DTNet（原论文记作 HSE，Hierarchical Scale-feature Extraction）调制识别模型的
PyTorch 实现，在 RML2016.10b 数据集上复现。网络结构逐行提取自原版 Notebook
（RML2016b_DTNet.ipynb, cell-8），仅做工程化清理（路径相对化、参数化、AMP/DataLoader
加速），不改变模型结构与数学定义。

## 模型结构

| 模块 | 功能点 |
|------|--------|
| 双流嵌入（Dual-stream Embedding） | 用两种卷积核（16×2 与 32×32）分别提取局部与全局尺度特征，拼接为 token 序列 |
| SFE（Scale-Feature-Extension） | 残差 + 通道注意力（Scale/Extention）做多尺度特征扩展，输出 128 通道特征图 |
| Transformer 编码器 | 4 层自注意力（4 头，hidden=40）建模 token 间长程依赖，取 `[CLS]` 位输出 |
| split-MLP | 将 hidden 沿通道对半拆分、分别过两个支路再拼接，作为轻量化分类头前置 |

输入：$x \in \mathbb{R}^{2\times128}$（实部/虚部两通道，128 个采样点）。
输出：10 类调制的 softmax 对数。

## 复现结果（RML2016.10b，10 类，未归一化 I/Q，70/15/15 划分）

| 指标（test 集） | 数值 |
|----------------|------|
| 整体精度（micro） | 62.76% |
| per-SNR 宏平均 | 62.87% |
| 最优单 SNR 精度 | 92.90% @ +12 dB |

与论文报告 94.4% 的差距来自数据口径（本文 10 类 / 未归一化 / 70-15-15，
论文为 11 类 / 归一化 / 不同验证划分），并非实现错误。

## 用法

```bash
pip install -r requirements.txt

# 训练（默认 20 epoch / batch 2048 / lr 4e-3）
python train.py dataset2016b.h5

# 测试集 per-SNR 评估，结果存 per_snr_test_pytorch.npz
python eval.py dataset2016b.h5 test

# 可视化（需先完成训练得到 dtnet_best_pytorch.pt）
python plot_train_curve.py   # fig_train_curve.png 训练曲线
python fig_snr.py            # fig_snr.png per-SNR 准确率
python fig_signal.py         # fig_waveform.png 时域波形 + fig_confusion.png 混淆矩阵
```

数据集 `dataset2016b.h5` 需自行从 RML2016.10b 官方来源获取，放在仓库根目录
（已被 .gitignore 忽略，不纳入版本控制）。HDF5 内字段约定：
`X_train/X_val/X_test` 形状 `[N,1,128,2]`，`Y_*` 为 `[N,10]` one-hot，
`Z_*` 为 `[N]` 的 SNR 标签。

## 环境

- Python 3.13 + PyTorch 2.13（CUDA 12.6）
- 20 epoch / batch 2048 / AMP 混合精度，RTX 4060 上约 14 分钟
- CPU 亦可运行（自动回退，速度显著下降）
