#!/usr/bin/env python3
"""Luau 정적 분석(luau-analyze). Roblox 전역(script, game, Instance, Vector3, ...)은 CLI 분석기가 모르므로 'Unknown global/require' 는 환경 한계로 분류하고,
SyntaxError 와 그 밖의 TypeError 를 따로 센다. 사용법: python3 tools/analyze.py [파일...]  (생략하면 src/ tests/ 전체)"""
import os, subprocess, sys, re
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AN = os.environ.get("LUAU_ANALYZE", "/home/claude/tools/luau-bin/luau-analyze")
files = sys.argv[1:]
if not files:
    for d in ("src", "tests"):
        for dp, _, fs in os.walk(os.path.join(ROOT, d)):
            files += [os.path.join(dp, f) for f in fs if f.endswith(".luau")]
syn, other, env = 0, [], 0
for f in sorted(files):
    out = subprocess.run([AN, f], capture_output=True, text=True, cwd=ROOT); out = out.stdout + out.stderr
    for line in out.splitlines():
        if "SyntaxError" in line:
            syn += 1; print("SYNTAX", line)
        elif "Unknown global" in line or "Unknown require" in line:
            env += 1
        elif "Error" in line:
            other.append(line)
print("파일 %d개: SyntaxError %d, 환경 한계(Unknown global/require) %d, 그 외 TypeError/경고 %d" % (len(files), syn, env, len(other)))
for l in other: print("  ", l)
sys.exit(1 if syn else 0)
