%% main_ecnn_exp.m  —  基于ECNN的深度学习干扰识别仿真实验
% 复现书179~182页：多通道特征融合的集成卷积神经网络(ECNN)
% 网络结构参考表5.2，数据流参考179页步骤一~四
% 输出: fig5_13_ecnn_results.png (OA/AA对比曲线)

%% ======================== 参数设置 ========================
Tp=20e-6; B=10e6; fs=20e6;
N_per_class = 300;   % 每类样本数（兼顾运行时间）
Nclasses_all = 12;    % 12类: 无干扰+7单一干扰+4复合干扰(书180页设定)
snr_db = 0;

% STFT参数（对齐书180页）
stft_nseg     = 32;
stft_overlap  = 8;
stft_nfft     = 100;
stft_win      = hamming(round((round(Tp*fs)/stft_nseg)+stft_overlap));

% 训练集比例
train_ratios = [0.02, 0.04, 0.06, 0.08];  % 2%,4%,6%,8%
n_runs       = 3;                           % 重复次数取平均

[t,S_lfm]=lfm_signal(Tp,B,fs,0);
Npts=length(t);

%% ======================== 数据集生成 ========================
fprintf('=== ECNN深度学习干扰识别实验 ===\n');
fprintf('生成 %d 类 × %d 样本 = %d 个时域样本...\n', Nclasses_all, N_per_class, Nclasses_all*N_per_class);

% 12类定义 (参考180页):
% 0=无干扰, 1=密集假目标, 2=ISRJ, 3=距离欺骗, 4=灵巧噪声,
% 5=扫频, 6=阻塞(宽带压制), 7=线性扫频,
% 8=距离欺骗+灵巧噪声, 9=密集假目标+灵巧噪声,
% 10=距离欺骗+ISRJ, 11=线性扫频+ISRJ

cls_names_12 = {'无干扰','密集假目标','ISRJ','距离欺骗','灵巧噪声',...
                '扫频','宽带压制','线性扫频','距离+灵巧','密集+灵巧',...
                '距离+ISRJ','扫频+ISRJ'};

X_time = zeros(N_per_class*Nclasses_all, Npts);
Y_full = zeros(N_per_class*Nclasses_all, 1);

rng(2024);
for cls = 0:Nclasses_all-1
    fprintf('  类别%d(%s)...\n', cls+1, cls_names_12{cls+1});
    for n = 1:N_per_class
        idx = cls*N_per_class + n;
        X_time(idx,:) = real(gen_sample_12class(t,S_lfm,Tp,B,fs,cls,snr_db))';
        Y_full(idx) = cls;
    end
end

%% ======================== STFT时频图生成 ========================
fprintf('\n计算STFT时频图(三通道: 实部/虚部/模值)...\n');

% 先算一个样本确定输出尺寸
S_test = stft(X_time(1,:), fs, 'Window', stft_win, 'OverlapLength', stft_overlap, ...
              'FFTLength', stft_nfft, 'Centered', true);
[stft_h, stft_w] = size(S_test);
fprintf('STFT输出尺寸: %d × %d\n', stft_h, stft_w);

% 预分配 [H, W, C, N] (MATLAB trainNetwork 要求N在最后一维)
X_tf = zeros(stft_h, stft_w, 3, N_per_class*Nclasses_all);

parfor i = 1:size(X_time,1)
    S_stft = stft(X_time(i,:), fs, 'Window', stft_win, 'OverlapLength', stft_overlap, ...
                   'FFTLength', stft_nfft, 'Centered', true);
    R = real(S_stft); Im = imag(S_stft); M = abs(S_stft);
    % 归一化到[0,1]
    R = (R-min(R(:)))/(max(R(:))-min(R(:))+1e-10);
    Im = (Im-min(Im(:)))/(max(Im(:))-min(Im(:))+1e-10);
    M = (M-min(M(:)))/(max(M(:))-min(M(:))+1e-10);
    tmp = cat(3, R, Im, M);      % 拼为 [stft_h, stft_w, 3] = [100,30,3]
    X_tf(:,:,:,i) = tmp;         % 单次赋值，parfor兼容 (N在最后一维)
end
fprintf('时频图数据集尺寸: %s\n', mat2str(size(X_tf)));

