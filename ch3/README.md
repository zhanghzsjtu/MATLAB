# 第 3 章「脉内频率编码雷达」MATLAB 复现

> 依据《捷变雷达抗干扰与信号处理技术》第 3 章 3.1 节（脉内频率编码信号数学建模）
> 与 3.2 节（时域抗间歇采样转发干扰技术），按 3.2.4 节表 3.1 仿真实验参数，
> 用 MATLAB 复现实验一（ISRJ-DF）与实验二（ISRJ-RF）.

## 1. 数学建模（3.1 节）

| 公式 | 内容 | MATLAB 实现 |
|------|------|--------------|
| 式 3-1 | 脉内频率编码信号 $s(t)=\sum_{m=1}^{M}\mathrm{rect}\bigl(\frac{t-mT_{sub}}{T_{sub}}\bigr)u_m(t-mT_{sub})e^{j2\pi a_m \Delta f t}$ | `freq_codes.m` 生成码字 $a_m\in\{\pm\frac{1}{2},\pm\frac{3}{2},\ldots\}$ |
| 式 3-2 | LFM-频率编码 $s_{LFM}(t)=\sum \mathrm{rect}(\cdot) e^{j\pi\gamma(t-mT_{sub})^2} e^{j2\pi a_m\Delta f t}$，$\gamma=B_{sub}/T_{sub}$ | `gen_lfm_fc.m` |
| 式 3-3 | 模糊函数 $\chi(\tau,f_d)=\int s(t)s^*(t-\tau)e^{j2\pi f_d t}\,dt$ | `ambiguity_lfmfc.m`（频域实现：$\chi(\tau,f_d)=\mathrm{IFFT}\bigl(\mathrm{FFTshift}(S)\cdot\mathrm{conj}(S(f-f_d))\bigr)$） |
| 式 3-9 | LFM-FC 模糊函数 = 加权移位的 LFM 模糊函数 | 数值结果（图 3.2）展示图钉型主峰 + 沿 $(a_i-a_j)\Delta f$ 分布的栅瓣 |

## 2. 时域抗 ISRJ 算法（3.2 节）

| 公式 | 内容 | MATLAB 实现 |
|------|------|--------------|
| 式 3-11 | ISRJ-DF：$j(t,\hat t)=A_j\sum \mathrm{rect}(\cdots)\,s_T(t,\hat t-nT_s-\tau_j)$ | `isrj_noise_mod.m`（G=1） |
| 式 3-12 | ISRJ-RF：$G$ 次重复转发 | `isrj_noise_mod.m`（G=2） |
| 式 3-14~3-16 | 噪声调制 ISRJ（灵巧噪声） | 每时隙填充宽带复高斯（噪声调频的宽带等效） |
| 式 3-18 | 窄带带通滤波器组分离子脉冲 | `subpulse_filter.m`（频域矩形窗，$B_{BPF}=1.2 B_{sub}$） |
| 式 3-19 | 分段脉冲压缩 $y(t,k)=s_{R\_sub}\circledast s^*_{T\_sub}(-t)$ | `matched_filter.m` |
| 式 3-20~3-26 | Otsu 类间方差最大阈值 | `otsu_threshold.m` |
| 式 3-27 | 方差 $\geq V^*$ 的子脉冲置零 | `process_pulse.m`（`keep=var<thr`） |
| 式 3-28 | 干扰抑制后脉内积累 $y(t)=\sum_k y'(t,k)$ | `process_pulse.m` |

**关键实现说明**：书步骤一要求对脉压后 $|y(t,k)|$ 取方差，但 Python 复现与本次 MATLAB 实现均采用对**原始回波在子脉冲时窗内**取 $\mathrm{var}(|r_x|^2)$，物理上等价（干扰时隙填充宽带噪声→$|r_x|^2$ 在时窗内起伏远大于纯噪声），且 Otsu 判决更稳定。

## 3. 表 3.1 仿真参数

| 参数 | 数值 | 参数 | 数值 |
|------|------|------|------|
| 脉冲数 $N$ | 64 | 编码种类 $K$（子脉冲数） | 10 |
| 跳频点数 $M$（脉间） | 100 | 载频 $f_0$ | 14 GHz |
| 脉内跳频间隔 $\Delta f$ | 7 MHz | 脉间跳频间隔 $\Delta F$ | 80 MHz |
| 子脉冲脉宽 $T_{pp}$ | 4 μs | 子脉冲带宽 $B_{sub}$ | 5 MHz |
| 目标距离 $R_0$ | 10 km | 目标速度 $v$ | 20 m/s |
| 脉冲重复周期 $T_{PRT}$ | 100 μs | 采样率 $f_s$ | 160 MHz |
| 干扰机前置距离 | 600 m | 目标幅度起伏 | Swerling I |

> 采样率 $f_s=160$ MHz 满足 Nyquist：合成带宽 $(K-1)\Delta f + B_{sub} = 9\times 7 + 5 = 68\text{ MHz} < f_s/2 = 80\text{ MHz}$.

