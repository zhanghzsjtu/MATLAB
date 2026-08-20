%% main_decision_tree_exp.m  —  决策树特征提取与干扰识别仿真实验 v2
% 复现书170~176页：基于多域特征的决策树快速干扰识别
% 方法A: fitctree自动决策树; 方法B: 分层手动决策树(数据驱动阈值)
% 输出: fig5_5~fig5_11 + 混淆矩阵

%% ======================== 全局参数 ========================
Tp  = 20e-6;     B = 10e6;     fs = 20e6;
N_per_class = 1000;   Nclasses = 9;   snr_db = 0;

[t, S_lfm] = lfm_signal(Tp, B, fs, 0);
Npts = length(t);

%% ======================== 批量数据集生成 (纯九类干扰, 不含无干扰) ========================
fprintf('生成 %d 类 × %d 样本...\n', Nclasses, N_per_class);
X_data = zeros(N_per_class*Nclasses, Npts);
Y_label = zeros(N_per_class*Nclasses, 1);
rng(2024);  % 固定种子保证可复现

for cls = 1:Nclasses
    fprintf('  类别 %d/%d\n', cls, Nclasses);
    for n = 1:N_per_class
        idx = (cls-1)*N_per_class + n;
        X_data(idx,:) = real(generate_one_sample(t,S_lfm,Tp,B,fs,cls,snr_db))';
        Y_label(idx) = cls;
    end
end

%% ======================== 特征提取 ========================
fprintf('提取7维特征...\n');
N_total = size(X_data,1);

% F1: 能量 (公式5-19)
F_energy = sum(X_data.^2, 2);

% F2: 带宽 (-10dB)
F_bw = zeros(N_total,1);
for i=1:N_total
    xf=abs(fft(X_data(i,:))); xf=xf/max(xf); F_bw(i)=sum(xf>0.3)*fs/Npts/1e6;
end

% F3: 时域连续性系数 N1 (公式5-20)
F_n1 = zeros(N_total,1);
for i=1:N_total
    x=X_data(i,:); Tth=3*std(x(round(Npts*0.85:end))); F_n1(i)=sum(abs(x)<Tth)/Npts;
end

% F4: 采样窗均值 MW (公式5-21)
F_mw = zeros(N_total,1);
wl=round(Npts*0.15);
for i=1:N_total
    x=X_data(i,:);
    F_mw(i)=(mean(abs(x(1:wl)))+mean(abs(x(end-wl+1:end))))/2;
end

% F5: 时宽
F_tw = zeros(N_total,1);
for i=1:N_total
    x=X_data(i,:); env=abs(hilbert(x)); env=env/max(env);
    F_tw(i)=sum(env>0.1)/fs*1e6;
end

% F6: 频域矩偏度 skewness (公式5-22)
F_sk = zeros(N_total,1);
for i=1:N_total
    F_sk(i)=skewness(abs(fftshift(fft(X_data(i,:)))));
end

% F7: 局部矩偏度 N2 (公式5-23)
F_n2 = zeros(N_total,1);
nw=5; ws=floor(Npts/nw);
for i=1:N_total
    x=X_data(i,:); sks=zeros(nw,1);
    for w=1:nw
        seg=x((w-1)*ws+1:min(w*ws,Npts));
        sks(w)=skewness(abs(fftshift(fft(seg))));
    end
    F_n2(i)=mean(sks);
end

% 组装特征矩阵
Features = [F_energy, F_bw, F_n1, F_mw, F_tw, F_sk, F_n2];
feat_names = {'能量','带宽/MHz','连续性系数N1','采样窗均值MW', ...
               '时宽/us','频域矩偏度','局部矩偏度N2'};

fprintf('特征矩阵尺寸: %d × %d\n', size(Features,1), size(Features,2));

%% ======================== 方法A: fitctree 自动决策树 (九类干扰) ========================
fprintf('\n--- 方法A: fitctree (九类干扰) ---\n');

% 在纯九类干扰上训练决策树，让树自行学习阈值
cv = cvpartition(Y_label, 'HoldOut', 0.3);
X_tr = Features(training(cv), :); y_tr = Y_label(training(cv));
X_te = Features(test(cv), :);     y_te = Y_label(test(cv));
ctree_model = fitctree(X_tr, y_tr, ...
    'MinLeafSize', 30, 'MaxNumSplits', 60);
y_pred_A = predict(ctree_model, X_te);

