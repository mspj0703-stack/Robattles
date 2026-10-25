--!strict
-- 임시 전투 연출 카탈로그. 최종 아트가 아니다: 아래 `style` 은 EffectPlayer 가 코드로 만드는 임시 도형이다.
-- 교체 방법(코드 수정 불필요): ReplicatedStorage.RoBattles.Assets.Effects 에 같은 cue 이름(예: "sword.slash")의 Model/Part/ParticleEmitter 를 넣으면
-- 그것을 복제해 쓴다. 사운드는 Sounds 의 id 만 바꾸면 된다. 무기는 Assets.Weapons.<CharacterId> (WeaponModels 참고).
-- ASSUMPTION A56: 사운드 id 는 Roblox 클라이언트 내장(rbxasset://) 임시 파일 이름이며 Studio 에서 재생 여부를 확인하지 않았다(무음으로 실패할 수 있음).

local EffectCatalog = {}

EffectCatalog.Sounds = {
	swing = { id = "rbxasset://sounds/swordslash.wav", volume = 0.6 },
	parry = { id = "rbxasset://sounds/unsheath.wav", volume = 0.7 },
	parry_hit = { id = "rbxasset://sounds/swordlunge.wav", volume = 0.8 },
	hit = { id = "rbxasset://sounds/clickfast.wav", volume = 0.8 },
	paint_fire = { id = "rbxasset://sounds/button.wav", volume = 0.35 },
	reload = { id = "rbxasset://sounds/switch.wav", volume = 0.6 },
	dodge = { id = "rbxasset://sounds/snap.mp3", volume = 0.4 },
}

-- cue 이름 → 정의. style: Arc | Ring | Burst | Highlight | Afterimage | Muzzle | Projectile | Splat | Poof
EffectCatalog.Cues = {
	["sword.slash"] = { style = "Arc", color = { 235, 240, 255 }, size = 7, lifetime = 0.18, sound = "swing" },
	["sword.slash3"] = { style = "Arc", color = { 255, 220, 140 }, size = 9, lifetime = 0.25, sound = "swing" },
	["skill.triple1"] = { style = "Arc", color = { 150, 220, 255 }, size = 8, lifetime = 0.2, sound = "swing" },
	["skill.triple2"] = { style = "Arc", color = { 110, 190, 255 }, size = 9, lifetime = 0.22, sound = "swing" },
	["skill.triple3"] = { style = "Arc", color = { 255, 170, 90 }, size = 11, lifetime = 0.3, sound = "swing" },
	["skill.lunge.charge"] = { style = "Ring", color = { 255, 210, 120 }, size = 4, lifetime = 0.5, sound = "parry" },
	["skill.lunge.dash"] = { style = "Afterimage", color = { 255, 200, 90 }, size = 0, lifetime = 0.4, count = 5, sound = "dodge" },
	["skill.bladewave"] = { style = "Arc", color = { 120, 230, 255 }, size = 14, lifetime = 0.35, sound = "swing" },
	["skill.storm.start"] = { style = "Ring", color = { 255, 255, 255 }, size = 10, lifetime = 0.4, sound = "parry" },
	["skill.storm.tick"] = { style = "Ring", color = { 190, 230, 255 }, size = 12, lifetime = 0.25, sound = "swing" },
	["skill.storm.finish"] = { style = "Burst", color = { 255, 255, 200 }, size = 22, lifetime = 0.5, sound = "parry_hit" },
	["duelist.proc"] = { style = "Burst", color = { 255, 215, 70 }, size = 7, lifetime = 0.35, sound = "parry_hit" },
	["parry.start"] = { style = "Ring", color = { 110, 175, 255 }, size = 5, lifetime = 0.4, sound = "parry" },
	["parry.success"] = { style = "Burst", color = { 255, 230, 110 }, size = 6, lifetime = 0.3, sound = "parry_hit" },
	["parry.blocked"] = { style = "Burst", color = { 255, 120, 80 }, size = 4, lifetime = 0.25 },
	["hit.impact"] = { style = "Burst", color = { 255, 90, 90 }, size = 3, lifetime = 0.2, sound = "hit" },
	["hit.flash"] = { style = "Highlight", color = { 255, 255, 255 }, size = 0, lifetime = 0.12 },
	["dodge.afterimage"] = { style = "Afterimage", color = { 120, 200, 255 }, size = 0, lifetime = 0.35, count = 4, sound = "dodge" },
	["paint.fire"] = { style = "Muzzle", color = { 255, 140, 40 }, size = 1.2, lifetime = 0.08, sound = "paint_fire" },
	["paint.projectile"] = { style = "Projectile", color = { 255, 140, 40 }, size = 0.6, lifetime = 2 },
	["paint.splat"] = { style = "Splat", color = { 255, 140, 40 }, size = 2.2, lifetime = 1.5 },
	["reload.start"] = { style = "Ring", color = { 200, 200, 200 }, size = 2, lifetime = 0.3, sound = "reload" },
	["reload.done"] = { style = "Burst", color = { 120, 255, 140 }, size = 2, lifetime = 0.2, sound = "reload" },
	["death.poof"] = { style = "Poof", color = { 200, 200, 200 }, size = 6, lifetime = 0.6 },
	["respawn.flash"] = { style = "Ring", color = { 255, 255, 255 }, size = 6, lifetime = 0.5 },
}

-- 임시 무기 모델 규격(WeaponModels 가 코드로 만든다). attach: 붙일 손 부품 후보(R15 → R6 순)
EffectCatalog.Weapons = {
	SWORD = { kind = "Sword", color = { 200, 205, 215 }, handleColor = { 90, 60, 40 }, length = 4.2, attach = { "RightHand", "Right Arm" } },
	PAINTBALL = { kind = "Gun", color = { 60, 60, 70 }, accent = { 255, 140, 40 }, length = 2.4, attach = { "RightHand", "Right Arm" } },
}

return EffectCatalog
