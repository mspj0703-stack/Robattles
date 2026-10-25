--!nonstrict
-- 임시 전투 연출 큐 변환(순수 로직) 테스트. 실제 렌더링(EffectPlayer/WeaponModels)은 Roblox 전용이라 Studio 검증 대상이다.
local T = require(script.Parent.TestRunner)
local Env = require(script.Parent.Env)
local Effects = Env.client("Logic/EffectsModel")
local Catalog = Env.shared("Data/EffectCatalog")
local Characters = Env.shared("Data/Characters")

local function cues(list, name)
	local out = {}
	for _, c in list do if c.cue == name then table.insert(out, c) end end
	return out
end

T.describe("EffectsModel: 이벤트 → 연출 큐", function()
	T.it("Swing → sword.slash (내 것 mine=true)", function()
		local r = Effects.translate({ type = "Swing", playerId = 1, hits = {} }, 1)
		T.expectEqual(#cues(r, "sword.slash"), 1)
		T.expect(r[1].mine)
		T.expect(not Effects.translate({ type = "Swing", playerId = 2, hits = {} }, 1)[1].mine)
	end)
	T.it("패링 시작/성공/반격 표시", function()
		T.expectEqual(#cues(Effects.translate({ type = "Parry", playerId = 1 }, 1), "parry.start"), 1)
		local r = Effects.translate({ type = "ParrySuccess", playerId = 1, attackerId = 2, countered = true }, 1)
		T.expectEqual(#cues(r, "parry.success"), 1)
		T.expectEqual(#cues(r, "parry.blocked"), 1)
		T.expect(cues(r, "parry.success")[1].countered)
	end)
	T.it("Damaged → 피격 번쩍임 + 충격 연출, 공격자 관점 mine 구분", function()
		local r = Effects.translate({ type = "Damaged", attackerId = 1, targetId = 2, amount = 14 }, 1)
		T.expectEqual(#cues(r, "hit.flash"), 1)
		T.expectEqual(#cues(r, "hit.impact"), 1)
		T.expect(cues(r, "hit.impact")[1].mine)
		T.expect(not cues(r, "hit.flash")[1].mine)
	end)
	T.it("Dodge → 잔상(방향·서버 확정 거리·시작 위치 전달)", function()
		local r = Effects.translate({ type = "Dodge", playerId = 1, info = { direction = { X = 1, Y = 0, Z = 0 }, distance = 5, origin = { X = 0, Y = 3, Z = 0 } } }, 1)
		local c = cues(r, "dodge.afterimage")[1]
		T.expectEqual(c.distance, 5)
		T.expectEqual(c.origin.Y, 3)
	end)
	T.it("PAINTBALL 발사(Spawned Linear) → 발사 연출 + 시각용 탄, 다른 타입은 무시", function()
		local ev = { type = "Spawned", projectileType = "Linear", ownerId = 1, projectileId = 7, pos = { X = 0, Y = 5, Z = 0 }, dir = { X = 0, Y = 0, Z = -1 }, speed = 220, radius = 0.3, lifetime = 2, time = 10 }
		local r = Effects.translate(ev, 1)
		T.expectEqual(#cues(r, "paint.fire"), 1)
		T.expectEqual(#cues(r, "paint.projectile"), 1)
		ev.projectileType = "Beam"
		T.expectEqual(#Effects.translate(ev, 1), 0)
	end)
	T.it("투사체 종료 → projectile.end, 명중/벽이면 얼룩(splat)", function()
		local r = Effects.translate({ type = "Ended", projectileId = 7, reason = "World", pos = { X = 1, Y = 2, Z = 3 } }, 1)
		T.expectEqual(#cues(r, "projectile.end"), 1)
		T.expectEqual(#cues(r, "paint.splat"), 1)
		local r2 = Effects.translate({ type = "Ended", projectileId = 7, reason = "Range", pos = { X = 1, Y = 2, Z = 3 } }, 1)
		T.expectEqual(#cues(r2, "paint.splat"), 0)
	end)
	T.it("재장전 완료/사망/리스폰 큐", function()
		T.expectEqual(#cues(Effects.translate({ type = "Reloaded", playerId = 1 }, 1), "reload.done"), 1)
		T.expectEqual(#cues(Effects.translate({ type = "Died", playerId = 2 }, 1), "death.poof"), 1)
		T.expectEqual(#cues(Effects.translate({ type = "Respawned", playerId = 2 }, 1), "respawn.flash"), 1)
	end)
	T.it("잘못된 입력은 빈 목록(예외 없음)", function()
		T.expectEqual(#Effects.translate(nil, 1), 0)
		T.expectEqual(#Effects.translate("x", 1), 0)
		T.expectEqual(#Effects.translate({ type = 5 }, 1), 0)
		T.expectEqual(#Effects.translate({ type = "Unknown" }, 1), 0)
		T.expectEqual(#Effects.translate({ type = "Spawned", projectileType = "Linear" }, 1), 0)
	end)
end)

T.describe("EffectsModel: 재장전 에지·시각 탄·잔상", function()
	T.it("재장전 시작 상승 에지에서만 true", function()
		local idle = { t = 1, ammo = { cur = 10, reloadingUntil = 0 } }
		local reloading = { t = 2, ammo = { cur = 0, reloadingUntil = 3.8 } }
		T.expect(Effects.reloadStarted(idle, reloading, 2))
		T.expect(not Effects.reloadStarted(reloading, { t = 2.1, ammo = { reloadingUntil = 3.8 } }, 2.1))
		T.expect(not Effects.reloadStarted(idle, idle, 1))
		T.expect(not Effects.reloadStarted(nil, { t = 1 }, 1)) -- 탄약 없는 캐릭터(SWORD)
		T.expect(Effects.reloadStarted(nil, reloading, 2))
	end)
	T.it("시각 탄 위치: 속도×경과, 수명 이후·시작 전은 nil", function()
		local cue = { pos = { X = 0, Y = 5, Z = 0 }, dir = { X = 0, Y = 0, Z = -1 }, speed = 220, lifetime = 2, startTime = 10 }
		T.expectNear(Effects.projectilePosition(cue, 10.5).Z, -110, 1e-6)
		T.expect(Effects.projectilePosition(cue, 12.5) == nil)
		T.expect(Effects.projectilePosition(cue, 9) == nil)
		T.expect(Effects.projectilePosition({ pos = cue.pos, dir = cue.dir }, 10) == nil)
	end)
	T.it("잔상 위치: 시작점부터 거리까지 균등, 거리 0이면 모두 시작점, 잘못된 입력은 빈 목록", function()
		local pts = Effects.afterimagePoints({ X = 0, Y = 3, Z = 0 }, { X = 1, Y = 0, Z = 0 }, 8, 4)
		T.expectEqual(#pts, 4)
		T.expectEqual(pts[1].X, 0)
		T.expectEqual(pts[4].X, 6)
		for _, p in Effects.afterimagePoints({ X = 0, Y = 3, Z = 0 }, { X = 1, Y = 0, Z = 0 }, 0, 3) do T.expectEqual(p.X, 0) end
		T.expectEqual(#Effects.afterimagePoints(nil, nil, 5, 3), 0)
	end)
end)

T.describe("EffectCatalog: 교체 가능한 구조 검증", function()
	local STYLES = { Arc = true, Ring = true, Burst = true, Highlight = true, Afterimage = true, Muzzle = true, Projectile = true, Splat = true, Poof = true }
	T.it("모든 큐 정의가 유효한 style·color·lifetime 을 가진다", function()
		for name, def in Catalog.Cues do
			T.expect(STYLES[def.style], name .. " style")
			T.expect(type(def.color) == "table" and #def.color == 3, name .. " color")
			T.expect(def.lifetime > 0, name .. " lifetime")
			if def.sound then T.expect(Catalog.Sounds[def.sound] ~= nil, name .. " 사운드 정의 없음") end
		end
	end)
	T.it("EffectsModel 이 내보내는 모든 cue 이름이 카탈로그에 있다(projectile.end 제외)", function()
		local events = {
			{ type = "Swing", playerId = 1 }, { type = "Parry", playerId = 1 }, { type = "ParrySuccess", playerId = 1, attackerId = 2 },
			{ type = "Damaged", attackerId = 1, targetId = 2 }, { type = "Dodge", playerId = 1, info = {} },
			{ type = "Spawned", projectileType = "Linear", pos = { X = 0, Y = 0, Z = 0 }, dir = { X = 0, Y = 0, Z = 1 } },
			{ type = "Ended", reason = "Hit", pos = { X = 0, Y = 0, Z = 0 } }, { type = "Reloaded", playerId = 1 },
			{ type = "Died", playerId = 1 }, { type = "Respawned", playerId = 1 },
		}
		for _, ev in events do
			for _, c in Effects.translate(ev, 1) do
				if c.cue ~= "projectile.end" then T.expect(Catalog.Cues[c.cue] ~= nil, c.cue) end
			end
		end
		T.expect(Catalog.Cues["reload.start"] ~= nil) -- 상태 에지로 재생되는 큐
	end)
	T.it("Phase 1 캐릭터(SWORD/PAINTBALL) 모두 임시 무기 규격이 있고 다른 캐릭터 규격은 없다", function()
		for id in Characters do T.expect(Catalog.Weapons[id] ~= nil, id) end
		local n = 0
		for _ in Catalog.Weapons do n += 1 end
		T.expectEqual(n, 2)
	end)
	T.it("사운드 정의: id 문자열과 0~1 음량(빈 id 는 재생 생략 허용)", function()
		for name, s in Catalog.Sounds do
			T.expect(type(s.id) == "string", name)
			T.expect(s.volume > 0 and s.volume <= 1, name)
		end
	end)
end)
return true