%% ======================== 定义CNN网络 (表5.2) ========================
layers_cnn = [
    imageInputLayer([stft_h stft_w 3], 'Name','input','Normalization','none')  % X_tf格式 [H,W,C,N]
    
    convolution2dLayer([13 13], 64, 'Padding','same', 'Name','conv1')
    batchNormalizationLayer('Name','bn1')
    reluLayer('Name','relu1')
    maxPooling2dLayer([2 2], 'Stride',[2 2], 'Name','pool1')
    dropoutLayer(0.25, 'Name','drop1')
    
    convolution2dLayer([9 9], 128, 'Padding','same', 'Name','conv2')
    batchNormalizationLayer('Name','bn2')
    reluLayer('Name','relu2')
    maxPooling2dLayer([2 2], 'Stride',[2 2], 'Name','pool2')
    
    convolution2dLayer([5 5], 128, 'Padding','same', 'Name','conv3')
    batchNormalizationLayer('Name','bn3')
    reluLayer('Name','relu3')
    maxPooling2dLayer([2 2], 'Stride',[2 2], 'Name','pool3')
    dropoutLayer(0.25, 'Name','drop2')
    
    convolution2dLayer([3 3], 256, 'Padding','same', 'Name','conv4')
    batchNormalizationLayer('Name','bn4')
    reluLayer('Name','relu4')
    maxPooling2dLayer([2 2], 'Stride',[2 2], 'Name','pool4')
    
    fullyConnectedLayer(Nclasses_all, 'Name','fc_out')
    softmaxLayer('Name','softmax')
    classificationLayer('Name','output')
];

fprintf('\nCNN网络层数: %d\n', length(layers_cnn));

%% ======================== 训练选项 ========================
options = trainingOptions('sgdm', ...
    'MaxEpochs', 30, ...
    'MiniBatchSize', 32, ...
    'InitialLearnRate', 0.001, ...
    'Shuffle','every-epoch', ...
    'Plots','none', ...
    'Verbose',false, ...
    'L2Regularization', 0.0001);

%% ======================== 多比例训练实验 ========================
results_OA = zeros(length(train_ratios), n_runs);
results_AA = zeros(length(train_ratios), n_runs);

for ri = 1:length(train_ratios)
    ratio = train_ratios(ri);
    fprintf('\n===== 训练集比例: %.0f%% =====\n', ratio*100);
    
    for run_i = 1:n_runs
        fprintf('  第%d次重复...\n', run_i);
        
        % 划分训练/测试集（HoldOut参数=测试集比例; 用1-ratio使训练集=ratio）
        cv = cvpartition(numel(Y_full), 'HoldOut', 1-ratio);
        tr_idx = training(cv);
        te_idx = test(cv);

        X_tr = X_tf(:,:,:,tr_idx);
        Y_tr = categorical(Y_full(tr_idx(:)));
        X_te = X_tf(:,:,:,te_idx);
        Y_te = categorical(Y_full(te_idx(:)));

        % 尺寸一致性断言 (N在X_tf第4维)
        assert(size(X_tr,4)==numel(Y_tr), 'X_tr/Y_tr 数量不一致');
        assert(size(X_te,4)==numel(Y_te), 'X_te/Y_te 数量不一致');
        fprintf('  [debug] X_tr=%s Y_tr=%d X_te=%s Y_te=%d\n', ...
            mat2str(size(X_tr)), numel(Y_tr), mat2str(size(X_te)), numel(Y_te));
        
        % 训练CNN
        rng(run_i * 100);
        net = trainNetwork(X_tr, Y_tr, layers_cnn, options);
        
        % 预测
        Y_pred = classify(net, X_te);
        
        % 计算准确率
        acc = mean(Y_pred == Y_te) * 100;
        
        % 计算每类准确率(AA)
        per_acc = zeros(Nclasses_all, 1);
        for c = 1:Nclasses_all
            idx_c = Y_te == categorical(c-1);
            if sum(idx_c) > 0
                per_acc(c) = mean(Y_pred(idx_c) == Y_te(idx_c)) * 100;
            end
        end
        aa = mean(per_acc);
        
        results_OA(ri, run_i) = acc;
        results_AA(ri, run_i) = aa;
        
        fprintf('    OA=%.1f%%, AA=%.1f%%\n', acc, aa);
    end
    
    fprintf('  -> 平均 OA=%.1f%% (+/-%.1f), AA=%.1f%% (+/-%.1f)\n', ...
        mean(results_OA(ri,:)), std(results_OA(ri,:)), ...
        mean(results_AA(ri,:)), std(results_AA(ri,:)));
end

