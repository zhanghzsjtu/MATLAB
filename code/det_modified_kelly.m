function [Lambda, eps_hat] = det_modified_kelly(Z, Rhat_train, K, v, eps_grid, Tp)
%det_modified_kelly  Modified Kelly's GLRT (DeMaio-Orlando 2011 TSP, eq. 26-30)
%
%   严格按论文 (27)-(28) 行列式之比 + Lemma 1 的 alpha 闭式实现。
%
%   论文 (27) (漏向左, 含目标门 = l-1, l):
%     K_{-1}(eps) = |I + S^{-1} * (sum_{i=l-1}^{l+1} z_i z_i^H)| /
%                   |I + S^{-1} * (u_{l-1} u_{l-1}^H + u_l u_l^H)|
%   论文 (28) (漏向右, 含目标门 = l, l+1):
%     K_1(eps)   = |I + S^{-1} * (sum_{i=l-1}^{l+1} z_i z_i^H)| /
%                   |I + S^{-1} * (u_l u_l^H + u_{l+1} u_{l+1}^H)|
%   其中 S = K * Rhat_train (仅训练样本 SCM, 即 S_{l,l+1} 中不含目标的部分),
%   u_i = z_i - alpha_hat * c_i * v, alpha_hat 由 Lemma 1 闭式 (精讲第4步) 给出:
%     alpha_hat = [c_l (v^H S^{-1} z_l) + c_{l+1} (v^H S^{-1} z_{l+1})] /
%                 [(c_l^2 + c_{l+1}^2) (v^H S^{-1} v)]
%
%   论文 (26): Lambda = max_{eps} max(K_{-1}(eps), K_1(eps)) > eta
%    eps=0 时退化为经典 Kelly (29)。
%
%   实现: 直接用 det(I + M) 计算 N 维行列式 (N=16, 数值稳定),
%         M = S^{-1}(xx^H) 通过 invS*x*x' 构造并取 real。

nEps = length(eps_grid);
Lambda_e = zeros(nEps, 1);
v = v(:);
N = length(v);
eyeN = eye(N);

% 仅训练样本 SCM: S = K * Rhat_train (论文 S_{l,l+1} 的噪声部分)
S_train = K * Rhat_train;
invS = inv(S_train + 1e-12 * eyeN);   % 正则化防止数值奇异

% 预计算 v^H S^{-1} v 与 3 门主数据
vSv = real(v' * invS * v);
zlm = Z(:,1);  % z_{l-1}
zl  = Z(:,2);  % z_l
zlp = Z(:,3);  % z_{l+1}

% 预计算 S^{-1} * z (用于分子分母构造)
Szlm = invS * zlm;
Szl  = invS * zl;
Szlp = invS * zlp;

for k = 1:nEps
    eps = eps_grid(k);
    if eps == 0
        % 经典 Kelly (29) 标量形式: 待检 = z_l, 噪声门 = l-1, l+1
        Sbar = S_train + zlm*zlm' + zlp*zlp';
        invSb = inv(Sbar + 1e-12 * eyeN);
        zt = real(zl' * invSb * zl);
        num = abs(v' * invSb * zl)^2;
        den = real(v' * invSb * v);
        B = 1 + zt;
        if abs(B - num/den) < 1e-15
            Lambda_e(k) = realmax;
        else
            Lambda_e(k) = B / (B - num/den);
        end
    elseif eps < 0
        % ---- 漏向左: 含目标门 = (l-1, l), 噪声门 = l+1 ----
        % S_{l,l+1} = z_{l+1} z_{l+1}^H + K Rhat (精讲第4步 noise-only 散布)
        Sl = S_train + zlp*zlp';
        invSl = inv(Sl + 1e-12 * eyeN);
        vSv_l = real(v' * invSl * v);
        % 分子: 仅含目标两门
        Szlm_l = invSl * zlm;
        Szl_l  = invSl * zl;
        D_num = real(det(eyeN + Szlm_l*zlm' + Szl_l*zl'));
        % 系数 (矩形脉冲, f=0)
        c_lm = -eps / Tp;
        c_l  = 1 + eps / Tp;
        % Lemma 1 闭式 alpha_hat (用 Sl)
        x_lm = v' * invSl * zlm;
        x_l  = v' * invSl * zl;
        alpha_hat = (c_lm * x_lm + c_l * x_l) / ((c_lm^2 + c_l^2) * vSv_l);
        u_lm = zlm - alpha_hat * c_lm * v;
        u_l  = zl  - alpha_hat * c_l  * v;
        Su_lm = invSl * u_lm;
        Su_l  = invSl * u_l;
        D_den = real(det(eyeN + Su_lm*u_lm' + Su_l*u_l'));
        if D_den < 1e-15
            Lambda_e(k) = realmax;
        else
            Lambda_e(k) = D_num / D_den;
        end
    else
        % ---- 漏向右: 含目标门 = (l, l+1), 噪声门 = l-1 ----
        % S_{l,l+1} = z_{l-1} z_{l-1}^H + K Rhat
        Sl = S_train + zlm*zlm';
        invSl = inv(Sl + 1e-12 * eyeN);
        vSv_l = real(v' * invSl * v);
        Szl_l  = invSl * zl;
        Szlp_l = invSl * zlp;
        D_num = real(det(eyeN + Szl_l*zl' + Szlp_l*zlp'));
        c_l  = 1 - eps / Tp;
        c_lp = eps / Tp;
        x_l  = v' * invSl * zl;
        x_lp = v' * invSl * zlp;
        alpha_hat = (c_l * x_l + c_lp * x_lp) / ((c_l^2 + c_lp^2) * vSv_l);
        u_l  = zl  - alpha_hat * c_l  * v;
        u_lp = zlp - alpha_hat * c_lp * v;
        Su_l  = invSl * u_l;
        Su_lp = invSl * u_lp;
        D_den = real(det(eyeN + Su_l*u_l' + Su_lp*u_lp'));
        if D_den < 1e-15
            Lambda_e(k) = realmax;
        else
            Lambda_e(k) = D_num / D_den;
        end
    end
end

[Lambda, idx] = max(Lambda_e);
eps_hat = eps_grid(idx);
end
