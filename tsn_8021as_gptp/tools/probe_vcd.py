#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""列出各 VCD 中的信号名, 便于挑选绘图信号。"""
import re, os

def list_signals(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        txt = f.read()
    decl, _, _ = txt.partition("$enddefinitions")
    names = []
    for m in re.finditer(r"\$var\s+\w+\s+\d+\s+(\S+)\s+([\w.\[\]]+)\s*\$end", decl):
        names.append(m.group(2))
    return names

base = "E:/03-tsn/tsn_8021as/tsn_8021as/sim"
for fn in sorted(os.listdir(base)):
    if fn.endswith(".vcd"):
        print("==== ", fn, " ====")
        for n in list_signals(os.path.join(base, fn)):
            print("   ", n)
