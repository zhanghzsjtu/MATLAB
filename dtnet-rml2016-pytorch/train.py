# -*- coding: utf-8 -*-
"""
train.py — DTNet (HSE) training on RML2016.10b, PyTorch version.

Network definition extracted verbatim from the original notebook
(RML2016b_DTNet.ipynb, cell-8); data loaded from an HDF5 file
(10 mods, unnormalized I/Q, 70/15/15 random split).

Usage:
  python train.py [data.h5] [epochs] [batch] [lr]

Default data path is resolved relative to this script's directory,
so the repo is portable across machines.
"""
import sys
import os
import time
import math
import copy
import warnings

import h5py
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim

_HERE = os.path.dirname(os.path.abspath(__file__))
DATA_FILE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(_HERE, "dataset2016b.h5")
EPOCHS    = int(sys.argv[2]) if len(sys.argv) > 2 else 20
BATCH     = int(sys.argv[3]) if len(sys.argv) > 3 else 2048
LR        = float(sys.argv[4]) if len(sys.argv) > 4 else 4e-3   # sqrt-scale for batch 2048
L2        = 5e-5
VAL_CHUNK = 8192
CKPT      = os.path.join(_HERE, "dtnet_best_pytorch.pt")

# ============================ network (from ipynb) =========================
ACT2FN = {"gelu": torch.nn.functional.gelu, "relu": torch.nn.functional.relu}


class Config:
    hidden_size = 40
    transformer = {"num_layers": 4, "num_heads": 4, "attention_dropout_rate": 0.25}
    mlp_dim = 128


config = Config()