acc_A = mean(y_pred_A == y_te) * 100;
conf_A = confusionmat(y_te, y_pred_A);
per_acc_A = diag(conf_A) ./ sum(conf_A, 2) * 100;

fprintf('fitctree 整体准确率(OA): %.1f%%\n', acc_A);
for c=1:Nclasses
    fprintf('  类别%d: %.1f%%\n', c, per_acc_A(c));
end

%% ======================== 特征重要性分析 ========================
fprintf('\n--- 特征重要性 (predictorImportance) ---\n');
imp = predictorImportance(ctree_model);
[imp_sorted, imp_order] = sort(imp, 'descend');
fprintf('特征重要性排序:\n');
for k=1:length(imp_sorted)
    fprintf('  %s: %.4f\n', feat_names{imp_order(k)}, imp_sorted(k));
end

%% ======================== 绘制结果图 ========================
%% ======================== 绘制结果图 ========================

% 图5.5: 九类能量分布对比
figure('Position',[50 50 800 450]);
bd=[]; gd=[];
for c=1:Nclasses, bd=[bd; F_energy(Y_label==c)]; gd=[gd; c*ones(sum(Y_label==c),1)]; end
boxplot(bd,gd); xlabel('干扰类别编号'); ylabel('能量');
title('图5.5  九类干扰信号的能量特征值'); grid on;
saveas(gcf,'figs/fig5_5_energy.png');

% 图5.6: 带宽
figure('Position',[50 50 900 480]);
bd=[]; gd=[];
for c=1:Nclasses, bd=[bd; F_bw(Y_label==c)]; gd=[gd; c*ones(sum(Y_label==c),1)]; end
boxplot(bd,gd); xlabel('干扰类别编号'); ylabel('带宽/MHz');
title('图5.6  九类不同干扰信号的带宽特征值'); grid on;
saveas(gcf,'figs/fig5_6_bandwidth.png');

% 图5.7: 连续性系数(类1~4)
figure('Position',[50 50 700 420]);
b7=[]; g7=[];
for c=[1 2 3 4], b7=[b7; F_n1(Y_label==c)]; g7=[g7; c*ones(sum(Y_label==c),1)]; end
boxplot(b7,g7); xlabel('干扰类别'); ylabel('时域连续性系数 N_1');
title('图5.7  第1~4类干扰的时域连续性系数');
xticks(1:4); xticklabels({'1.全脉冲转发','2.密集转发','3.ISRJ','4.部分脉冲密集'}); grid on;
saveas(gcf,'figs/fig5_7_continuity.png');

% 图5.8: MW(类2 vs 3)
figure('Position',[50 50 550 380]);
boxplot([F_mw(Y_label==2);F_mw(Y_label==3)], [ones(sum(Y_label==2),1);2*ones(sum(Y_label==3),1)]);
xlabel('干扰类别'); ylabel('采样窗均值 M_W');
title('图5.8  第2类与第3类干扰的特征M_W');
xticks([1 2]); xticklabels({'2.密集转发','3.ISRJ'}); grid on;
saveas(gcf,'figs/fig5_8_mw.png');

% 图5.9: 时宽(类5~9)
figure('Position',[50 50 700 420]);
b9=[]; g9=[];
for c=[5 6 7 8 9], b9=[b9; F_tw(Y_label==c)]; g9=[g9; c*ones(sum(Y_label==c),1)]; end
boxplot(b9,g9); xlabel('干扰类别'); ylabel('时宽/\mus');
title('图5.9  第5~9类干扰的信号时宽');
xticks(1:5); xticklabels({'5.灵巧噪声','6.噪声调频','7.宽带压制','8.扫频','9.梳状谱'}); grid on;
saveas(gcf,'figs/fig5_9_timewidth.png');

% 图5.10: 频域矩偏度(类7~9)
figure('Position',[50 55 550 380]);
boxplot([F_sk(Y_label==7);F_sk(Y_label==8);F_sk(Y_label==9)], ...
    [ones(sum(Y_label==7),1);2*ones(sum(Y_label==8),1);3*ones(sum(Y_label==9),1)]);
xlabel('干扰类别'); ylabel('频域矩偏度');
title('图5.10  第7~9类干扰的频域矩偏度');
xticks(1:3); xticklabels({'7.宽带压制','8.扫频','9.梳状谱'}); grid on;
saveas(gcf,'figs/fig5_10_skewness.png');

