#!/usr/bin/env python3
"""BRICKYARD 맵 생성기 순수 로직 테스트(Luau CLI). 기존 전투 테스트(tools/run_tests.py)와 독립.
사용법: python3 tools/run_map_tests.py [--luau 경로] [--out docs/MAP_TEST_RESULTS.md]
"""
import argparse, datetime, os, re, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAT_DOT = re.compile(r'require\(script\.Parent\.([A-Za-z_][A-Za-z0-9_]*)\)')


def convert(text):
    return PAT_DOT.sub(lambda m: 'require("./%s")' % m.group(1), text)


def copy_tree(src, dst, only=None):
    for dirpath, _, files in os.walk(src):
        rel = os.path.relpath(dirpath, src)
        os.makedirs(os.path.join(dst, rel), exist_ok=True)
        for f in files:
            if f.endswith(".luau") and (only is None or f in only):
                with open(os.path.join(dirpath, f), encoding="utf-8") as fh:
                    body = convert(fh.read())
                with open(os.path.join(dst, rel, f), "w", encoding="utf-8") as fh:
                    fh.write(body)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--luau", default=shutil.which("luau") or os.path.join(ROOT, "..", "tools", "luau-bin", "luau"))
    ap.add_argument("--out", default=None)
    args = ap.parse_args()
    # Roblox 전용 모듈은 CLI에서 로드하지 않는다(테스트가 require 하지 않음).
    with tempfile.TemporaryDirectory() as tmp:
        copy_tree(os.path.join(ROOT, "src", "map"), os.path.join(tmp, "map"),
                  only={"BrickyardConfig.luau", "MapLayout.luau", "MapValidator.luau", "MapBuilder.luau", "SpawnAnalysis.luau", "SpawnRegistry.luau", "SpawnRisk.luau"})
        copy_tree(os.path.join(ROOT, "tests_map"), os.path.join(tmp, "tests_map"))
        shutil.copy(os.path.join(ROOT, "tests", "TestRunner.luau"), os.path.join(tmp, "tests_map", "TestRunner.luau"))
        proc = subprocess.run([args.luau, os.path.join(tmp, "tests_map", "run_all.luau")], capture_output=True, text=True, cwd=tmp)
    output = proc.stdout + proc.stderr
    print(output)
    if args.out:
        stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
        with open(os.path.join(ROOT, args.out), "w", encoding="utf-8") as fh:
            fh.write("# BRICKYARD 맵 생성기 테스트 결과 (Luau CLI, 순수 로직)\n\n실행 시각: %s\n종료 코드: %d\n\n```\n%s\n```\n" % (stamp, proc.returncode, output.strip()))
    sys.exit(proc.returncode)


if __name__ == "__main__":
    main()
