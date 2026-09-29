--[[
    Config
    Central tunables. Nothing in the game should hard-code a magic number;
    it belongs here so balance passes are a one-file change.
]]

local Config = {}

Config.Version = "0.1.0"

-- Progression
Config.TotalStages = 60
Config.Worlds = {
    { name = "Grasslands",     firstStage = 1,  lastStage = 15 },
    { name = "NeonCaverns",    firstStage = 16, lastStage = 30 },
    { name = "FrozenPeaks",    firstStage = 31, lastStage = 45 },
    { name = "LavaCore",       firstStage = 46, lastStage = 60 },
}

-- Anti-exploit
Config.CompleteCooldown = 0.5      -- seconds between accepted completion requests
Config.MaxCheckpointDistance = 40  -- studs; player must be near the end pad
Config.MaxRequestPerMinute = 30    -- hard rate limit on the completion remote

-- Respawn
Config.RespawnDelay = 1.5          -- seconds at the checkpoint before control returns

-- Data
Config.DataStoreName = "SkywardSprint_v1"
Config.DataStoreRetries = 4
Config.SaveInterval = 120          -- seconds between autosaves

-- Development: generate placeholder stage geometry on boot so a headless build
-- is playable. Turn off once levels are authored by hand in Studio.
Config.GeneratePlaceholderLevels = true

-- Monetization (replace with your real IDs before publishing)
Config.GamePasses = {
    SkipStage = 0,
    DoubleCoins = 0,
    VipTag = 0,
}
Config.DeveloperProducts = {
    CheckpointSave = 0,
    TrailEffect = 0,
}

-- Presentation values (Color3, etc.) live in Presentation.luau so this module
-- stays pure data and remains loadable outside Roblox for tests.

return Config
