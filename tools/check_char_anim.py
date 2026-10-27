#!/usr/bin/env python3
"""캐릭터 애니메이션(PAINTBALL/SLINGSHOT …) 브랜치 정적 검사 (Python 전용, Luau 실행기 불필요).
1) 금지 영역(서버 전투·Remote 계약·캐릭터 수치·UI·맵·프로젝트 파일)이 기준 커밋 대비 변경되지 않았는지
2) CharacterAnimator 가 PreSimulation 에서만 Transform 을 쓰고, Animation 인스턴스를 캐시 경유로만 만들며, 연결을 해제하는지
3) Main.client 변경이 허용된 훅뿐인지 / SWORD 모듈과 겹치지 않는지 / 모션 데이터에 SWORD 가 섞이지 않았는지
사용법: python3 tools/check_char_anim.py [기준커밋(기본 a598bcb)]   Git 확인 실패는 FAIL(종료코드 2)."""
import subprocess, sys, os, re
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = sys.argv[1] if len(sys.argv) > 1 else "a598bcb"
FORBIDDEN_PREFIX = ("src/server/", "src/map/", "src/client/UI/", "src/simulation/")
FORBIDDEN_FILES = {"src/shared/RemoteSpec.luau", "src/shared/Data/Characters.luau", "src/shared/Config.luau", "src/shared/Schema.luau",
                   "default.project.json", "integrated.project.json", "brickyard.project.json"}
NEW_ALLOWED = ("src/client/CharacterAnimator.luau", "src/client/Logic/CharacterAnimState.luau", "src/client/Logic/GunLocomotion.luau",
               "src/client/Logic/TrackBook.luau", "src/client/Logic/MatchResetModel.luau", "tests/AnimFiveChars.spec.luau",
               "src/shared/Data/CharacterMotions.luau", "src/shared/Data/CharacterMotionRegistry.luau",
               "tests/CharacterAnim.spec.luau", "docs/CHARACTER_ANIMATION.md", "tools/check_char_anim.py")
# 기존 파일 수정 허용 목록: 훅 연결(Main.client), 테스트 등록(run_all), SwordAnimState 의 baseSampler 선택 옵션(기본 동작 불변)
MODIFIED_ALLOWED = {"src/client/Main.client.luau", "src/client/SwordAnimator.luau", "tests/run_all.luau", "src/client/Logic/SwordAnimState.luau", "tools/check_anim.py"}
fails = 0
def check(ok, msg):
    global fails
    print(("PASS " if ok else "FAIL ") + msg)
    if not ok: fails += 1
def git(*a):
    r = subprocess.run(["git", *a], capture_output=True, text=True, cwd=ROOT)
    if r.returncode != 0:
        raise RuntimeError("git %s 실패(rc=%d): %s" % (" ".join(a), r.returncode, r.stderr.strip()))
    return r.stdout
def read(p): return open(os.path.join(ROOT, p), encoding="utf-8").read()
def strip(src): return "\n".join(l for l in src.splitlines() if not l.strip().startswith("--"))
try:
    git("rev-parse", "--is-inside-work-tree")
    git("rev-parse", "--verify", "--quiet", BASE + "^{commit}")
    diff_names = git("diff", "--name-only", BASE).split()
    untracked = git("ls-files", "--others", "--exclude-standard").split()
    swordstate_diff = git("diff", BASE, "--", "src/client/Logic/SwordAnimState.luau")
    main_diff = git("diff", BASE, "--", "src/client/Main.client.luau")
except (RuntimeError, OSError) as e:
    print("FAIL 변경 검사를 수행할 수 없음 — PASS 로 처리하지 않음: %s" % e)
    print("실패 1"); sys.exit(2)
