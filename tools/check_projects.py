#!/usr/bin/env python3
"""Rojo 프로젝트 파일 정적 점검(Rojo를 실행하지 않음): JSON 유효성, $path 존재, 마운트 이름 충돌.
Rojo 실제 동기화/Studio 호환성은 검증하지 않는다."""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = ["default.project.json", "brickyard.project.json", "integrated.project.json"]


def walk(node, path, out):
    if isinstance(node, dict):
        if "$path" in node:
            out.append((path, node["$path"]))
        for k, v in node.items():
            if not k.startswith("$"):
                walk(v, path + "/" + k, out)


def main():
    bad = 0
    for f in FILES:
        fp = os.path.join(ROOT, f)
        try:
            data = json.load(open(fp, encoding="utf-8"))
        except Exception as e:
            print("FAIL %s: JSON 오류 %s" % (f, e)); bad += 1; continue
        mounts = []
        walk(data.get("tree", {}), "", mounts)
        for inst, p in mounts:
            ok = os.path.isdir(os.path.join(ROOT, p)) or os.path.isfile(os.path.join(ROOT, p))
            print("%s %s: %s -> %s" % ("PASS" if ok else "FAIL", f, inst, p))
            bad += 0 if ok else 1
        paths = [m[0] for m in mounts]
        if len(paths) != len(set(paths)):
            print("FAIL %s: 마운트 위치 중복" % f); bad += 1
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
