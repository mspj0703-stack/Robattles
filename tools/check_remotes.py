#!/usr/bin/env python3
"""RemoteEvent 정적 점검(Studio 미실행): RemoteSpec 정의 ↔ 서버 생성 ↔ ServerRouter 연결 ↔ 클라이언트 사용 이름 일치."""
import os, re, sys
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rd = lambda p: open(os.path.join(R, p), encoding="utf-8").read()

spec = rd("src/shared/RemoteSpec.luau")
body = spec[spec.index("RemoteSpec.Remotes = {"):spec.index("function RemoteSpec.validate")]
c2s = set(re.findall(r"^\t([A-Za-z]+) = Schema", body, re.M))
server = rd("src/server/Main.server.luau")
s2c = set(re.findall(r'(?:feedback|stateRemote|scoreRemote)\.Name = "([A-Za-z]+)"', server))
created = c2s | s2c
router = rd("src/server/ServerRouter.luau")
routed = set(re.findall(r'remoteName == "([A-Za-z]+)"', router))
client = rd("src/client/Main.client.luau")
used = set(re.findall(r"remotes\.([A-Z][A-Za-z]+)", client)) | set(re.findall(r'WaitForChild\("([A-Z][A-Za-z]+)"\)', client)) - {"RoBattles", "Remotes"}
dyn = set(re.findall(r'remote = "([A-Za-z]+)"', rd("src/client/Logic/InputModel.luau"))) if os.path.exists(os.path.join(R, "src/client/Logic/InputModel.luau")) else set()
bad = 0
def chk(ok, msg):
    global bad
    print(("PASS " if ok else "FAIL ") + msg); bad += 0 if ok else 1
chk(bool(c2s), "RemoteSpec 클라→서버 정의: %s" % sorted(c2s))
chk(s2c == {"Feedback", "State", "Scoreboard"}, "서버→클라 RemoteEvent 생성: %s" % sorted(s2c))
chk(c2s <= routed, "ServerRouter 가 모든 클라→서버 Remote 를 처리 (누락: %s)" % sorted(c2s - routed))
chk(routed <= c2s, "ServerRouter 에 정의 없는 Remote 없음 (초과: %s)" % sorted(routed - c2s))
chk(used <= created, "클라이언트가 쓰는 Remote 는 모두 서버가 생성 (없음: %s)" % sorted(used - created))
chk(dyn <= c2s, "클라이언트 동적 Remote 이름(cmd.remote)이 정의에 있음 (없음: %s)" % sorted(dyn - c2s))
chk('Name = "Remotes"' in server and "ReplicatedStorage" in server, "서버가 ReplicatedStorage.RoBattles.Remotes 를 생성")
chk('WaitForChild("Remotes")' in client, "클라이언트가 Remotes 를 WaitForChild")
sys.exit(1 if bad else 0)