changed = set(diff_names) | set(untracked)
bad = sorted(f for f in changed if f in FORBIDDEN_FILES or f.startswith(FORBIDDEN_PREFIX))
check(not bad, "금지 영역 파일 변경 없음 (변경: %s)" % bad)
# 이미 커밋된 신규 파일은 diff_names 에 나오므로, 기준 커밋에 없던 파일 = 신규
base_files = set(git("ls-tree", "-r", "--name-only", BASE).split())
modified = sorted(f for f in changed if f in base_files)
new = sorted(f for f in changed if f not in base_files)
check(set(modified) <= MODIFIED_ALLOWED, "기존 파일 수정은 허용 목록만: %s" % modified)
check(all(f in NEW_ALLOWED for f in new), "신규 파일은 허용 목록만: %s" % [f for f in new if f not in NEW_ALLOWED])
added = [l for l in swordstate_diff.splitlines() if l.startswith("+") and not l.startswith("+++")]
removed = [l for l in swordstate_diff.splitlines() if l.startswith("-") and not l.startswith("---")]
check(len(added) <= 3 and len(removed) <= 2 and all("baseSampler" in l for l in added) and all("LocomotionPose.sample" in l for l in removed),
      "SwordAnimState 변경은 baseSampler 옵션 훅뿐 (+%d/-%d)" % (len(added), len(removed)))
main_added = [l[1:] for l in main_diff.splitlines() if l.startswith("+") and not l.startswith("+++")]
main_removed = [l for l in main_diff.splitlines() if l.startswith("-") and not l.startswith("---")]
check(all(("charAnim" in l or "swordAnim:resetAll()" in l or "CharacterAnimator" in l or "MatchResetModel" in l or "lastAnimMatch" in l or l.strip() in ("pcall(function()", "end)", "end", "local m = MatchResetModel.matchOf(snap)")) for l in main_added) and len(main_added) <= 18 and "swordAnim:resetAll()" in "\n".join(main_added),
      "Main.client 변경은 4캐릭터 훅 + SWORD resetAll 로 제한 (추가 %d줄)" % len(main_added))
check(len(main_removed) <= 1 and all("swordAnim:destroy()" in l for l in main_removed), "Main.client 에서 지운 줄은 destroy 줄 수정 1곳뿐 (%d)" % len(main_removed))
sword_diff = git("diff", BASE, "--", "src/client/SwordAnimator.luau")
sword_added = [l[1:] for l in sword_diff.splitlines() if l.startswith("+") and not l.startswith("+++")]
sword_removed = [l for l in sword_diff.splitlines() if l.startswith("-") and not l.startswith("---")]
check(not sword_removed and "function SwordAnimator:resetAll()" in "\n".join(sword_added) and "w.backlog = {}" in "\n".join(sword_added) and all(x in "\n".join(sword_added) for x in ("rig.state:reset()", "stopTracks(rig)", "resetJoints(rig)")),
      "SWORD 변경은 경기 경계 resetAll 추가뿐(기존 라인 삭제 없음)")
code = strip(read("src/client/CharacterAnimator.luau"))
check("RunService.PreSimulation:Connect" in code, "Transform 적용을 PreSimulation 에 연결")
check("BindToRenderStep" not in code and "RenderStepped" not in code and "Heartbeat" not in code, "RenderStepped/Heartbeat 로 Transform 을 쓰지 않음")
check(code.count('Instance.new("Animation")') == 1 and "_resolveAnimation" in code.split('Instance.new("Animation")')[0].split("function CharacterAnimator")[-1],
      "Animation 인스턴스는 캐시되는 _resolveAnimation 안에서만 생성")
