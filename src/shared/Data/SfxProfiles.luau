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

-- P2-B: per-cue mastering for the eleven uploaded-asset *candidates*.
-- No Roblox SoundId is assigned here; publishing/permissions must be confirmed separately.
local cueMix = {
    ["sword.slash"] = { speed = 1.04, gain = 0.93 },
    ["skill.storm.finish"] = { speed = 0.94, gain = 1.00 },
    ["parry.success"] = { speed = 1.00, gain = 1.00 },
    ["paint.fire"] = { speed = 1.13, gain = 0.85 },
    ["paint.explosion"] = { speed = 0.91, gain = 0.98 },
    ["ball.bounce"] = { speed = 1.12, gain = 0.90 },
    ["ball.throw.charged"] = { speed = 0.98, gain = 0.96 },
    ["bomb.explosion"] = { speed = 0.84, gain = 1.00 },
    ["sling.fire"] = { speed = 1.17, gain = 0.88 },
    ["sling.ult.precise"] = { speed = 1.06, gain = 0.96 },
    ["hit.impact"] = { speed = 1.00, gain = 0.91 },
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
    local mix = type(cueName) == "string" and cueMix[cueName] or nil
    -- Relative fine-tuning on top of the family-level sound profile.
    return { family = family, speed = def.speed * (mix and mix.speed or 1), gain = def.gain * (mix and mix.gain or 1),
        distance = def.distance, minGap = def.minGap }
end

return SfxProfiles
