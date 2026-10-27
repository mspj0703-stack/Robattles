#!/usr/bin/env python3
"""SWORD 애니메이션 브랜치 정적 검사 (Python 전용, Luau 실행기 불필요).
1) 금지 영역(서버 전투·Remote 계약·캐릭터 수치·UI·맵·프로젝트 파일)이 기준 커밋 대비 변경되지 않았는지
2) SwordAnimator 가 PreSimulation 에서 Transform 을 쓰고(RenderStepped/BindToRenderStep 로 쓰지 않음)
3) 매 프레임 호출 경로에서 Animation 인스턴스를 만들지 않고(캐시 경유) 연결을 해제하는지 소스 문자열로 확인한다.
사용법: python3 tools/check_anim.py [기준커밋(기본 ac6d48f)]
Git 이력이 없거나 기준 커밋을 확인할 수 없으면 FAIL(종료코드 2)이다."""
import re, subprocess, sys, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# 기본 기준: 애니메이션을 얹기 전의 통합본. 병합 브랜치에서는 "애니메이션이 추가한 변경"만 금지 영역 검사 대상이 된다.
BASE = sys.argv[1] if len(sys.argv) > 1 else "ac6d48f"
FORBIDDEN_PREFIX = ("src/server/", "src/map/", "src/client/UI/", "src/simulation/")
FORBIDDEN_FILES = {"src/shared/RemoteSpec.luau", "src/shared/Data/Characters.luau", "src/shared/Config.luau", "src/shared/Schema.luau",
                   "default.project.json", "integrated.project.json", "brickyard.project.json"}
# 승인된 서버 수정(Blade Storm End 이벤트 시각) 에 한해 아래 3개 파일만 예외. 그 밖의 서버/금지 영역 변경은 계속 FAIL.
APPROVED_SERVER_EDITS = {"src/server/SwordSkills.luau", "src/server/CharacterController.luau", "tests/Sword.spec.luau"}
ALLOWED_SHARED_EDIT = {"src/client/Main.client.luau", "tests/run_all.luau", "docs/STUDIO_TEST_PLAN.md"} | APPROVED_SERVER_EDITS
fails = 0
def check(ok, msg):
    global fails
    print(("PASS " if ok else "FAIL ") + msg)
    if not ok: fails += 1
def git(*a):
    """git 실패(저장소 아님/기준 커밋 없음/비교 오류)는 예외로 올린다 — 빈 출력을 '변경 없음'으로 오인해 PASS 하지 않기 위해."""
    r = subprocess.run(["git", *a], capture_output=True, text=True, cwd=ROOT)
    if r.returncode != 0:
        raise RuntimeError("git %s 실패(rc=%d): %s" % (" ".join(a), r.returncode, r.stderr.strip()))
    return r.stdout
try:
    git("rev-parse", "--is-inside-work-tree")
    git("rev-parse", "--verify", "--quiet", BASE + "^{commit}")
    diff_names = git("diff", "--name-only", BASE).split()
    untracked = git("ls-files", "--others", "--exclude-standard").split()
except (RuntimeError, OSError) as e:
    print("FAIL 변경 검사를 수행할 수 없음(Git 저장소/기준 커밋 확인 실패) — PASS 로 처리하지 않음: %s" % e)
    print("실패 1")
    sys.exit(2)
changed = set(diff_names) | set(untracked)
bad = sorted(f for f in changed if (f in FORBIDDEN_FILES or f.startswith(FORBIDDEN_PREFIX)) and f not in APPROVED_SERVER_EDITS)
check(not bad, "금지 영역 파일 변경 없음 (변경: %s)" % bad)
modified = sorted(set(diff_names) - set(f for f in changed if f.startswith(("src/client/Logic/", "src/client/SwordAnimator", "src/shared/Data/Motion", "src/shared/Data/SwordMotions", "tests/SwordAnim", "docs/SWORD", "tools/check_anim", "src/client/CharacterAnimator", "src/shared/Data/Character", "tests/CharacterAnim", "docs/CHARACTER", "tools/check_char_anim"))))
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
check(main.count("swordAnim") == 4 and main.count("SwordAnimator") == 3 and "swordAnim:resetAll()" in main and "charAnim:resetAll()" in main,
      "Main.client: 기존 SWORD 3훅 + SWORD/4캐릭터 경기 경계 resetAll (swordAnim=%d, SwordAnimator=%d)" % (main.count("swordAnim"), main.count("SwordAnimator")))
check("BACKLOG_SECONDS" in code and "w.backlog" in code, "rig 준비 전 이벤트 보류/재생(유실 방지)")
check('FindFirstChildOfClass("Animator") ~= nil and self:_isAssetDriven' in code, "Animator 가 없으면 에셋 구동으로 판정하지 않음(절차 폴백)")
print("실패 %d" % fails)
sys.exit(1 if fails else 0)