% 图5.11: 局部矩偏度(类7 vs 8)
figure('Position',[50 55 550 380]);
boxplot([F_n2(Y_label==7);F_n2(Y_label==8)], [ones(sum(Y_label==7),1);2*ones(sum(Y_label==8),1)]);
xlabel('干扰类别'); ylabel('局部矩偏度 N_2');
title('图5.11  第7类与第8类干扰的局部矩偏度');
xticks([1 2]); xticklabels({'7.宽带压制','8.扫频'}); grid on;
saveas(gcf,'figs/fig5_11_local_skewness.png');

% 混淆矩阵(fitctree结果)
figure('Position',[50 60 650 550]);
imagesc(conf_A); colormap(flipud(hot)); colorbar;
cls_names={'全脉冲转','密集转','ISRJ','部分密集','灵巧噪','噪声FM','宽带压','扫频','梳状谱'};
set(gca,'XTick',1:9,'XTickLabel',cls_names,'YTick',1:9,'YTickLabel',cls_names);
xlabel('预测类别'); ylabel('真实类别');
title(sprintf('fitctree混淆矩阵 (OA=%.1f%%)', acc_A));
for ii=1:size(conf_A,1), for jj=1:size(conf_A,2)
    text(jj,ii,sprintf('%d',conf_A(ii,jj)),'HorizontalAlignment','center','Color','w','FontSize',8);
end, end
saveas(gcf,'figs/fig_confusion_matrix.png');

% 决策树可视化（兼容 -nodisplay 批处理模式，不依赖树对象内部属性类型）
% 用 text + annotation 绘制决策规则摘要图
tree_fig = figure('Position',[80 60 1100 750], 'Color','w');
axis off; hold on;
% 方法：用 predict/fitctree 的文本输出作为数据源，绘制结构化摘要
title(sprintf('CART Decision Tree Structure (OA=%.1f%%)', acc_A), 'FontSize',14, 'FontWeight','bold');
% 标题下方画分隔线
annotation('line', [0.08 0.92], [0.88 0.88], 'LineWidth',1.5, 'Color',[0.2 0.4 0.7]);
% 左栏：树参数统计
text(0.05, 0.82, sprintf('Tree Parameters'), 'FontSize',12, 'FontWeight','bold', 'Color',[0.15 0.3 0.6]);
text(0.05, 0.76, sprintf('  Algorithm: CART (fitctree)'), 'FontSize',10);
text(0.05, 0.71, sprintf('  MinLeafSize: 30   MaxNumSplits: 60'), 'FontSize',10);
text(0.05, 0.66, sprintf('  Training: %d samples (70%%)', round(size(X_tr,1))), 'FontSize',10);
text(0.05, 0.61, sprintf('  Test:       %d samples (30%%)', size(X_te,1)), 'FontSize',10);
% 右栏：每类准确率
text(0.52, 0.82, sprintf('Per-Class Accuracy'), 'FontSize',12, 'FontWeight','bold', 'Color',[0.6 0.2 0.15]);
cls_names_short = {'1.RDJ','2.DFTJ','3.ISRJ','4.PDFT','5.SNJ','6.NFM','7.BBN','8.SW','9.CSJ'};
for c = 1:Nclasses
    bar_w = per_acc_A(c) / 100 * 0.35;  % 归一化条宽
    y_c = 0.76 - (c-1)*0.055;
    rectangle('Position',[0.52, y_c-0.015, bar_w, 0.03], ...
        'FaceColor',[0.2 0.55 0.85], 'EdgeColor','none');
    text(0.53, y_c, sprintf('%s  %.1f%%', cls_names_short{c}, per_acc_A(c)), ...
        'FontSize',9.5, 'VerticalAlignment','middle');
end
% 底部：特征重要性排序（文字版）
text(0.05, 0.32, sprintf('Feature Importance Ranking (predictorImportance)'), ...
    'FontSize',11.5, 'FontWeight','bold', 'Color',[0.2 0.4 0.2]);
for k = 1:length(imp_sorted)
    imp_bar = imp_sorted(k) / max(imp_sorted) * 0.45;  % 归一化
    y_imp = 0.25 - (k-1)*0.035;
    rectangle('Position',[0.20, y_imp-0.01, imp_bar, 0.022], ...
        'FaceColor',[0.85 0.5 0.15], 'EdgeColor','none');
    text(0.06, y_imp, sprintf('%d. %s  (%.4f)', k, feat_names{imp_order(k)}, imp_sorted(k)), ...
        'FontSize',9, 'VerticalAlignment','middle');
