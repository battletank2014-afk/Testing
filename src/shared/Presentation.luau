--[[
    Presentation
    Roblox-only values (Color3, Material names) that can't live in Config without
    dragging Roblox globals into modules that must stay testable outside Studio.
]]

local Presentation = {}

Presentation.CheckpointColor = Color3.fromRGB(90, 220, 120)
Presentation.EndPadColor = Color3.fromRGB(255, 200, 60)

Presentation.Palette = {
    Grasslands = { Color3.fromRGB(96, 168, 84), Color3.fromRGB(158, 214, 132) },
    NeonCaverns = { Color3.fromRGB(120, 70, 200), Color3.fromRGB(60, 220, 220) },
    FrozenPeaks = { Color3.fromRGB(210, 235, 245), Color3.fromRGB(120, 170, 210) },
    LavaCore = { Color3.fromRGB(60, 30, 30), Color3.fromRGB(230, 90, 40) },
}

return Presentation