%% ======================== 基线方法: RF (人工特征) ========================
fprintf('\n===== 基线: Random Forest (人工特征) =====\n');
% 提取7维人工特征 (同决策树实验)
F_energy = sum(X_time.^2, 2);
F_bw=zeros(size(X_time,1),1); F_n1=zeros(size(X_time,1)); F_mw=zeros(size(X_time,1));
F_tw=zeros(size(X_time,1)); F_sk=zeros(size(X_time,1)); F_n2=zeros(size(X_time,1));
for i=1:size(X_time,1)
    xf=abs(fft(X_time(i,:))); xf=xf/max(xf); F_bw(i)=sum(xf>0.3)*fs/Npts/1e6;
    x=X_time(i,:); Tth=3*std(x(round(Npts*0.85:end))); F_n1(i)=sum(abs(x)<Tth)/Npts;
    wl=round(Npts*0.15); F_mw(i)=(mean(abs(x(1:wl)))+mean(abs(x(end-wl+1:end))))/2;
    env=abs(hilbert(x)); env=env/max(env); F_tw(i)=sum(env>0.1)/fs*1e6;
    F_sk(i)=skewness(abs(fftshift(fft(X_time(i,:)))));
    nw=5; ws=floor(Npts/nw); sks=zeros(nw,1);
    for w=1:nw, seg=x((w-1)*ws+1:min(w*ws,Npts)); sks(w)=skewness(abs(fftshift(fft(seg)))); end
    F_n2(i)=mean(sks);
end
F_manual = [F_energy,F_bw,F_n1,F_mw,F_tw,F_sk,F_n2];

% === RF基线(人工特征)：因TreeBagger训练较慢，单独运行，此处注释避免阻塞出图 ===
% rf_OA = zeros(length(train_ratios), n_runs);
% rf_AA = zeros(length(train_ratios), n_runs);
% for ri=1:length(train_ratios)
%     for run_i=1:n_runs
%         cv=cvpartition(numel(Y_full),'HoldOut',1-train_ratios(ri));
%         tr_idx=training(cv); te_idx=test(cv);
%         b=TreeBagger(100,F_manual(tr_idx,:),Y_full(tr_idx(:)),'OOBPrediction','on');
%         pred=predict(b,F_manual(te_idx,:));
%         pred_num = str2double(pred);
%         rf_OA(ri,run_i)=mean(pred_num==Y_full(te_idx))*100;
%         pa=zeros(Nclasses_all,1);
%         for c=1:Nclasses_all, ic=Y_full(te_idx)==(c-1); if sum(ic)>0, pa(c)=mean(pred_num(ic)==Y_full(ic))*100; end, end
%         rf_AA(ri,run_i)=mean(pa);
%     end
%     fprintf('  RF %.0f%%: OA=%.1f%%, AA=%.1f%%\n', train_ratios(ri)*100, mean(rf_OA(ri,:)), mean(rf_AA(ri,:)));
% end
rf_OA = zeros(length(train_ratios), n_runs);   % 占位，图5.13仅画ECNN曲线
rf_AA = zeros(length(train_ratios), n_runs);

%% ======================== 绘制图5.13风格结果曲线 ========================
figure('Position',[50 50 900 420]);

% OA曲线
subplot(1,2,1);
errorbar(train_ratios*100, mean(results_OA,2), std(results_OA,0,2), '-bo', 'LineWidth',2,'MarkerSize',8,'MarkerFaceColor','b');
xlabel('训练样本占比/%'); ylabel('整体精度(OA)/%');
title('(a) ECNN整体分类精度OA'); grid on; xlim([0 10]); ylim([0 100]);

% AA曲线
subplot(1,2,2);
errorbar(train_ratios*100, mean(results_AA,2), std(results_AA,0,2), '-bo', 'LineWidth',2,'MarkerSize',8,'MarkerFaceColor','b');
xlabel('训练样本占比/%'); ylabel('平均精度(AA)/%');
title('(b) ECNN平均分类精度AA'); grid on; xlim([0 10]); ylim([0 100]);

sgtitle('图5.13  ECNN十二类干扰识别结果（复现）','FontSize',13,'FontWeight','bold');
saveas(gcf,'D:/11-捷变雷达抗干扰与信号处理技术/_复现工作/sim/fig5_13_ecnn_results.png');