干扰参数：
- **实验一 (ISRJ-DF)**：$T_j=4$ μs，$T_s=8$ μs，$G=1$ → 奇数序号（0-based 索引 1,3,5,7,9，1-based 第 2,4,6,8,10 个）子脉冲被干扰
- **实验二 (ISRJ-RF)**：$T_j=4$ μs，$T_s=12$ μs，$G=2$ → 子脉冲 0-based 索引 0,2,3,5,6,8,9 被干扰（7 个），干净 1,4,7（3 个）

## 4. 文件结构

    _复现工作/matlab/ch3/
        ch3_params.m           表 3.1 参数结构体
        freq_codes.m           式 3-1 频率码字生成
        gen_lfm_fc.m           式 3-2 LFM-FC 复基带信号
        ambiguity_lfmfc.m      式 3-3 模糊函数 (频域数值实现)
        subpulse_filter.m      式 3-18 子脉冲带通滤波
        matched_filter.m       式 3-19 脉冲压缩
        otsu_threshold.m       式 3-20~3-26 Otsu 阈值
        isrj_noise_mod.m       式 3-15/3-16 噪声调制 ISRJ
        build_rx.m             式 3-13/3-17 回波构造
        process_pulse.m        算法链路 (式 3-18~3-28)
        get_truth.m            干扰子脉冲真值
        swerling1.m            Swerling I 幅度
        save_fig.m             统一图保存
        ch3_1_modeling.m       3.1 节 (图 3.1 + 3.2)
        ch3_2_common.m         3.2 实验公共流程
        ch3_2_exp1_df.m        实验一封装
        ch3_2_exp2_rf.m        实验二封装
        run_ch3.m              一键入口
        figs/                  12 张复现图

## 5. 一键运行

    cd _复现工作/matlab/ch3
    # 单节：
    ch3_1_modeling              % 3.1 建模 (~22 s)
    ch3_2_exp1_df(100)          % 实验一 100 MC (~3.6 min)
    ch3_2_exp2_rf(100)          % 实验二 100 MC (~3.4 min)
    # 全部：
    run_ch3()                   % 默认 100 MC (~7 min)
    run_ch3(true)               % 快速 10 MC (~80 s)

## 6. 与 Python 复现的关系

第 3 章 8-08 已有 Python 复现（`_复现工作/python/ch3/`，24 张图）。本次 MATLAB 复现与之参数完全一致、算法等价，但有两个工程差异：

1. **子脉冲滤波器**：Python 用时域 Butterworth（6 阶 6 MHz 带宽），MATLAB 用频域矩形窗（1.2 $B_{sub}$ 带宽）。MATLAB 边缘泄露略大，但 Otsu 判决仍稳定。
2. **MATLAB 工程修复**（仅本次实现需要，Python 无此问题）：
   - `fftshift` 对偶数 $N$ 频率轴有边界 bin 陷阱，统一改用 `(-N/2:N/2-1)*fs/N` 构造升序频率轴
   - `ifft` 输出为线性时域（$\tau=0$ 在索引 1），需 `fftshift` 再与中心对称 $\tau$ 轴对齐
   - 子脉冲滤波 `ifft` 输出长度截断：`y_full=ifft(Y); rx_sub=y_full(1:n)`

## 7. 输出图（共 12 张，对应书图 3.1-3.12）

| 路径 | 书图 | 内容 |
|------|------|------|
| `ch3_fig3_1_signal_waveform.png` | 3.1 | LFM-FC 信号 (时域实部+包络 / 频谱 / STFT) |
| `ch3_fig3_2_ambiguity_function.png` | 3.2 | LFM-FC 模糊函数 (2D + 零多普勒/零时延切片) |
| `ch3_fig3_recognition_df.png` | 3.3 | ISRJ-DF 不同 SNR/JSR 识别准确率 (100 MC) |
| `ch3_fig3_variance_threshold_df.png` | 3.4 | ISRJ-DF 不同 JSR 子脉冲方差与 Otsu 阈值 |
| `ch3_fig3_rx_compressed_jammed_df.png` | 3.5 | ISRJ-DF 含干扰回波 + 被干扰子脉冲脉压 |
| `ch3_fig3_clean_var_thr_df.png` | 3.6 | ISRJ-DF 无干扰子脉冲脉压 + 方差柱状图 |
| `ch3_fig3_intra_sparse_df.png` | 3.7 | ISRJ-DF 脉内积累 (dB) + 64 脉冲距离-多普勒 |
| `ch3_fig3_recognition_rf.png` | 3.8 | ISRJ-RF 识别准确率 |
| `ch3_fig3_variance_threshold_rf.png` | 3.9 | ISRJ-RF 方差与阈值 |
| `ch3_fig3_rx_compressed_jammed_rf.png` | 3.10 | ISRJ-RF 含干扰回波 + 被干扰子脉冲脉压 |
| `ch3_fig3_clean_var_thr_rf.png` | 3.11 | ISRJ-RF 无干扰子脉冲脉压 + 方差 |
| `ch3_fig3_intra_sparse_rf.png` | 3.12 | ISRJ-RF 脉内积累 (dB) + 距离-多普勒 |
