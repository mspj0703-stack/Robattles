#!/usr/bin/env python3
"""SWORD 애니메이션 브랜치 정적 검사 (Python 전용, Luau 실행기 불필요).
1) 금지 영역(서버 전투·Remote 계약·캐릭터 수치·UI·맵·프로젝트 파일)이 기준 커밋 대비 변경되지 않았는지
2) SwordAnimator 가 PreSimulation 에서 Transform 을 쓰고(RenderStepped/BindToRenderStep 로 쓰지 않음)
3) 매 프레임 호출 경로에서 Animation 인스턴스를 만들지 않고(캐시 경유) 연결을 해제하는지 소스 문자열로 확인한다.
사용법: python3 tools/check_anim.py [기준커밋(기본 e5ae619)]"""
import re, subprocess, sys, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = sys.argv[1] if len(sys.argv) > 1 else "e5ae619"
FORBIDDEN_PREFIX = ("src/server/", "src/map/", "src/client/UI/", "src/simulation/")
FORBIDDEN_FILES = {"src/shared/RemoteSpec.luau", "src/shared/Data/Characters.luau", "src/shared/Config.luau", "src/shared/Schema.luau",
                   "default.project.json", "integrated.project.json", "brickyard.project.json"}
ALLOWED_SHARED_EDIT = {"src/client/Main.client.luau", "tests/run_all.luau"}
fails = 0
def check(ok, msg):
    global fails
    print(("PASS " if ok else "FAIL ") + msg)
    if not ok: fails += 1
def git(*a):
    return subprocess.run(["git", *a], capture_output=True, text=True, cwd=ROOT).stdout
changed = set(git("diff", "--name-only", BASE).split()) | set(git("ls-files", "--others", "--exclude-standard").split())
bad = sorted(f for f in changed if f in FORBIDDEN_FILES or f.startswith(FORBIDDEN_PREFIX))
check(not bad, "금지 영역 파일 변경 없음 (변경: %s)" % bad)
modified = sorted(set(git("diff", "--name-only", BASE).split()) - set(f for f in changed if f.startswith(("src/client/Logic/", "src/client/SwordAnimator", "src/shared/Data/Motion", "src/shared/Data/SwordMotions", "tests/SwordAnim", "docs/SWORD", "tools/check_anim"))))
check(set(modified) <= ALLOWED_SHARED_EDIT, "기존 파일 수정은 허용 목록만: %s" % modified)
src = open(os.path.join(ROOT, "src/client/SwordAnimator.luau"), encoding="utf-8").read()
code = "\n".join(l for l in src.splitlines() if not l.strip().startswith("--"))
check("RunService.PreSimulation:Connect" in code, "Transform 적용을 PreSimulation 에 연결")
check("BindToRenderStep" not in code and "RenderStepped" not in code and "Heartbeat" not in code, "RenderStep/RenderStepped/Heartbeat 로 Transform 을 쓰지 않음")
check(code.count('Instance.new("Animation")') == 1 and "_resolveAnimation" in code.split('Instance.new("Animation")')[0].split("function SwordAnimator")[-1],
      "Animation 인스턴스는 캐시되는 _resolveAnimation 안에서만 생성")
check("AnimationCache.new" in code and "self._anims:has(id)" in code, "에셋 구동 판정은 AnimationCache 경유")
check("_watched[model]" in code and "if self._bound[pl]" in code, "캐릭터/플레이어 중복 감시 방지")
check("disconnectAll(w.conns)" in code and "disconnectAll(rig.conns)" in code and "PlayerRemoving" in code, "캐릭터 제거 시 연결 해제")
check("RigStatus.classify" in code and "DescendantAdded" in code, "관절 미준비 시 재시도(DescendantAdded)")
main = open(os.path.join(ROOT, "src/client/Main.client.luau"), encoding="utf-8").read()
check(main.count("swordAnim") == 3 and main.count("SwordAnimator") == 3, "Main.client 변경은 require 1 + swordAnim 3곳(생성/Feedback/destroy)뿐 (swordAnim=%d, SwordAnimator=%d)" % (main.count("swordAnim"), main.count("SwordAnimator")))
print("실패 %d" % fails)
sys.exit(1 if fails else 0)
