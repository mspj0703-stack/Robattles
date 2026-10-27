#!/usr/bin/env python3
"""Offline, source-level require target check for the RoBattles ZIP handoff.

This checks literal require(script.Parent...) and Link.shared("...") references.
It does NOT parse Luau, resolve runtime Roblox Instances or execute modules.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
PARENT_REQUIRE = re.compile(r'\brequire\(\s*script((?:\.Parent)+)((?:\.[A-Za-z_][A-Za-z0-9_]*)+)\s*\)')
SHARED_REQUIRE = re.compile(r'\bLink\.shared\(\s*(["\'])([^"\'\n]+)\1\s*\)')
MAP_REQUIRE = re.compile(r'\brequire\(\s*mapFolder:WaitForChild\(["\']([^"\']+)["\']\)\s*\)')
ANY_REQUIRE = re.compile(r'\brequire\(')


def check(root: Path) -> tuple[list[str], int, int, int]:
    src = root / 'src'
    issues: list[str] = []
    matched_local = matched_shared = matched_map = other_requires = 0
    for source in sorted(src.rglob('*.luau')):
        code = source.read_text(encoding='utf-8')
        # Original project uses only these literal requires under src/.
        local = list(PARENT_REQUIRE.finditer(code))
        shared = list(SHARED_REQUIRE.finditer(code))
        map_deps = list(MAP_REQUIRE.finditer(code))
        matched_local += len(local)
        matched_shared += len(shared)
        matched_map += len(map_deps)
        unknown = len(ANY_REQUIRE.findall(code)) - len(local) - len(map_deps)
        if unknown > 0:
            other_requires += unknown
            # This is a scope limitation, not a proof of a broken require.
        for m in local:
            parent_count = m.group(1).count('.Parent')
            nodes = m.group(2).lstrip('.').split('.')
            base = source
            for _ in range(parent_count):
                base = base.parent
            target = base.joinpath(*nodes).with_suffix('.luau')
            if not target.is_file():
                line = code.count('\n', 0, m.start()) + 1
                issues.append(f'{source.relative_to(root)}:{line}: missing local module {target.relative_to(root) if target.is_relative_to(root) else target}')
        for m in map_deps:
            target = src.joinpath("map", m.group(1)).with_suffix(".luau")
            if not target.is_file():
                line = code.count("\n", 0, m.start()) + 1
                issues.append(f"{source.relative_to(root)}:{line}: missing dynamic map module {m.group(1)!r}")
        for m in shared:
            path = m.group(2)
            nodes = path.split('/')
            if any(not n or n in ('.', '..') for n in nodes):
                issues.append(f'{source.relative_to(root)}: invalid shared path {path!r}')
                continue
            target = src.joinpath('shared', *nodes).with_suffix('.luau')
            if not target.is_file():
                line = code.count('\n', 0, m.start()) + 1
                issues.append(f'{source.relative_to(root)}:{line}: missing shared module {path!r}')
    return issues, matched_local, matched_shared, matched_map, other_requires


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root', type=Path, default=ROOT, help='RoBattles project root')
    args = ap.parse_args()
    issues, local, shared, maps, dynamic = check(args.root)
    print(f'[requires] literal local={local}, shared={shared}, map={maps}, other/dynamic require={dynamic}')
    if issues:
        for issue in issues:
            print('FAIL', issue)
        return 1
    print('PASS: all inspected literal require targets exist (not a runtime test)')
    if dynamic:
        print(f'NOTE: {dynamic} other require calls were not validated')
    return 0


if __name__ == '__main__':
    sys.exit(main())
