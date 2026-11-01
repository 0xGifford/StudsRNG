#!/usr/bin/env python3
"""Cross-module API check: every `Alias.member` used on a required module
must exist in that module (`function M.member`, `M.member =`, or a key of
the table it returns). Catches typos and calls to functions that were
renamed or removed, which the analyzer can't see through Roblox requires.

    python3 tools/lint_modules.py
"""
import re, pathlib, sys
from collections import defaultdict

files = [p for p in pathlib.Path("src").rglob("*.lua")]
by_name = defaultdict(list)
for p in files:
    name = p.stem if p.stem != "init" else p.parent.name
    by_name[name].append(p)

def exports(path):
    s = path.read_text()
    names = set()
    ret = re.findall(r"^return\s+([A-Za-z_]\w*)\s*$", s, re.M)
    table = ret[-1] if ret else None
    if table:
        for m in re.finditer(rf"^(?:function\s+{table}[.:](\w+)|{table}\.(\w+)\s*=)", s, re.M):
            names.add(m.group(1) or m.group(2))
        # local T = { key = ..., } literal at declaration
        m = re.search(rf"^local {table}\s*(?::[^=]+)?=\s*\{{(.*?)^\}}", s, re.M | re.S)
        if m:
            depth = 0
            for line in m.group(1).splitlines():
                if depth == 0:
                    k = re.match(r"\s*(\w+)\s*=", line)
                    if k: names.add(k.group(1))
                depth += line.count("{") - line.count("}")
        return names, True
    # return { ... } literal: top-level keys
    m = re.search(r"^return\s*\{(.*)\}\s*$", s, re.M | re.S)
    if m:
        depth = 0
        for line in m.group(1).splitlines():
            if depth == 0:
                k = re.match(r"\s*(\w+)\s*=", line)
                if k: names.add(k.group(1))
            depth += line.count("{") - line.count("}")
        return names, True
    return names, False  # returns something else (a Component, a call...): skip

cache = {}
problems = []
def strip_comments(text):
    text = re.sub(r"--\[(=*)\[.*?\]\1\]", "", text, flags=re.S)
    return re.sub(r"--[^\n]*", "", text)

for p in files:
    s = strip_comments(p.read_text())
    for m in re.finditer(r"^local (\w+) = require\(([^\n]+)\)\s*$", s, re.M):
        alias, arg = m.group(1), m.group(2)
        target = re.findall(r'["\.](\w+)"?\)*\s*$', arg.strip().rstrip(")"))
        seg = re.findall(r'(\w+)', arg)
        if not seg: continue
        name = seg[-1]
        cands = by_name.get(name, [])
        if len(cands) != 1: continue
        mod = cands[0]
        if mod not in cache: cache[mod] = exports(mod)
        names, known = cache[mod]
        if not known or not names: continue
        for u in set(re.findall(rf"(?<![\w.:]){alias}[.:](\w+)", s)):
            if u not in names:
                # types (Alias.Type in annotations) start uppercase and appear after ':' or '::'
                if re.search(rf"(?::|::|<|,\s*)\s*{alias}\.{u}\b", s) and not re.search(rf"{alias}[.:]{u}\s*\(", s):
                    continue
                if re.search(rf"export type {u}\b", mod.read_text()):
                    continue
                problems.append(f"{p}: {alias}.{u} — {mod.name} has no '{u}'")
for x in sorted(problems): print(x)
print(f"{len(files)} files, {len(problems)} unknown module member(s)")
sys.exit(1 if problems else 0)