check("AnimationCache.new" in code and "self._anims:has(" in code, "에셋 구동 판정은 AnimationCache 경유")
check("_watched[model]" in code and "if self._bound[pl]" in code, "캐릭터/플레이어 중복 감시 방지")
check("disconnectAll(w.conns)" in code and "disconnectAll(rig.conns)" in code and "PlayerRemoving" in code, "캐릭터 제거 시 연결 해제")
check("RigStatus.classify" in code and "DescendantAdded" in code, "관절 미준비 시 재시도(DescendantAdded)")
check("BACKLOG_SECONDS" in code and "w.backlog" in code, "rig 준비 전 이벤트 보류/재생")
check('FindFirstChildOfClass("Animator") ~= nil and self:_isAssetDriven' in code, "Animator 없으면 절차 폴백")
check('cid ~= "SWORD"' in code, "SWORD 모델은 건드리지 않음(SwordAnimator 와 관절 충돌 없음)")
check('"SWORD"' not in strip(read("src/shared/Data/CharacterMotions.luau")), "CharacterMotions 에 SWORD 데이터 없음")
sw = strip(read("src/client/SwordAnimator.luau"))
check('== "SWORD"' in sw, "SwordAnimator 는 SWORD 전용 유지")
# ── 모션 데이터 정적 검사(CharacterMotionRegistry.validate 의 핵심을 Python 으로 재구현 — Luau validate 를 대체하지 않는다) ──
def parse_motions(src):
    chars, cur_c, cur_m, in_motions = {}, None, None, False
    for line in src.splitlines():
        m = re.match(r"^M\.([A-Z]+) = \{", line)
        if m: cur_c = m.group(1); chars[cur_c] = {}; cur_m = None; continue
        if re.match(r"^\t(Groups|Locomotion) = \{", line): cur_m = None; in_motions = False; continue
        if re.match(r"^\tMotions = \{", line): in_motions = True; continue
        m = re.match(r"^\t\t(\w+) = \{", line)
        if m and cur_c and in_motions: cur_m = m.group(1); chars[cur_c][cur_m] = {"keys": [], "line": line}; continue
        if cur_c and cur_m and cur_m in chars[cur_c]:
            d = chars[cur_c][cur_m]
            if True:
                for k in ("priority", "duration", "impact", "maxDuration", "commit", "tickExtend"):
                    mm = re.search(r"\b%s = ([0-9.]+)" % k, line)
                    if mm and not re.match(r"^\t\t\t\t\{ t =", line) and k not in d: d[k] = float(mm.group(1))
                if re.search(r"\bhold = true", line): d["hold"] = True
                mm = re.search(r'\bnext = "(\w+)"', line)
                if mm: d["next"] = mm.group(1)
                mm = re.match(r"^\t\t\t\t\{ t = ([0-9.]+)", line)
                if mm: d["keys"].append(float(mm.group(1)))
    return chars
motion_src = read("src/shared/Data/CharacterMotions.luau")
parsed = parse_motions(motion_src)
check(set(parsed) == {"PAINTBALL", "SLINGSHOT", "SUPERBALL", "TIMEBOMB"}, "모션 데이터 캐릭터: %s" % sorted(parsed))
total_motions = 0
for cid, motions in parsed.items():
    for mid, d in motions.items():
        if "duration" not in d: continue  # Locomotion 등 모션이 아닌 블록
        total_motions += 1
        keys, dur = d["keys"], d["duration"]
        ok = len(keys) >= 2 and keys == sorted(keys) and keys[-1] <= dur + 1e-6 and keys[0] >= 0
        ok = ok and ("impact" not in d or any(abs(k - d["impact"]) < 1e-6 for k in keys))
        ok = ok and (not d.get("hold") or d.get("maxDuration", 0) >= dur)
        ok = ok and ("next" not in d or d["next"] in motions)
        ok = ok and 1 <= d.get("priority", 0) <= 9
        check(ok, "모션 데이터 %s/%s (키 %s, 길이 %s, impact %s)" % (cid, mid, keys, dur, d.get("impact")))
