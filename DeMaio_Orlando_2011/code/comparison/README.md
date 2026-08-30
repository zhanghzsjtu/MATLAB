# De Maio & Orlando 2011 TSP 复现 — 复审与对比报告

本目录包含对 `G_teams_Q1/01_意大利_DeMaio_Orlando_Aubry/code/` 下复现脚本的
**逐项复审报告**与**配套公式推导**。两份文档均按论文 Section II–IV 严格
整理。

## 文档

| 文件 | 内容 |
|---|---|
| `index.html` | 原始图 vs 复现图 6 张并排对比 + 公式一致性核对表 + 改进建议 |
| `formulas.html` | 论文式 (1)–(54) 完整整理与详细推导（GLRT、Modified Kelly/AMF/ACE、$\gamma$-CFAR） |
| `orig_Fig1.png` … `orig_Fig6.png` | 从论文 PDF 渲染并裁剪的原始 Fig.1–Fig.6 |
| `DeMaio2011_Fig*_*.png` | 复现脚本产出的 6 张图（含论文没有的 ROC 图，标 Fig.3_ROC.png） |

## 主要复审结论

1. **公式实现正确**：Modified Kelly / Modified AMF / Modified ACE 的两距离门泄漏
   模型与论文式 (25)–(46) 一致；协方差 $C_{i,j}=\rho^{(i-j)^2}$、导向矢量 $v=s\otimes a$、
   $\epsilon$ 网格 `linspace(-Tp/2, Tp/2, 2*Ne+1)`、SNR 定义式 (53)/(54) 均与论文严格一致。

2. **公共参数严格**：$N=16$、$K=32$、$P_{fa}=10^{-4}$、$\rho=0.995$、$T_p=0.2\,\mu s$、
   $c=3\times 10^8$、$\nu_s=0.3$、$f=0$、$\gamma=3$ dB 均与论文 Section IV 一致。

3. **图层面多处偏差**：
   - Fig.1 缺 Modified DT-GLRT（论文式 47），用 Cls.Kelly 替代；
   - Fig.2 缺 Modified GAMF（论文式 48）和 AMF；
   - Fig.3 复现画的是 ROC 图（论文无 ROC）；
   - Fig.4 / Fig.6 合并为单图、丢失 2 子图结构；
   - Fig.5 多画 Mod.Kelly/Mod.AMF，缺 Modified GASD（论文式 49）；
   - 缺 3 个 Modified 分布式目标检测器实现（`det_modified_dtglrt.m` /
     `det_modified_gamf.m` / `det_modified_gasd.m`）。

4. **MC 次数缩减**：脚本默认 $2\times 10^5 / 10^4 / 500$，论文 $10^6 / 10^5 / 500$。
   曲线趋势与论文一致，过渡区略抖动。

## 改进建议（详见 `index.html` 第 ⑩ 节）

1. 新增 3 个 Modified 分布式目标检测器（论文式 47/48/49）；
2. Fig.3 改为论文 Fig.3（$P_d$ vs SNR），删/重命名伪 ROC；
3. Fig.4 / Fig.6 恢复 2 子图结构并标理论下界 0.866 m / 0.433 m；
4. Fig.5 检测器集合改为 `{'mae','mgasd','c'}`；
5. 论文级精度调用 `DeMaio2011_reproduce_all(1e6, 1e5, 500)`。

---

*免责声明：所有内容基于 A. De Maio, D. Orlando, IEEE TSP 59(9), 2011, DOI 10.1109/TSP.2011.2159602。*