end
% 底部注释
text(0.05, 0.02, sprintf('Root split feature: %s (highest information gain)', feat_names{imp_order(1)}), ...
    'FontSize',9, 'Color',[0.4 0.4 0.4], 'FontAngle','italic');
hold off;
saveas(tree_fig,'figs/fig_decision_tree_view.png');

% 特征重要性柱状图
figure('Position',[80 60 800 420]);
barh(imp_sorted,'FaceColor',[0.2 0.5 0.8]);
set(gca,'YTick',1:length(imp_order),'YTickLabel',feat_names(imp_order),'YDir','reverse');
xlabel('重要性得分'); title('图5.12  七维特征的重要性排序');
grid on;
saveas(gcf,'figs/fig5_12_feature_importance.png');

fprintf('\n全部结果图已保存到 ./figs/\n');

%% ===================== 局部函数 =====================
function [t,S]=lfm_signal(Tp,B,fs,f0)
    if nargin<4, f0=0; end
    N=round(Tp*fs); t=(0:N-1)'/fs; k=B/Tp;
    S=(double(abs(t)<=Tp/2)).*exp(1j*(2*pi*f0*t+pi*k*t.^2));
end

function sig=generate_one_sample(t,S_lfm,Tp,B,fs,cls,snr_db)
    dt=t(2)-t(1);
    switch cls
        case 0, sig=awgn(0.5*S_lfm,snr_db,'measured');
        case 1, sig=awgn(interp1(t,S_lfm,t+(1+8*rand)*1e-6,'linear',0),snr_db,'measured');
        case 2, s=zeros(size(S_lfm)); for nn=1:randi([3 6]), s=s+0.8*interp1(t,S_lfm,t+(1+9*rand)*1e-6,'linear',0); end; sig=awgn(s,snr_db,'measured');
        case 3, Tsl=(0.8+1.2*rand)*1e-6; Tss=(1.5+3.5*rand)*1e-6; Kk=floor(Tp/Tss); s=zeros(size(S_lfm));
                for kk=1:Kk, pr=(abs((t-kk*Tss-Tsl/2)/Tsl)<=0.5); s=s+pr.*S_lfm; end; sig=awgn(s,snr_db,'measured');
        case 4, ps=round(length(t)*(0.2+0.3*rand)); pe=round(length(t)*(0.6+0.3*rand)); s=zeros(size(S_lfm));
                for nn=1:randi([2 5]), tr=rand()*5e-6; tmp=zeros(size(S_lfm)); is_=min(ps+round(tr*fs),length(t));
                    ie_=min(is_+round(0.6*length(t)),length(t)); if ie_>is_&&is_>0, tmp(is_:ie_)=S_lfm(1:ie_-is_+1)*0.7; end; s=s+tmp; end
                sig=awgn(s.*((t>=t(ps))&(t<=t(pe))),snr_db,'measured');
        case 5, Tsl=(0.8+1.2*rand)*1e-6; Tss=(1.5+3.5*rand)*1e-6; Kk=floor(Tp/Tss); sb=zeros(size(S_lfm));
                for kk=1:Kk, sb=sb+(abs((t-kk*Tss-Tsl/2)/Tsl)<=0.5).*S_lfm; end; sig=awgn(sb.*(1+0.3*randn(size(t))),snr_db,'measured');
        case 6, sig=awgn(cos(2*pi*B*(1.5+2*rand)*cumsum(0.5*randn(size(t)))*dt),snr_db,'measured');
        case 7, sig=sqrt(1.5)*randn(size(t));
        case 8, dfs=(10+20*rand)*1e6; Ts_w=(30+50*rand)*1e-6; fj=dfs*mod(t,Ts_w)/Ts_w; sig=awgn(cos(2*pi*cumsum(fj)*dt),snr_db,'measured');
        case 9, Nc=randi([3 7]); fc_=linspace(-5e6,5e6,Nc)*(0.5+0.5*rand); sc=zeros(size(S_lfm)); rect_d=(abs(t)<=Tp/2);
                for ii=1:Nc, sc=sc+0.3*rect_d.*exp(1j*2*pi*fc_(ii)*t); end; sig=awgn(real(sc),snr_db,'measured');
    end
end