check(total_motions == 36, "검사한 모션 수 %d (기대 36개: 10+8+11+7)" % total_motions)
# ── 이벤트 계약 교차 검사: 상태기계가 기다리는 cue/defId/phase 가 실제 서버 소스에 존재하는가(서버는 읽기만 한다) ──
state_src = strip(read("src/client/Logic/CharacterAnimState.luau"))
server_src = "".join(read("src/server/" + f) for f in sorted(os.listdir(os.path.join(ROOT, "src/server"))) if f.endswith(".luau"))
cues = sorted(set(re.findall(r'cue == "([a-z.]+)"', state_src)) | set(re.findall(r'cue == "([a-z.]+)" and', state_src)))
cues += ["paint.ult.windup", "ball.cyclone.start"]  # phase 로 분기하는 궁극기 cue 도 서버 존재 확인
missing_cues = [c for c in sorted(set(cues)) if 'cue = "%s"' % c not in server_src and ('"%s"' % c) not in server_src]
check(not missing_cues and len(cues) >= 20, "상태기계가 쓰는 cue 가 서버에 모두 존재(%d개, 누락 %s)" % (len(set(cues)), missing_cues))
for phase_cue in ('cue = "paint.ult.windup"', 'cue = "ball.cyclone.start"', 'cue = "ball.cyclone.shot"', 'cue = "sling.ult.fire"', 'cue = "bomb.bigbang"'):
    check(phase_cue in server_src, "서버 이벤트 존재: " + phase_cue)
check('id = "paint_shot"' in read("src/shared/Data/Characters.luau") and 'defId == "paint_shot"' in state_src, "PaintFire 의 defId 가 Characters 와 일치")
for phase in ("Windup", "Tick", "End", "Start", "Shot", "Fire", "Throw"):
    check('phase = "%s"' % phase in server_src, "서버가 phase=%s 를 실제로 보냄" % phase)
check(state_src.count("_storm = {") == 0 and state_src.count("newStorm(now") >= 3 and "lastActivity" in state_src,
      "궁극기 잠금 테이블은 newStorm(lastActivity 포함)으로만 생성 — GPT Blade Storm Tick 패치 호환")
check("TrackBook" in code and "rig.book:apply" in code and "rig.tracks" not in code, "에셋 트랙 재생/정지는 TrackBook 경유(중복 방지)")
main_src = read("src/client/Main.client.luau")
check("charAnim:resetAll()" in main_src and "MatchResetModel.shouldReset" in main_src and "charAnim:onLocalRelease()" in main_src, "Main.client: resetAll/로컬 해제 훅 연결")
check("active ~= nil and not active._destroyed" in code and "active = self" in code, "CharacterAnimator 중복 생성 방지(싱글턴 가드)")
# ── 휴리스틱 구문 점검: 문자열/주석을 지운 뒤 블록 열기/닫기 개수가 맞는지(컴파일이 아니다 — Luau 실행기 대체 불가) ──
import re
def strip_luau(src):
    src = re.sub(r"--\[(=*)\[.*?\]\1\]", "", src, flags=re.S)
    src = re.sub(r"--[^\n]*", "", src)
    src = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', src)
    src = re.sub(r"'(?:\\.|[^'\\\n])*'", "''", src)
    return src
def balance(src):
    toks = re.findall(r"[A-Za-z_][A-Za-z_0-9]*", strip_luau(src))
    opens = closes = 0
    prev = None
    for t in toks:
        if t in ("function", "do", "repeat"): opens += 1
        elif t == "if" and prev != "else": opens += 1  # elseif 는 별도 토큰이라 영향 없음
        elif t in ("end", "until"): closes += 1
        prev = t
    return opens, closes
luau_files = sorted(f for f in changed if f.endswith(".luau") and os.path.exists(os.path.join(ROOT, f)))
for f in luau_files + ["src/client/SwordAnimator.luau"]:
    o, c = balance(read(f))
    check(o == c, "블록 열기/닫기 균형(휴리스틱) %s: 열기 %d / 닫기 %d" % (f, o, c))
print("실패 %d" % fails)
sys.exit(1 if fails else 0)
