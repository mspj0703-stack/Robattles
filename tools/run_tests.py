#!/usr/bin/env python3
"""순수 로직 테스트를 Luau CLI로 실행한다.

src/shared 와 tests 를 임시 폴더로 복사하면서 Roblox식 require(script.Parent.X)를
CLI용 문자열 require로 바꾼다. 원본 소스는 수정하지 않는다.
사용법: python3 tools/run_tests.py [--luau /path/to/luau] [--out docs/TEST_RESULTS.md]
"""
import argparse, datetime, os, re, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLI_ENV = (
    'return {\n'
    '  shared = function(path) return require("../shared/" .. path) end,\n'
    '  server = function(path) return require("../server/" .. path) end,\n'
    '  client = function(path) return require("../client/" .. path) end,\n'
    '  map = function(path) return require("../map/" .. path) end,\n'
    '}\n'
)

CLI_LINK = 'return { shared = function(path) return require("../shared/" .. path) end }\n'

PAT_PARENT_LINK = re.compile(r'require\(script\.Parent\.Parent\.Link\)')
PAT_BRACKET = re.compile(r'require\(script\.Parent\["([^"]+)"\]\)')
PAT_DOT = re.compile(r'require\(script\.Parent\.([A-Za-z_][A-Za-z0-9_]*)\)')


def convert(text: str) -> str:
    text = PAT_PARENT_LINK.sub('require("../Link")', text)
    text = PAT_BRACKET.sub(lambda m: 'require("./%s")' % m.group(1), text)
    return PAT_DOT.sub(lambda m: 'require("./%s")' % m.group(1), text)


def copy_tree(src, dst):
    for dirpath, _, files in os.walk(src):
        rel = os.path.relpath(dirpath, src)
        os.makedirs(os.path.join(dst, rel), exist_ok=True)
        for f in files:
            if f.endswith(".luau"):
                with open(os.path.join(dirpath, f), encoding="utf-8") as fh:
                    body = convert(fh.read())
                with open(os.path.join(dst, rel, f), "w", encoding="utf-8") as fh:
                    fh.write(body)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--luau", default=shutil.which("luau") or os.path.join(ROOT, "..", "tools", "luau-bin", "luau"))
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    with tempfile.TemporaryDirectory() as tmp:
        copy_tree(os.path.join(ROOT, "src", "shared"), os.path.join(tmp, "shared"))
        copy_tree(os.path.join(ROOT, "src", "server"), os.path.join(tmp, "server"))
        copy_tree(os.path.join(ROOT, "src", "client"), os.path.join(tmp, "client"))
        # 통합 테스트용: 순수 맵 모듈만 복사(Roblox 전용 모듈은 제외)
        map_pure = {"BrickyardConfig.luau", "MapLayout.luau", "MapValidator.luau", "SpawnAnalysis.luau", "SpawnRegistry.luau", "SpawnRisk.luau"}
        os.makedirs(os.path.join(tmp, "map"), exist_ok=True)
        for f in map_pure:
            with open(os.path.join(ROOT, "src", "map", f), encoding="utf-8") as fh:
                body = convert(fh.read())
            with open(os.path.join(tmp, "map", f), "w", encoding="utf-8") as fh:
                fh.write(body)
        copy_tree(os.path.join(ROOT, "tests"), os.path.join(tmp, "tests"))
        with open(os.path.join(tmp, "client", "Link.luau"), "w", encoding="utf-8") as fh:
            fh.write(CLI_LINK)
        with open(os.path.join(tmp, "server", "Link.luau"), "w", encoding="utf-8") as fh:
            fh.write(CLI_LINK)
        with open(os.path.join(tmp, "tests", "Env.luau"), "w", encoding="utf-8") as fh:
            fh.write(CLI_ENV)
        proc = subprocess.run([args.luau, os.path.join(tmp, "tests", "run_all.luau")],
                              capture_output=True, text=True, cwd=tmp)
    output = proc.stdout + proc.stderr
    print(output)
    if args.out:
        stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
        with open(os.path.join(ROOT, args.out), "w", encoding="utf-8") as fh:
            fh.write("# 자동 테스트 결과 (Luau CLI, 순수 로직)\n\n실행 시각: %s\n종료 코드: %d\n\n```\n%s\n```\n" % (stamp, proc.returncode, output.strip()))
    sys.exit(proc.returncode)


if __name__ == "__main__":
    main()