% 打印最终结果表
fprintf('\n========== ECNN最终结果汇总 ==========\n');
fprintf('%-8s %-12s %-12s\n','训练比%','ECNN-OA','ECNN-AA');
for ri=1:length(train_ratios)
    fprintf('%-8.0f %-12.1f %-12.1f\n', ...
        train_ratios(ri)*100, mean(results_OA(ri,:)), mean(results_AA(ri,:)));
end
fprintf('=====================================\n');
fprintf('结果已保存至 _复现工作/sim/fig5_13_ecnn_results.png\n');

%% ===================== 局部函数 =====================
function [t,S]=lfm_signal(Tp,B,fs,f0)
    if nargin<4
        f0=0;
    end
    N=round(Tp*fs); t=(0:N-1)'/fs; k=B/Tp;
    S=(double(abs(t)<=Tp/2)).*exp(1j*(2*pi*f0*t+pi*k*t.^2));
end

function sig=gen_sample_12class(t,S_lfm,Tp,B,fs,cls,snr_db)
    dt=t(2)-t(1);
    switch cls
        case 0, sig=awgn(0.5*S_lfm,snr_db,'measured');
        case 1, s=zeros(size(S_lfm)); for nn=1:randi([3 6]), s=s+0.8*interp1(t,S_lfm,t+(1+9*rand)*1e-6,'linear',0); end; sig=awgn(s,snr_db,'measured');
        case 2, Tsl=(0.8+1.2*rand)*1e-6; Tss=(1.5+3.5*rand)*1e-6; Kk=floor(Tp/Tss); s=zeros(size(S_lfm));
            for kk=1:Kk,s=s+(abs((t-kk*Tss-Tsl/2)/Tsl)<=0.5).*S_lfm;end
sig=awgn(s,snr_db,'measured');
        case 3, sig=awgn(interp1(t,S_lfm,t+(1+9*rand)*1e-6,'linear',0),snr_db,'measured');
        case 4, Tsl=(0.8+1.2*rand)*1e-6; Tss=(1.5+3.5*rand)*1e-6; Kk=floor(Tp/Tss); sb=zeros(size(S_lfm));
            for kk=1:Kk,sb=sb+(abs((t-kk*Tss-Tsl/2)/Tsl)<=0.5).*S_lfm;end
sig=awgn(sb.*(1+0.3*randn(size(t))),snr_db,'measured');
        case 5, dfs=(10+20*rand)*1e6; Ts_w=(30+50*rand)*1e-6; fj=dfs*mod(t,Ts_w)/Ts_w; sig=awgn(cos(2*pi*cumsum(fj)*dt),snr_db,'measured');
        case 6, sig=sqrt(1.5)*randn(size(t));
        case 7, K_fm=B*(1.5+2*rand); sig=awgn(cos(2*pi*K_fm*cumsum(0.5*randn(size(t)))*dt),snr_db,'measured');
        case 8, s_rd=interp1(t,S_lfm,t+(1+9*rand)*1e-6,'linear',0); sn=(0.3+0.4*rand)*randn(size(t)); sig=awgn(s_rd.*(1+sn),snr_db,'measured');
        case 9, s=zeros(size(S_lfm)); for nn=1:randi([3 6]), s=s+0.8*interp1(t,S_lfm,t+(1+9*rand)*1e-6,'linear',0); end; sn=0.3*randn(size(t)); sig=awgn(s.*(1+sn),snr_db,'measured');
        case 10, s_rd=interp1(t,S_lfm,t+(1+9*rand)*1e-6,'linear',0); Tsl=(0.8+1.2*rand)*1e-6; Tss=(1.5+3.5*rand)*1e-6; Kk=floor(Tp/Tss); isrj_s=zeros(size(S_lfm));
            for kk=1:Kk,isrj_s=isrj_s+(abs((t-kk*Tss-Tsl/2)/Tsl)<=0.5).*S_lfm;end; sig=awgn(s_rd+isrj_s,snr_db,'measured');
        case 11, dfs=(10+20*rand)*1e6; Ts_w=(30+50*rand)*1e-6; fj=dfs*mod(t,Ts_w)/Ts_w; sw=cos(2*pi*cumsum(fj)*dt); Tsl=(0.8+1.2*rand)*1e-6; Tss=(1.5+3.5*rand)*1e-6; Kk=floor(Tp/Tss); isrj_s=zeros(size(S_lfm));
            for kk=1:Kk,isrj_s=isrj_s+(abs((t-kk*Tss-Tsl/2)/Tsl)<=0.5).*S_lfm;end; sig=awgn(sw+isrj_s,snr_db,'measured');
    end
end