class Mlp(nn.Module):
    def __init__(self, config):
        super(Mlp, self).__init__()
        input_dim = config.hidden_size
        hidden_dim = config.mlp_dim
        output_dim = config.hidden_size
        self.Linear1 = nn.Linear(input_dim // 2, hidden_dim // 2)
        self.Linear2 = nn.Linear(input_dim // 2, hidden_dim // 2)
        self.Linear3 = nn.Linear(hidden_dim // 2, output_dim // 2)
        self.Linear4 = nn.Linear(hidden_dim // 2, output_dim // 2)
        self.act_fn = ACT2FN["gelu"]
        self._init_weights()

    def _init_weights(self):
        nn.init.xavier_uniform_(self.Linear1.weight)
        nn.init.xavier_uniform_(self.Linear2.weight)
        nn.init.normal_(self.Linear1.bias, std=1e-6)
        nn.init.normal_(self.Linear2.bias, std=1e-6)
        nn.init.xavier_uniform_(self.Linear3.weight)
        nn.init.xavier_uniform_(self.Linear4.weight)
        nn.init.normal_(self.Linear3.bias, std=1e-6)
        nn.init.normal_(self.Linear4.bias, std=1e-6)

    def forward(self, x):
        m, n = torch.split(x, x.size(-1) // 2, dim=-1)
        m_out = self.Linear2(m)
        m_out = self.act_fn(m_out)
        n_out = self.Linear1(n)
        n_out = self.act_fn(n_out)
        db_mlp = torch.cat((self.Linear4(m_out), self.Linear3(n_out)), dim=-1)
        return db_mlp


def _no_grad_trunc_normal_(tensor, mean, std, a, b):
    def norm_cdf(x):
        return (1.0 + math.erf(x / math.sqrt(2.0))) / 2.0

    with torch.no_grad():
        l = norm_cdf((a - mean) / std)
        u = norm_cdf((b - mean) / std)
        tensor.uniform_(2 * l - 1, 2 * u - 1)
        tensor.erfinv_()
        tensor.mul_(std * math.sqrt(2.0))
        tensor.add_(mean)
        tensor.clamp_(min=a, max=b)
        return tensor


def trunc_normal_(tensor, mean=0.0, std=1.0, a=-2.0, b=2.0):
    return _no_grad_trunc_normal_(tensor, mean, std, a, b)


class Attention(nn.Module):
    def __init__(self, config, vis):
        super(Attention, self).__init__()
        self.vis = vis
        self.num_attention_heads = config.transformer["num_heads"]
        self.attention_head_size = int(config.hidden_size / self.num_attention_heads)
        self.all_head_size = self.num_attention_heads * self.attention_head_size
        self.query = nn.Linear(config.hidden_size, self.all_head_size)
        self.key = nn.Linear(config.hidden_size, self.all_head_size)
        self.value = nn.Linear(config.hidden_size, self.all_head_size)
        self.out = nn.Linear(config.hidden_size, config.hidden_size)
        self.attn_dropout = nn.Dropout(config.transformer["attention_dropout_rate"])
        self.proj_dropout = nn.Dropout(config.transformer["attention_dropout_rate"])
        self.softmax = nn.Softmax(dim=-1)

    def transpose_for_scores(self, x):
        new_x_shape = x.size()[:-1] + (self.num_attention_heads, self.attention_head_size)
        x = x.view(*new_x_shape)
        return x.permute(0, 2, 1, 3)

    def forward(self, hidden_states):
        mixed_query_layer = self.query(hidden_states)
        mixed_key_layer = self.key(hidden_states)
        mixed_value_layer = self.value(hidden_states)
        query_layer = self.transpose_for_scores(mixed_query_layer)
        key_layer = self.transpose_for_scores(mixed_key_layer)
        value_layer = self.transpose_for_scores(mixed_value_layer)
        attention_scores = torch.matmul(query_layer, key_layer.transpose(-1, -2))
        attention_scores = attention_scores / math.sqrt(self.attention_head_size)
        attention_probs = self.softmax(attention_scores)
        attention_probs = self.attn_dropout(attention_probs)
        context_layer = torch.matmul(attention_probs, value_layer)
        context_layer = context_layer.permute(0, 2, 1, 3).contiguous()
        new_context_layer_shape = context_layer.size()[:-2] + (self.all_head_size,)
        context_layer = context_layer.view(*new_context_layer_shape)
        attention_output = self.out(context_layer)
        attention_output = self.proj_dropout(attention_output)
        return attention_output


class Block(nn.Module):
    def __init__(self, config, vis):
        super(Block, self).__init__()
        self.hidden_size = config.hidden_size
        self.attention_norm = nn.LayerNorm(config.hidden_size, eps=1e-6)
        self.ffn_norm = nn.LayerNorm(config.hidden_size, eps=1e-6)
        self.ffn = Mlp(config)
        self.attn = Attention(config, vis)

    def forward(self, x):
        h = x
        x = self.attention_norm(x)
        x = self.attn(x)
        x = x + h
        h = x
        x = self.ffn_norm(x)
        x = self.ffn(x)
        x = x + h
        return x


class Encoder(nn.Module):
    def __init__(self, vis):
        super(Encoder, self).__init__()
        self.layer = nn.ModuleList()
        self.encoder_norm = nn.LayerNorm(config.hidden_size, eps=1e-6)
        for _ in range(config.transformer["num_layers"]):
            layer = Block(config, vis)
            self.layer.append(copy.deepcopy(layer))

    def forward(self, hidden_states):
        for layer_block in self.layer:
            hidden_states = layer_block(hidden_states)
        encoded = self.encoder_norm(hidden_states)
        return encoded


class SFE(nn.Module):
    def __init__(self, signal_size=(128, 2), in_channels=1):
        super(SFE, self).__init__()
        self.signal_size = signal_size
        self.scale = FE_Scale(2, 24)
        self.extension1 = FE_Extension(24, 32)
        self.extension2 = FE_Extension(32, 78)
        self.extension3 = FE_Extension(78, 96)
        self.extension4 = FE_Extension(96, 128)

    def forward(self, x):
        x = self.scale(x.view(-1, 2, self.signal_size[0], 1))
        x = self.extension1(x.view(-1, 24, self.signal_size[0], 1))
        x = self.extension2(x.view(-1, 32, self.signal_size[0], 1))
        x = self.extension3(x.view(-1, 78, self.signal_size[0], 1))
        x = self.extension4(x.view(-1, 96, self.signal_size[0], 1))
        return x


class Embeddings(nn.Module):
    def __init__(self, signal_size=(128, 2), in_channels=1):
        super(Embeddings, self).__init__()
        self.signal_size = signal_size
        self.hidden_size = config.hidden_size
        self.SFE = SFE()
        self.patch_size1 = (16, 2)
        self.patch_embeddings1 = nn.Conv2d(in_channels, self.hidden_size,
                                           kernel_size=self.patch_size1, stride=self.patch_size1)
        self.patch_size2 = (32, 32)
        self.patch_embeddings2 = nn.Conv2d(in_channels, self.hidden_size,
                                           kernel_size=self.patch_size2, stride=self.patch_size2)
        n_patches = (self.signal_size[0] // self.patch_size1[0]
                     + (self.signal_size[0] // self.patch_size2[0]) ** 2)
        self.position_embeddings = nn.Parameter(torch.zeros(1, n_patches + 1, self.hidden_size))
        self.cls_token = nn.Parameter(torch.zeros(1, 1, self.hidden_size))
        self.dropout = nn.Dropout(0.05)

    def forward(self, x):
        B = x.shape[0]
        cls_tokens = self.cls_token.expand(B, -1, -1)
        x_SFE = self.SFE(x)
        x1 = self.patch_embeddings1(x.view(-1, 1, self.signal_size[0], self.signal_size[1]))
        x2 = self.patch_embeddings2(x_SFE.view(-1, 1, self.signal_size[0], self.signal_size[0]))
        x = torch.cat([x1.view(-1, self.hidden_size, self.signal_size[0] // self.patch_size1[0]),
                       x2.view(-1, self.hidden_size,
                               (self.signal_size[0] // self.patch_size2[0]) ** 2)], 2)
        x = x.flatten(2)
        x = x.transpose(-1, -2)
        x = torch.cat((cls_tokens, x), dim=1)
        embeddings = x + self.position_embeddings
        embeddings = self.dropout(embeddings)
        return embeddings


class FE_Scale(nn.Module):
    def __init__(self, in_channels, out_channels, stride=1):
        super().__init__()
        self.Scale = Scale(out_channels, gap_size=(1))
        self.residual_function = nn.Sequential(
            nn.Conv1d(in_channels, out_channels, kernel_size=3, stride=stride, padding=1, bias=False),
            nn.BatchNorm1d(out_channels),
            nn.ReLU(inplace=True),
            nn.Conv1d(out_channels, out_channels, kernel_size=3, padding=1, bias=False),
            nn.BatchNorm1d(out_channels),
            self.Scale,
        )
        for layer in self.residual_function:
            if isinstance(layer, nn.Conv1d):
                nn.init.kaiming_normal_(layer.weight, mode='fan_out', nonlinearity='relu')

    def forward(self, x):
        x = x.view(-1, x.shape[1], x.shape[2] * x.shape[3])
        return nn.ReLU(inplace=True)(self.residual_function(x))


class Scale(nn.Module):
    def __init__(self, channel, gap_size):
        super(Scale, self).__init__()
        self.gap = nn.AdaptiveAvgPool1d(gap_size)
        self.fc = nn.Sequential(
            nn.Linear(channel, channel),
            nn.BatchNorm1d(channel),
            nn.ReLU(inplace=True),
            nn.Linear(channel, channel),
            nn.SiLU(),
        )
        self.tanh = nn.Tanh()

    def forward(self, x):
        x_raw = x
        x_abs = x.abs()
        x = self.gap(x)
        x = torch.flatten(x, 1)
        x = self.fc(x)
        x = x.unsqueeze(2)
        x = x_abs - x
        x = torch.mul(self.tanh(x_raw), torch.max(x, torch.zeros_like(x)))
        return x


class FE_Extension(nn.Module):
    def __init__(self, in_channels, out_channels, stride=1):
        super().__init__()
        self.Extention = Extention(out_channels, gap_size=(1))
        self.residual_function = nn.Sequential(
            DepthwiseSeparableCNN(in_channels, out_channels, kernel_size=3, stride=stride),
            nn.BatchNorm1d(out_channels),
            nn.ReLU(inplace=True),
        )

    def forward(self, x):
        x = x.view(-1, x.shape[1], x.shape[2] * x.shape[3])
        x = self.residual_function(x)
        x = self.Extention(x)
        return x


class Extention(nn.Module):
    def __init__(self, channel, gap_size):
        super(Extention, self).__init__()
        self.gap = nn.AdaptiveAvgPool1d(gap_size)
        self.fc = nn.Sequential(
            nn.Linear(channel, channel),
            nn.BatchNorm1d(channel),
            nn.ReLU(inplace=True),
            nn.Linear(channel, channel),
            nn.Sigmoid(),
        )

    def forward(self, x):
        x_raw = x
        x = self.gap(x)
        x = torch.flatten(x, 1)
        out = self.fc(x)
        out = out.view(out.size(0), out.size(1), 1)
        out = out * x_raw
        return out


class DepthwiseSeparableCNN(nn.Module):
    def __init__(self, in_channels, out_channels, kernel_size=3, stride=1):
        super(DepthwiseSeparableCNN, self).__init__()
        self.depthwise_conv = nn.Conv1d(in_channels, in_channels, kernel_size=kernel_size,
                                        stride=stride, padding=1, groups=in_channels, bias=False)
        self.pointwise_conv = nn.Conv1d(in_channels, out_channels, kernel_size=1, stride=1,
                                        padding=0, bias=False)
        self.bn = nn.BatchNorm1d(out_channels)
        self.relu = nn.ReLU(inplace=True)

    def forward(self, x):
        x = self.depthwise_conv(x)
        x = self.pointwise_conv(x)
        x = self.bn(x)
        x = self.relu(x)
        return x


class TransformerEncoder(nn.Module):
    def __init__(self, signal_size, vis):
        super(TransformerEncoder, self).__init__()
        self.embeddings = Embeddings()
        self.encoder = Encoder(vis)

    def forward(self, input_ids):
        embedding_output = self.embeddings(input_ids)
        encoded = self.encoder(embedding_output)
        return encoded


class HSE(nn.Module):
    def __init__(self, signal_size=(128, 2), num_classes=10, vis=False):
        super(HSE, self).__init__()
        self.num_classes = num_classes
        self.transformer = TransformerEncoder(signal_size, vis)
        self.head = nn.Linear(config.hidden_size, num_classes)

    def forward(self, x):
        x = self.transformer(x)
        logits = self.head(x[:, 0])
        return logits


# ============================== data + training ============================
def load_h5(path, split):
    with h5py.File(path, 'r') as f:
        X = f[f'X_{split}'][:]     # [N,1,128,2] float32
        Y = f[f'Y_{split}'][:]     # [N,10] one-hot
    return X, Y


def main():
    torch.manual_seed(2016)
    np.random.seed(2016)
    torch.backends.cudnn.benchmark = True     # auto-tune cuDNN kernels

    print(f'[PT] data={DATA_FILE} epochs={EPOCHS} batch={BATCH} lr={LR} wd={L2}')
    X_train, Y_train = load_h5(DATA_FILE, 'train')
    X_val, Y_val = load_h5(DATA_FILE, 'val')
    print(f'[PT] train {X_train.shape} val {X_val.shape}')

    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f'[PT] device: {device} ({torch.cuda.get_device_name(0) if torch.cuda.is_available() else "cpu"})')

    net = HSE(num_classes=10).to(device)
    criterion = nn.CrossEntropyLoss()

    # Fused Adam (CUDA kernel fusion) keeps the exact Adam+weight_decay
    # semantics of the original ipynb, only the kernels are fused.
    try:
        optimizer = optim.Adam(net.parameters(), lr=LR, weight_decay=L2,
                               fused=torch.cuda.is_available())
        print('[PT] Adam fused=True')
    except TypeError:
        optimizer = optim.Adam(net.parameters(), lr=LR, weight_decay=L2)
        print('[PT] Adam fused not supported, plain Adam')

    # Mixed precision (fp16 tensor cores)
    use_amp = torch.cuda.is_available()
    scaler = torch.amp.GradScaler('cuda') if use_amp else None

    # DataLoader: parallel prefetch + pinned memory
    train_ds = torch.utils.data.TensorDataset(
        torch.from_numpy(X_train), torch.from_numpy(Y_train).argmax(1))
    train_loader = torch.utils.data.DataLoader(
        train_ds, batch_size=BATCH, shuffle=True, drop_last=True,
        num_workers=4, pin_memory=True, persistent_workers=True)

    y_val_labels = Y_val.argmax(1)

    best_acc = 0.0
    t_start = time.time()
    for epoch in range(EPOCHS):
        net.train()
        total_loss = 0.0
        n_b = 0
        t0 = time.time()
        for xb, yb in train_loader:
            xb, yb = xb.to(device, non_blocking=True), yb.to(device, non_blocking=True)
            with torch.amp.autocast('cuda', enabled=use_amp):
                out = net(xb)
                loss = criterion(out, yb)
            scaler.scale(loss).backward()
            scaler.step(optimizer)
            scaler.update()
            optimizer.zero_grad()
            total_loss += loss.item()
            n_b += 1

        # validation (chunked, AMP inference)
        net.eval()
        preds = []
        with torch.no_grad(), torch.amp.autocast('cuda', enabled=use_amp):
            for i in range(0, len(X_val), VAL_CHUNK):
                xb = torch.as_tensor(X_val[i:i + VAL_CHUNK], device=device)
                preds.append(net(xb).argmax(1).cpu().numpy())
        preds = np.concatenate(preds)
        val_acc = float((preds == y_val_labels).mean())
        lr_now = optimizer.param_groups[0]['lr']
        print(f'Epoch {epoch + 1:02d} | train loss {total_loss / n_b:.4f} | '
              f'val acc {val_acc:.4f} | lr {lr_now:.2e} | {time.time() - t0:.0f}s')
        if val_acc > best_acc:
            best_acc = val_acc
            torch.save(net.state_dict(), CKPT)
        if (epoch + 1) % 5 == 0:
            for g in optimizer.param_groups:
                g['lr'] *= 0.5

    print(f'[PT] best val acc: {best_acc:.4f}  total {time.time() - t_start:.0f}s')
    print(f'[PT] saved {CKPT}')


if __name__ == '__main__':
    main()
