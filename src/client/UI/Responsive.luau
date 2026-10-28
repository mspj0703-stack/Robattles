--!nonstrict
-- Presentation-only responsive profiles. Never changes gameplay, inputs or server snapshots.
local Responsive = {}
Responsive.References = {
    desktop = Vector2.new(1280, 720),
    compact = Vector2.new(1024, 576),
    portrait = Vector2.new(720, 1180),
}
function Responsive.choose(width, height)
    if width <= 0 or height <= 0 then return "desktop" end
    if height > width * 1.12 then return "portrait" end
    if width < 1150 or height < 680 then return "compact" end
    return "desktop"
end
function Responsive.fit(width, height, preferred, profile)
    local reference = Responsive.References[profile] or Responsive.References.desktop
    -- DeviceSafeInsets is applied by ScreenGui; these margins are for UI breathing room.
    local availableWidth = math.max(1, width - 16)
    local availableHeight = math.max(1, height - 16)
    local factor = math.min(availableWidth / reference.X, availableHeight / reference.Y)
    return math.max(0.05, factor * math.clamp(preferred or 1, 0.75, 1.25))
end
function Responsive.place(obj, x, y, width, height)
    obj.Position = UDim2.fromOffset(x,y)
    obj.Size = UDim2.fromOffset(width,height)
end
return Responsive
