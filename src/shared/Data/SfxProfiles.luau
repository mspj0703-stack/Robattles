--!nonstrict
-- P2-A: purely cosmetic SFX mix profiles. Keep cue names, gameplay, and remote events unchanged.
-- Profiles adjust only playback speed, gain, spatial range and crowd-sound density.
-- Original Wave assets can be uploaded as Sound objects under Assets.Sounds using cue names.
local SfxProfiles = {}

local profiles = {
    sword = { speed = 1.06, gain = 0.86, distance = 66, minGap = 0.075 },
    paint = { speed = 1.22, gain = 0.86, distance = 62, minGap = 0.080 },
    ball = { speed = 1.15, gain = 0.80, distance = 67, minGap = 0.075 },
    bomb = { speed = 0.80, gain = 0.94, distance = 88, minGap = 0.13 },
    sling = { speed = 1.30, gain = 0.78, distance = 65, minGap = 0.07 },
    hit = { speed = 1.05, gain = 0.86, distance = 56, minGap = 0.055 },
    default = { speed = 1, gain = 0.85, distance = 68, minGap = 0.09 },
}

local function familyFor(cueName, soundName)
    if type(cueName) ~= "string" then cueName = "" end
    if string.find(cueName, "^paint%.") then return "paint" end
    if string.find(cueName, "^ball%.") then return "ball" end
    if string.find(cueName, "^bomb%.") then return "bomb" end
    if string.find(cueName, "^sling%.") then return "sling" end
    if string.find(cueName, "^hit%.") then return "hit" end
    if string.find(cueName, "^sword%.") or string.find(cueName, "^skill%.")
        or string.find(cueName, "^parry%.") or string.find(cueName, "^duelist%.") then
        return "sword"
    end
    if soundName == "boom" then return "bomb" end
    if soundName == "bounce" then return "ball" end
    return "default"
end

function SfxProfiles.forCue(cueName, soundName)
    local family = familyFor(cueName, soundName)
    local def = profiles[family]
    return { family = family, speed = def.speed, gain = def.gain,
        distance = def.distance, minGap = def.minGap }
end

return SfxProfiles
