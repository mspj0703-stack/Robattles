--!nonstrict
-- 에셋 트랙 재생 장부(순수 로직, CLI 테스트 가능). 상태기계의 재생/정지 로그를 host 콜백으로 옮기면서
-- "같은 트랙이 두 번 재생되거나 옛 정지가 새 재생을 끊는" 중복을 막는다. 캐릭터(rig) 1개당 인스턴스 1개.
--   host.isAsset(id) → bool, host.acquire(id) → 트랙 또는 nil(id 별로 호스트가 캐시), host.play(track, speed), host.stop(track, fade)
local TrackBook = {}
TrackBook.__index = TrackBook

function TrackBook.new()
	return setmetatable({ _bySerial = {} }, TrackBook)
end

function TrackBook:apply(log, host)
	for _, entry in log do
		if entry.kind == "stopAll" then
			self:stopAll(host)
		elseif entry.kind == "stop" then
			local track = self._bySerial[entry.serial]
			if track then
				host.stop(track, 0.1)
				self._bySerial[entry.serial] = nil
			end
		elseif entry.kind == "play" and host.isAsset(entry.id) then
			local track = host.acquire(entry.id)
			if track then
				-- 같은 트랙을 가리키던 이전 serial 매핑 제거(옛 stop 이 새 재생을 끊지 않도록)
				for serial, t in self._bySerial do
					if t == track then
						self._bySerial[serial] = nil
					end
				end
				host.play(track, entry.speed or 1)
				self._bySerial[entry.serial] = track
			end
		end
	end
end

function TrackBook:stopAll(host)
	for _, track in self._bySerial do
		host.stop(track, 0.05)
	end
	table.clear(self._bySerial)
end

-- 현재 매핑된 트랙 수(테스트/진단용)
function TrackBook:count()
	local n = 0
	for _ in self._bySerial do
		n += 1
	end
	return n
end

return TrackBook
