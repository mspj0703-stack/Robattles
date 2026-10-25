-- Pure Luau CLI tests: authoritative transitions, ordering and missing contracts.
local State=require("../src/client/UI/State")
local count=0
local function test(name,fn) fn(); count+=1; print("PASS UI "..name) end
local function eq(a,b) assert(a==b,"expected "..tostring(b)..", got "..tostring(a)) end
local function snap(t,alive,id) return {t=t,alive=alive,characterId=id or "SWORD"} end
local function new() return State.new(7,4) end
test("initial connecting",function() eq(new():status(0),"Connecting") end)
test("snapshot receipt and stale clock",function() local s=new(); s:snapshot(snap(10,true),11); eq(s:status(13),"Alive"); eq(s:status(15),"Stale") end)
test("old snapshot ignored",function() local s=new(); s:snapshot(snap(10,true),10); eq(s:snapshot(snap(9,false),11),false); eq(s.snap.alive,true) end)
test("death uses server time not receive time",function() local s=new(); s:snapshot(snap(10,true),10); s:feedback({type="Died",playerId=7,time=11},12); eq(s:respawnText(12),"3초 후 부활") end)
test("zero timer does not locally respawn",function() local s=new(); s:snapshot(snap(10,false),10); s:feedback({type="Died",playerId=7,time=10},10); s:snapshot(snap(15,false),15); eq(s:status(15),"Dead"); eq(s:respawnText(15),"서버가 캐릭터를 불러오는 중…") end)
test("death snapshot before death event",function() local s=new(); s:snapshot(snap(10,true),10); s:snapshot(snap(12,false),12); s:feedback({type="Died",playerId=7,time=11},12); eq(s.deathAt,11) end)
test("death deduplicated",function() local s=new(); local e={type="Died",playerId=7,time=10}; s:feedback(e,10); s:feedback(e,11); eq(#s.feed,1) end)
test("stale death cannot kill new life",function() local s=new(); s:snapshot(snap(20,true),20); s:feedback({type="Died",playerId=7,time=15},21); eq(s.deathAt,nil) end)
test("snapshot before life event rejected",function() local s=new(); s:snapshot(snap(10,true),10); s:feedback({type="Died",playerId=7,time=11},11); eq(s:snapshot(snap(10.5,true),12),false) end)
test("respawn clears transients",function() local s=new(); s:feedback({type="Died",playerId=7,time=10},10); s:feedback({type="Respawned",playerId=7,time=14},14); s:snapshot(snap(14.1,true),14.1); eq(s.deathAt,nil); eq(s:status(14.1),"Alive") end)
test("no death timestamp means no fabricated countdown",function() local s=new(); s:snapshot(snap(10,false),10); eq(s:respawnText(10),"서버 부활 정보 대기") end)
test("pending selection not optimistic",function() local s=new(); s:snapshot(snap(10,true),10); s:request("PAINTBALL",10); eq(s.snap.characterId,"SWORD"); eq(s.requested,"PAINTBALL") end)
test("selection confirmed by snapshot",function() local s=new(); s:request("PAINTBALL",10); local x=snap(11,true); x.pendingCharacterId="PAINTBALL"; s:snapshot(x,11); eq(s.requested,nil); eq(s.selectionMessage,"예약 완료 · 다음 리스폰에 적용") end)
test("selection timeout then late confirmation",function() local s=new(); s:request("PAINTBALL",0); s:tick(5); eq(s.requested,nil); local x=snap(7,true); x.pendingCharacterId="PAINTBALL"; s:snapshot(x,7); eq(s.snap.pendingCharacterId,"PAINTBALL") end)
test("selection request single flight",function() local s=new(); eq(s:request("SWORD",0),true); eq(s:request("PAINTBALL",1),false) end)
test("selection rejection",function() local s=new(); s:request("PAINTBALL",0); s:feedback({type="Rejected",remote="SelectCharacter"},1); eq(s.requested,nil) end)
test("server rank retained, never recomputed",function() local s=new(); s:setRows({{id=8,name="Other",kills=9,deaths=0,rank=1},{id=7,name="Me",kills=1,deaths=4,rank=2}}); local rank,k=s:myScore(); eq(rank,2); eq(k,1) end)
test("tied rows share the server rank",function() local s=new(); s:setRows({{id=8,name="A",kills=3,deaths=0,rank=1},{id=7,name="Me",kills=3,deaths=1,rank=1},{id=9,name="C",kills=0,deaths=2,rank=3}}); eq(s:myScore(),1); eq(s.rows[3].rank,3) end)
test("connected flag defaults true and keeps false",function() local s=new(); s:setRows({{id=7,name="Me",kills=0,deaths=0},{id=8,name="Gone",kills=2,deaths=1,connected=false}}); eq(s.rows[1].connected,true); eq(s.rows[2].connected,false) end)
test("player removal",function() local s=new(); s:setRows({{id=7,name="Me",kills=1,deaths=4}}); s:removePlayer(7); eq(#s.rows,0) end)
test("feed bounded and expires",function() local s=new(); for i=1,10 do s:feedback({type="Died",playerId=i,time=i},i) end; eq(#s.feed,5); s:tick(19); eq(#s.feed,0) end)
test("combo only from server swing",function() local s=new(); s:snapshot(snap(10,true),10); s:feedback({type="Swing",playerId=7,swingIndex=3,time=11},11); eq(s.combo.value,3); eq(s:characterLines({combo={text="콤보 3/3"}}),"콤보 3/3") end) -- 표시 문구는 이제 전투 HudModel(서버 스냅샷)에서 온다
test("character swap clears combo",function() local s=new(); s:snapshot(snap(10,true),10); s:feedback({type="Swing",playerId=7,swingIndex=3,time=11},11); s:snapshot(snap(12,true,"PAINTBALL"),12); eq(s.combo,nil) end)
test("dead ignores late swing",function() local s=new(); s:snapshot(snap(10,false),10); s:feedback({type="Swing",playerId=7,swingIndex=2,time=11},11); eq(s.combo,nil) end)
test("unsupported extension ignored",function() local s=new(); local x=snap(10,true); x.ui={version=2,match={phase="Results"}}; s:snapshot(x,10); eq(s:status(10),"Alive") end)
test("optional results then next match",function() local s=new(); local x=snap(10,true); x.ui={version=1,match={phase="Results",results={}}}; s:snapshot(x,10); eq(s:status(10),"Results"); s:snapshot(snap(11,true),11); eq(s:status(11),"Alive") end)
test("fit small windows without clipping",function() for _,size in {{640,360},{800,600},{1280,720},{1920,1080},{360,640}} do for _,pref in {0.75,1,1.25} do local f=State.fit(size[1],size[2],pref); assert(1280*f<=size[1]-24+0.001); assert(720*f<=size[2]-24+0.001) end end end)
test("killer never inferred from damage",function() local s=new(); s:feedback({type="Damaged",targetId=7,attackerId=8,amount=10},10); s:feedback({type="Died",playerId=7,time=11},11); eq(s.killer,nil) end)
test("selecting current character does not confirm stale pending",function() local s=new(); s:request("SWORD",10); local x=snap(11,true); x.pendingCharacterId="PAINTBALL"; s:snapshot(x,11); eq(s.requested,"SWORD"); x=snap(12,true); s:snapshot(x,12); eq(s.requested,nil) end)
local function msnap(t,alive,state,extra)
	local x=snap(t,alive); x.match={phase="ACTIVE",matchId=1,endsAt=t+100,participantCount=2,maxPlayers=12,player={state=state,selected=state~="Menu",characterSelectionAllowed=true,rank=2,kills=1}}
	for k,v in extra or {} do x.match.player[k]=v end
	return x
end
test("Menu (no character) is not Dead",function() local s=new(); s:snapshot(msnap(10,false,"Menu"),10); eq(s:status(10),"Menu") end)
test("selected but not yet spawned is Spawning",function() local s=new(); s:snapshot(msnap(10,false,"Selected"),10); eq(s:status(10),"Spawning") end)
test("server Dead state wins without a Died event",function() local s=new(); s:snapshot(msnap(10,false,"Dead",{respawnAt=14}),10); eq(s:status(10),"Dead"); eq(s:respawnText(11),"3초 후 부활") end)
test("respawn text uses server respawnAt then reports load failure",function() local s=new(); s:snapshot(msnap(15,false,"Dead",{respawnAt=14,spawnStatus="Failed"}),15); eq(s:respawnText(15):find("실패")~=nil,true) end)
test("participating alive is Alive",function() local s=new(); s:snapshot(msnap(10,true,"Participating"),10); eq(s:status(10),"Alive"); eq(s:phase(),"ACTIVE") end)
test("RESULTS phase overrides alive",function() local s=new(); local x=msnap(10,true,"Participating"); x.match.phase="RESULTS"; s:snapshot(x,10); eq(s:status(10),"Results") end)
test("legacy ui.match Results spelling still works",function() local s=new(); local x=snap(10,true); x.ui={version=1,match={phase="Results"}}; s:snapshot(x,10); eq(s:status(10),"Results") end)
test("KillConfirmed names killer and upgrades the Died line",function() local s=new(); s:snapshot(snap(10,true),10); s:feedback({type="Died",playerId=7,time=11},11); s:feedback({type="KillConfirmed",attackerId=8,targetId=7,time=11},11.01); eq(#s.feed,1); eq(s.feed[1].attackerId,8); eq(s.killer.attackerId,8) end)
test("KillConfirmed before Died is not duplicated",function() local s=new(); s:snapshot(snap(10,true),10); s:feedback({type="KillConfirmed",attackerId=8,targetId=7,time=11},11); s:feedback({type="Died",playerId=7,time=11},11.01); eq(#s.feed,1) end)
test("environment death has no killer",function() local s=new(); s:snapshot(snap(10,true),10); s:feedback({type="Died",playerId=7,time=11},11); eq(s.killer,nil); eq(s.feed[1].attackerId,nil) end)
test("character lines come from the combat HUD model",function() local s=new(); eq(s:characterLines({combo={text="콤보 2/3"},passive={text="Duelist 준비"}}),"콤보 2/3  ·  Duelist 준비"); eq(s:characterLines(nil),"서버 상태 대기") end)
print("UI state: "..count.." passed / 0 failed")
